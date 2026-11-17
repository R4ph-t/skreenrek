import Darwin
import Foundation

/// Reads newline-delimited messages from a file descriptor (stdin) on a thread of its own, so blocking reads never
/// sit on the Swift concurrency pool. The stream ends at end of file.
public enum StdioLines {
    /// Longer lines are cut to this many bytes, so they fail to parse instead of growing the buffer without bound.
    public static let maxLineBytes = 4 * 1024 * 1024

    public static func stream(fileDescriptor fd: Int32, maxLineBytes: Int = maxLineBytes) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let thread = Thread {
            var splitter = LineSplitter(maxLineBytes: maxLineBytes)
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    for line in splitter.feed(chunk[0..<n]) { continuation.yield(line) }
                } else if n < 0, errno == EINTR || errno == EAGAIN {
                    continue
                } else {
                    break
                }
            }
            if let rest = splitter.finish() { continuation.yield(rest) }
            continuation.finish()
        }
        thread.name = "skreenrek.mcp.stdin"
        thread.start()
        return stream
    }
}

/// Splits bytes into lines (without the newline). A line over the limit keeps its first `maxLineBytes` + 1 bytes.
struct LineSplitter {
    let maxLineBytes: Int
    private var buffer = Data()
    private var overflowed = false

    init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    mutating func feed<C: Collection>(_ bytes: C) -> [Data] where C.Element == UInt8 {
        var lines: [Data] = []
        for byte in bytes {
            if byte == 0x0A {
                lines.append(buffer)
                buffer = Data()
                overflowed = false
            } else if buffer.count <= maxLineBytes {
                buffer.append(byte)
            } else {
                overflowed = true
            }
        }
        return lines
    }

    /// The last line when the input didn't end with a newline.
    mutating func finish() -> Data? {
        defer { buffer = Data() }
        return buffer.isEmpty && !overflowed ? nil : buffer
    }
}
