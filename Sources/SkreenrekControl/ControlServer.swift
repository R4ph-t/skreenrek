import Darwin
import Foundation
import SkreenrekCore
import os

/// Serves `skreenrek.control/1` on a stream Unix socket (never TCP).
///
/// The folder holding the socket is mode 0700 and the socket 0600; only peers with the allowed uid (this user, by
/// default) are served. A stale socket file with no listener is replaced; a live one means another instance runs, and
/// `start()` throws `alreadyRunning`. Several clients may connect; each connection answers its requests in order, and
/// the controller actor serializes the operations themselves.
///
/// `@unchecked Sendable`: every mutable property is only touched on `queue` (a serial queue), and each connection's
/// writes run on its own serial queue.
public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data

    public enum StartError: Error, Hashable, CustomStringConvertible {
        /// Another Skreenrek answers on this socket.
        case alreadyRunning(path: String)
        /// The path is longer than a Unix socket path can be (104 bytes).
        case pathTooLong(path: String)
        case failed(String)

        public var description: String {
            switch self {
            case .alreadyRunning(let path): "Another Skreenrek is already running (\(path))."
            case .pathTooLong(let path): "The socket path is too long for a Unix socket: \(path)"
            case .failed(let message): message
            }
        }
    }

    public static let backlog: Int32 = 16
    /// The longest request line accepted. A longer one is answered with `usage` and the connection is closed.
    public static let maxLineBytes = 1 << 20

    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "control")

    public let path: URL
    private let handler: Handler
    private let allowedUID: uid_t
    private let queue = DispatchQueue(label: "it.fraime.skreenrek.control.server", qos: .userInitiated)

    private var listenSource: (any DispatchSourceRead)?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var rejectedPeers = 0
    private let connectionClosed: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - allowedUID: the only uid served; this user by default (tests pass another one to check refusal).
    ///   - connectionClosed: called once per connection after its file descriptor is closed (tests use it to check
    ///     that no connection outlives the server).
    public init(
        path: URL, allowedUID: uid_t = geteuid(), connectionClosed: (@Sendable () -> Void)? = nil,
        handler: @escaping Handler
    ) {
        self.path = path
        self.allowedUID = allowedUID
        self.connectionClosed = connectionClosed
        self.handler = handler
    }

    /// A server dropped without `stop()` still ends every connection: a read source left armed on a socket at end of
    /// stream would fire forever and burn a CPU core.
    deinit {
        listenSource?.cancel()
        for connection in connections.values {
            connection.source?.cancel()
            shutdown(connection.fd, SHUT_RDWR)
        }
    }

    public var isRunning: Bool { queue.sync { listenSource != nil } }

    /// Connections open right now.
    public var connectionCount: Int { queue.sync { connections.count } }

    /// Peers refused because their uid wasn't allowed.
    public var rejectedPeerCount: Int { queue.sync { rejectedPeers } }

    public func start() throws {
        try queue.sync { try startOnQueue() }
    }

    /// Stops listening, removes the socket file and ends every connection: reading stops at once, and each
    /// connection closes as soon as its request in flight (if any) has answered.
    public func stop() {
        queue.sync {
            guard let source = listenSource else { return }
            listenSource = nil
            source.cancel()
            unlink(path.path)
            for connection in connections.values {
                connection.source?.cancel()
                shutdown(connection.fd, SHUT_RDWR)
            }
        }
    }

    // MARK: - Listening

    private func startOnQueue() throws {
        guard listenSource == nil else { return }
        let socketPath = path.path
        guard UnixSocket.address(socketPath) != nil else { throw StartError.pathTooLong(path: socketPath) }
        try prepareFolder(path.deletingLastPathComponent())
        try clearStaleSocket(socketPath)

        let fd: Int32
        do {
            fd = try UnixSocket.make()
        } catch {
            throw StartError.failed("\(error)")
        }
        guard UnixSocket.bind(fd, UnixSocket.address(socketPath)!) == 0 else {
            let code = errno
            close(fd)
            if code == EADDRINUSE { throw StartError.alreadyRunning(path: socketPath) }
            throw StartError.failed("\(UnixSocket.Failure(call: "bind", code: code))")
        }
        guard chmod(socketPath, 0o600) == 0, listen(fd, Self.backlog) == 0 else {
            let code = errno
            close(fd)
            unlink(socketPath)
            throw StartError.failed("\(UnixSocket.Failure(call: "listen", code: code))")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { close(fd) }
        listenSource = source
        source.resume()
        Self.log.info("Listening on the control socket.")
    }

    /// Creates the folder with mode 0700, and tightens it to 0700 when this user owns it.
    private func prepareFolder(_ folder: URL) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw StartError.failed("Couldn't create \(folder.path): \(error.localizedDescription)")
        }
        var info = stat()
        if stat(folder.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o777 != 0o700 {
            chmod(folder.path, 0o700)
        }
    }

    /// Removes a socket file nobody listens on. A live socket means another instance runs.
    private func clearStaleSocket(_ socketPath: String) throws {
        var info = stat()
        guard lstat(socketPath, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw StartError.failed("\(socketPath) exists and isn't a socket.")
        }
        if UnixSocket.isLive(socketPath) { throw StartError.alreadyRunning(path: socketPath) }
        unlink(socketPath)
    }

    private func acceptAll(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            UnixSocket.setNonBlocking(fd)
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == allowedUID else {
                rejectedPeers += 1
                Self.log.notice("Refused a control connection from another user.")
                close(fd)
                continue
            }
            open(fd)
        }
    }

    // MARK: - Connections

    private func open(_ fd: Int32) {
        let connection = Connection(fd: fd, closed: connectionClosed)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        let (lines, continuation) = AsyncStream<Data>.makeStream()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        connection.source = source
        // The read handler never depends on the server being alive: it always reads, so end of stream always cancels
        // the source. (Returning early once the server was gone left the source firing in a busy loop.)
        source.setEventHandler { [connection] in
            if !ControlServer.read(connection, into: continuation) { connection.source?.cancel() }
        }
        source.setCancelHandler { [weak self, connection] in
            connection.readDone = true
            continuation.finish()
            if let self { self.closeIfDone(connection, key: key) } else { connection.closeIfDone() }
        }
        source.resume()

        let handler = handler
        let queue = queue
        // Requests run at user-initiated priority, so recording and its control never wait behind background work.
        Task(priority: .userInitiated) { [weak self] in
            for await line in lines {
                // An empty line is the reader's mark for a request over the limit.
                guard !line.isEmpty else {
                    _ = await connection.write(ControlServer.tooLongReply)
                    break
                }
                let reply = await handler(line)
                guard await connection.write(reply) else { break }
            }
            let server = self
            queue.async {
                connection.consumerDone = true
                connection.source?.cancel()
                if let server { server.closeIfDone(connection, key: key) } else { connection.closeIfDone() }
            }
        }
    }

    /// Reads what is there and yields each complete line. False at end of stream or on an error.
    private static func read(_ connection: Connection, into continuation: AsyncStream<Data>.Continuation) -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = chunk.withUnsafeMutableBytes { Darwin.read(connection.fd, $0.baseAddress, $0.count) }
            if n > 0 {
                connection.buffer.append(contentsOf: chunk[0..<n])
                while let newline = connection.buffer.firstIndex(of: 0x0A) {
                    var line = connection.buffer[connection.buffer.startIndex..<newline]
                    connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
                    if line.last == 0x0D { line = line.dropLast() }
                    if !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { continuation.yield(Data(line)) }
                }
                if connection.buffer.count > Self.maxLineBytes {
                    connection.buffer = Data()
                    continuation.yield(Data())
                    return false
                }
            } else if n < 0, errno == EAGAIN || errno == EINTR {
                return true
            } else {
                return false
            }
        }
    }

    static let tooLongReply = ControlRouter.line(
        ErrorResponse(
            id: nil,
            error: SkreenrekError.usage(
                message: "The request is longer than 1 MiB.", hint: "Send one JSON object per line, under 1 MiB."
            ).body))

    private func closeIfDone(_ connection: Connection, key: ObjectIdentifier) {
        if connection.closeIfDone() { connections[key] = nil }
    }

    /// One client connection. `buffer`, `source` and the flags are only touched on the server queue.
    private final class Connection: @unchecked Sendable {
        let fd: Int32
        var buffer = Data()
        var source: (any DispatchSourceRead)?
        var readDone = false
        var consumerDone = false
        var closed = false
        private let onClosed: (@Sendable () -> Void)?
        private let writeQueue = DispatchQueue(label: "it.fraime.skreenrek.control.write", qos: .userInitiated)

        init(fd: Int32, closed: (@Sendable () -> Void)?) {
            self.fd = fd
            self.onClosed = closed
        }

        /// Closes the descriptor once reading and the request consumer are both done. True when it closed now.
        @discardableResult
        func closeIfDone() -> Bool {
            guard readDone, consumerDone, !closed else { return false }
            closed = true
            close(fd)
            onClosed?()
            return true
        }

        /// Writes a reply off the cooperative pool. False when the client is gone.
        func write(_ data: Data) async -> Bool {
            await withCheckedContinuation { continuation in
                writeQueue.async { [fd] in
                    continuation.resume(returning: UnixSocket.writeAll(fd, data, deadline: UnixSocket.deadline(after: 10)))
                }
            }
        }
    }
}
