import Foundation
import SkreenrekCore

/// Turns one request line into one response line by calling the controller. Pure apart from the controller, so it is
/// tested without a socket too.
public struct ControlRouter: Sendable {
    public let controller: SkreenrekController
    public let hello: HelloBody

    public init(controller: SkreenrekController, hello: HelloBody) {
        self.controller = controller
        self.hello = hello
    }

    /// Answers one request line (without its newline). The response ends with a newline.
    public func respond(to line: Data) async -> Data {
        let envelope: RequestEnvelope
        do {
            envelope = try SkreenrekJSON.decoder().decode(RequestEnvelope.self, from: line)
        } catch {
            return Self.line(
                ErrorResponse(
                    id: nil,
                    error: SkreenrekError.usage(
                        message: "The request isn't valid JSON.",
                        hint: "Send one JSON object per line, as \(ControlProtocol.name) says."
                    ).body))
        }
        let id = envelope.id
        guard envelope.v == ControlProtocol.version else {
            let sent = envelope.v.map(String.init) ?? "none"
            return Self.line(
                ErrorResponse(
                    id: id,
                    error: ErrorBody(
                        code: "internal",
                        message: "This command speaks control protocol \(sent), but the running Skreenrek app "
                            + "speaks \(ControlProtocol.version).",
                        hint: ControlProtocol.mismatchHint, exit: 1)))
        }
        guard let name = envelope.method, let method = ControlProtocol.Method(rawValue: name) else {
            return Self.line(
                ErrorResponse(
                    id: id,
                    error: SkreenrekError.usage(
                        message: "\"\(envelope.method ?? "")\" isn't a Skreenrek control method.",
                        hint: ControlProtocol.mismatchHint
                    ).body))
        }
        let client = envelope.client ?? ClientInfo(kind: .cli)
        do {
            return try await dispatch(method, line: line, id: id, client: client)
        } catch let error as SkreenrekError {
            await controller.reportActionFailure(error)
            return Self.line(ErrorResponse(id: id, error: error.body))
        } catch {
            return Self.line(
                ErrorResponse(id: id, error: SkreenrekError.internal(message: error.localizedDescription).body))
        }
    }

    private func dispatch(_ method: ControlProtocol.Method, line: Data, id: Int?, client: ClientInfo) async throws
        -> Data
    {
        let controller = controller
        switch method {
        case .hello:
            return Self.line(ResultResponse(id: id, result: hello))
        case .windows:
            let p = try Self.params(WindowsParams.self, method, line) ?? WindowsParams()
            return Self.line(ResultResponse(id: id, result: try await controller.windows(app: p.app)))
        case .pick:
            let p = try Self.params(PickParams.self, method, line) ?? PickParams()
            let timeout = p.timeoutSeconds ?? PickParams.defaultTimeout
            guard timeout > 0, timeout.isFinite else {
                throw SkreenrekError.usage(
                    message: "The pick timeout must be more than 0 seconds.", hint: "Pass a positive timeoutSeconds.")
            }
            return Self.line(ResultResponse(id: id, result: try await controller.pick(timeout: timeout)))
        case .resize:
            guard let p = try Self.params(ResizeParams.self, method, line) else {
                throw Self.badParams(method, detail: "width and height are required")
            }
            let readback = try await controller.resize(
                query: p.windowQuery, size: PixelSize(width: p.width, height: p.height),
                allowInexact: p.allowInexact ?? false)
            return Self.line(ResultResponse(id: id, result: readback))
        case .recordStart:
            let p = try Self.params(StartParams.self, method, line) ?? StartParams()
            let body = try await controller.start(p, startedBy: client.kind, client: client.name)
            return Self.line(ResultResponse(id: id, result: body))
        case .recordStop:
            return Self.line(ResultResponse(id: id, result: try await controller.stop()))
        case .recordDiscard:
            return Self.line(ResultResponse(id: id, result: try await controller.discard()))
        case .recordWait:
            return Self.line(ResultResponse(id: id, result: try await controller.waitForEnd()))
        case .status:
            return Self.line(ResultResponse(id: id, result: await controller.status()))
        case .last:
            return Self.line(ResultResponse(id: id, result: try await controller.last()))
        case .doctor:
            return Self.line(ResultResponse(id: id, result: await controller.doctor()))
        }
    }

    /// The request's params as `P`, nil when absent. Wrong types or missing fields are a `usage` error.
    static func params<P: Decodable>(_ type: P.Type, _ method: ControlProtocol.Method, _ line: Data) throws -> P? {
        do {
            return try SkreenrekJSON.decoder().decode(RequestParams<P>.self, from: line).params
        } catch let error as DecodingError {
            throw badParams(method, detail: describe(error))
        }
    }

    static func badParams(_ method: ControlProtocol.Method, detail: String) -> SkreenrekError {
        .usage(
            message: "The params for \(method.rawValue) aren't valid: \(detail).",
            hint: "Check the parameter names and types for \(method.rawValue).")
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.filter { $0.stringValue != "params" }.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, _): return "\(key.stringValue) is missing"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            let at = path(context)
            return at.isEmpty ? "params must be an object" : "\(at) has the wrong type"
        case .valueNotFound(_, let context):
            let at = path(context)
            return at.isEmpty ? "params must be an object" : "\(at) can't be null"
        @unknown default:
            return "they can't be read"
        }
    }

    static func line<T: Encodable>(_ value: T) -> Data {
        var data: Data
        do {
            data = try SkreenrekJSON.encode(value)
        } catch {
            data = Data(
                #"{"error":{"code":"internal","exit":1,"hint":"Run: skreenrek doctor","message":"The response couldn't be encoded."},"v":1}"#
                    .utf8)
        }
        data.append(0x0A)
        return data
    }
}
