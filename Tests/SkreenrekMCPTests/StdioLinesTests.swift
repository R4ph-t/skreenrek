import Foundation
@testable import SkreenrekMCP
import Testing

@Suite(.timeLimit(.minutes(1))) struct StdioLinesTests {
    @Test func splitsLinesAcrossChunksAndKeepsTheLastUnterminatedLine() {
        var splitter = LineSplitter(maxLineBytes: 100)
        #expect(splitter.feed(Array("{\"a\":".utf8)) == [])
        #expect(splitter.feed(Array("1}\n{\"b\"".utf8)) == [Data("{\"a\":1}".utf8)])
        #expect(splitter.feed(Array(":2}\n\n".utf8)) == [Data("{\"b\":2}".utf8), Data()])
        #expect(splitter.finish() == nil)
        #expect(splitter.feed(Array("tail".utf8)) == [])
        #expect(splitter.finish() == Data("tail".utf8))
    }

    @Test func anOverlongLineIsCutSoItFailsToParseAndTheNextLineIsWhole() {
        var splitter = LineSplitter(maxLineBytes: 4)
        let lines = splitter.feed(Array("123456789\nok\n".utf8))
        #expect(lines == [Data("12345".utf8), Data("ok".utf8)])
    }

    @Test func theStreamReadsAPipeUntilItCloses() async throws {
        let pipe = Pipe()
        let stream = StdioLines.stream(fileDescriptor: pipe.fileHandleForReading.fileDescriptor)
        pipe.fileHandleForWriting.write(Data("one\ntwo\nthree".utf8))
        try pipe.fileHandleForWriting.close()
        let lines = try await within("the stream to end") {
            var lines: [String] = []
            for await line in stream { lines.append(String(decoding: line, as: UTF8.self)) }
            return lines
        }
        #expect(lines == ["one", "two", "three"])
    }
}
