import Darwin
import Foundation

/// Small POSIX helpers for the control socket: stream Unix sockets only, never TCP.
enum UnixSocket {
    /// `sun_path` holds 104 bytes on macOS, including the terminating zero.
    static let maxPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    struct Failure: Error, CustomStringConvertible {
        var call: String
        var code: Int32

        var description: String { "\(call) failed: \(String(cString: strerror(code)))" }
    }

    static func address(_ path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count <= maxPathBytes else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    /// A new non-blocking stream Unix socket that never raises SIGPIPE.
    static func make() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(call: "socket", code: errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setNonBlocking(fd)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func bind(_ fd: Int32, _ addr: sockaddr_un) -> Int32 {
        var addr = addr
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func connect(_ fd: Int32, _ addr: sockaddr_un) -> Int32 {
        var addr = addr
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// Connects a non-blocking socket, waiting up to `timeout` seconds. Returns 0 or an errno.
    static func connect(_ fd: Int32, path: String, timeout: TimeInterval) -> Int32 {
        guard let addr = address(path) else { return ENAMETOOLONG }
        if connect(fd, addr) == 0 { return 0 }
        let code = errno
        guard code == EINPROGRESS || code == EAGAIN || code == EINTR else { return code }
        guard wait(fd, events: Int16(POLLOUT), deadline: deadline(after: timeout)) else { return ETIMEDOUT }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return errno }
        return error
    }

    /// Whether something listens at `path` right now.
    static func isLive(_ path: String) -> Bool {
        guard let fd = try? make() else { return false }
        defer { close(fd) }
        return connect(fd, path: path, timeout: 0.5) == 0
    }

    static func deadline(after seconds: TimeInterval?) -> Date? {
        seconds.map { Date().addingTimeInterval($0) }
    }

    /// Waits until `fd` is ready for `events`, or the deadline passes (false). Hangups and errors count as ready, so
    /// the next read or write reports them.
    static func wait(_ fd: Int32, events: Int16, deadline: Date?) -> Bool {
        while true {
            var timeout: Int32 = -1
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 { return false }
                timeout = Int32(min(remaining * 1000, Double(Int32.max)).rounded(.up))
            }
            var pfd = pollfd(fd: fd, events: events, revents: 0)
            let n = poll(&pfd, 1, timeout)
            if n > 0 { return true }
            if n == 0 { return false }
            if errno != EINTR { return true }
        }
    }

    /// Writes all of `data` to a non-blocking socket. False when the peer is gone or the deadline passes.
    static func writeAll(_ fd: Int32, _ data: Data, deadline: Date?) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, base + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0, errno == EAGAIN || errno == EINTR {
                    guard wait(fd, events: Int16(POLLOUT), deadline: deadline) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }
}
