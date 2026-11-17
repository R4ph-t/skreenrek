import Darwin
import Foundation
import SkreenrekCore
import Synchronization

/// Why a control call didn't get an answer from the app.
public enum ControlClientError: Error, Hashable, CustomStringConvertible {
    /// Nothing listens on the socket: the app isn't running.
    case notRunning(path: String)
    /// The app didn't answer in time.
    case timedOut(method: String)
    /// The app closed the connection before answering.
    case connectionClosed
    /// The answer wasn't a `skreenrek.control/1` response.
    case badResponse(String)

    public var description: String {
        switch self {
        case .notRunning(let path): "Nothing is listening on \(path)."
        case .timedOut(let method): "The app didn't answer \(method) in time."
        case .connectionClosed: "The app closed the connection."
        case .badResponse(let detail): "The app's answer couldn't be read: \(detail)"
        }
    }
}

/// The app answered with an error: the design spec's `{code, message, hint, exit}`.
public struct ControlRemoteError: Error, Hashable {
    public var body: ErrorBody

    public init(body: ErrorBody) {
        self.body = body
    }
}

/// One response line, as received.
public struct ControlReply: Sendable, Hashable {
    /// The whole response line, without its newline.
    public var line: Data

    /// The `result` decoded as `R`, or the app's error as `ControlRemoteError`.
    public func decode<R: Decodable>(_ type: R.Type) throws -> R {
        let response: IncomingResponse<R>
        do {
            response = try SkreenrekJSON.decoder().decode(IncomingResponse<R>.self, from: line)
        } catch {
            throw ControlClientError.badResponse(String(describing: error))
        }
        if let error = response.error { throw ControlRemoteError(body: error) }
        guard let result = response.result else { throw ControlClientError.badResponse("no result") }
        return result
    }
}

/// A connection to the app's control socket. One request at a time per connection: calls queue up in order.
///
/// Connecting waits at most 2 s. A request waits at most `requestTimeout` for its answer, except `pick` (bounded by
/// its own timeout) and `record.wait`, which wait as long as it takes. Blocking I/O runs on the connection's own
/// dispatch queue, never on the Swift concurrency pool.
public final class ControlClient: Sendable {
    public static let connectTimeout: TimeInterval = 2
    /// Long enough for a resize with retries or for finalizing a long clip.
    public static let requestTimeout: TimeInterval = 30

    public let path: URL
    public let client: ClientInfo
    private let fd: Int32
    private let queue = DispatchQueue(label: "it.fraime.skreenrek.control.client")
    private struct State {
        var nextID = 1
        var buffer = Data()
        var closed = false
    }
    private let state = Mutex(State())

    private init(path: URL, client: ClientInfo, fd: Int32) {
        self.path = path
        self.client = client
        self.fd = fd
    }

    deinit {
        Darwin.close(fd)
    }

    /// Connects to the app. Throws `notRunning` when nothing listens on `path`.
    public static func connect(
        path: URL = ControlPaths.socketURL(), client: ClientInfo, timeout: TimeInterval = connectTimeout
    ) async throws -> ControlClient {
        let queue = DispatchQueue(label: "it.fraime.skreenrek.control.connect")
        let fd: Int32 = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let fd = try UnixSocket.make()
                    let code = UnixSocket.connect(fd, path: path.path, timeout: timeout)
                    guard code == 0 else {
                        Darwin.close(fd)
                        throw ControlClientError.notRunning(path: path.path)
                    }
                    continuation.resume(returning: fd)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return ControlClient(path: path, client: client, fd: fd)
    }

    /// Sends one request and returns the response line. `timeout` nil uses the method's default.
    public func send<P: Encodable & Sendable>(
        _ method: ControlProtocol.Method, params: P, timeout: TimeInterval? = nil
    ) async throws -> ControlReply {
        try await send(method.rawValue, params: params, timeout: timeout ?? Self.timeout(for: method))
    }

    /// Sends one request with no params.
    public func send(_ method: ControlProtocol.Method, timeout: TimeInterval? = nil) async throws -> ControlReply {
        try await send(method, params: NoParams?.none, timeout: timeout)
    }

    /// Sends any method name (tests use it for unknown methods). `timeout` nil waits forever.
    public func send<P: Encodable & Sendable>(_ method: String, params: P?, timeout: TimeInterval?) async throws
        -> ControlReply
    {
        let id = state.withLock { s in
            defer { s.nextID += 1 }
            return s.nextID
        }
        var line = try SkreenrekJSON.encode(OutgoingRequest(id: id, method: method, params: params, client: client))
        line.append(0x0A)
        return try await exchange(line, method: method, timeout: timeout)
    }

    /// Sends raw bytes (one line, newline included) and reads one response line.
    public func sendRaw(_ line: Data, timeout: TimeInterval? = requestTimeout) async throws -> ControlReply {
        try await exchange(line, method: "request", timeout: timeout)
    }

    /// Calls a method and decodes its result.
    public func call<R: Decodable, P: Encodable & Sendable>(
        _ method: ControlProtocol.Method, params: P, as type: R.Type, timeout: TimeInterval? = nil
    ) async throws -> R {
        try await send(method, params: params, timeout: timeout).decode(type)
    }

    public func call<R: Decodable>(_ method: ControlProtocol.Method, as type: R.Type, timeout: TimeInterval? = nil)
        async throws -> R
    {
        try await send(method, timeout: timeout).decode(type)
    }

    /// Closes the connection; a call waiting for its answer fails with `connectionClosed`.
    public func close() {
        let first = state.withLock { s in
            defer { s.closed = true }
            return !s.closed
        }
        if first { shutdown(fd, SHUT_RDWR) }
    }

    public static func timeout(for method: ControlProtocol.Method) -> TimeInterval? {
        method.waitsIndefinitely ? nil : requestTimeout
    }

    private func exchange(_ line: Data, method: String, timeout: TimeInterval?) async throws -> ControlReply {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result { try self.exchangeBlocking(line, method: method, timeout: timeout) })
            }
        }
    }

    private func exchangeBlocking(_ line: Data, method: String, timeout: TimeInterval?) throws -> ControlReply {
        let deadline = UnixSocket.deadline(after: timeout)
        guard !state.withLock({ $0.closed }) else { throw ControlClientError.connectionClosed }
        if !UnixSocket.writeAll(fd, line, deadline: deadline) {
            if let deadline, deadline.timeIntervalSinceNow <= 0 { throw ControlClientError.timedOut(method: method) }
            // The app may have answered and closed mid-write (a request over its line limit): read that answer, and
            // report `connectionClosed` only when there is none.
        }
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let reply = state.withLock({ s -> Data? in
                guard let newline = s.buffer.firstIndex(of: 0x0A) else { return nil }
                let reply = Data(s.buffer[s.buffer.startIndex..<newline])
                s.buffer.removeSubrange(s.buffer.startIndex...newline)
                return reply
            }) {
                return ControlReply(line: reply)
            }
            guard UnixSocket.wait(fd, events: Int16(POLLIN), deadline: deadline) else {
                throw ControlClientError.timedOut(method: method)
            }
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                state.withLock { $0.buffer.append(contentsOf: chunk[0..<n]) }
            } else if n < 0, errno == EAGAIN || errno == EINTR {
                continue
            } else {
                throw ControlClientError.connectionClosed
            }
        }
    }
}
