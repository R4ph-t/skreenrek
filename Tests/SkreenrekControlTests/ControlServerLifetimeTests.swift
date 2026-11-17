import Foundation
import SkreenrekControl
import SkreenrekCore
import Synchronization
import Testing

/// Counts closed server connections and lets a test wait for a count, without polling.
final class ClosedConnections: Sendable {
    private let state = Mutex<(count: Int, waiters: [(Int, CheckedContinuation<Void, Never>)])>((0, []))

    func closed() {
        let ready = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.count += 1
            let count = s.count
            defer { s.waiters.removeAll { $0.0 <= count } }
            return s.waiters.filter { $0.0 <= count }.map(\.1)
        }
        for waiter in ready { waiter.resume() }
    }

    var count: Int { state.withLock { $0.count } }

    func wait(for count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.count >= count { return true }
                s.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

/// No connection outlives its server. A read source left armed after the server went away used to fire in a busy loop
/// at end of stream, one CPU core per leaked connection, starving every other test in the process.
@Suite(.timeLimit(.minutes(1))) struct ControlServerLifetimeTests {
    static func echoServer(_ temp: ShortTemp, closed: ClosedConnections) -> ControlServer {
        ControlServer(path: temp.socket, connectionClosed: { closed.closed() }) { line in line + [0x0A] }
    }

    /// Connects and gets one answer, so the server has accepted the connection.
    static func connected(_ temp: ShortTemp) async throws -> ControlClient {
        let client = try await ControlClient.connect(path: temp.socket, client: ClientInfo(kind: .cli))
        _ = try await client.sendRaw(Data("{}\n".utf8), timeout: 10)
        return client
    }

    @Test func stopEndsConnectionsThatAreStillOpen() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let closed = ClosedConnections()
        let server = Self.echoServer(temp, closed: closed)
        try server.start()
        let client = try await Self.connected(temp)
        server.stop()
        try await within("the connection to close after stop") { await closed.wait(for: 1) }
        #expect(server.connectionCount == 0)
        withExtendedLifetime(client) {}
    }

    @Test func aServerDroppedWithoutStopStillClosesItsConnections() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let closed = ClosedConnections()
        var server: ControlServer? = Self.echoServer(temp, closed: closed)
        try server?.start()
        let client = try await Self.connected(temp)
        server = nil
        // The client hangs up after the server is gone: the server side still sees end of stream and closes.
        client.close()
        try await within("the connection to close after the server was dropped") { await closed.wait(for: 1) }
        #expect(closed.count == 1)
    }

    @Test func aClientHangingUpClosesItsConnection() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let closed = ClosedConnections()
        let server = Self.echoServer(temp, closed: closed)
        try server.start()
        defer { server.stop() }
        for _ in 0..<5 {
            let client = try await Self.connected(temp)
            client.close()
        }
        try await within("five connections to close") { await closed.wait(for: 5) }
        #expect(server.connectionCount == 0)
    }
}
