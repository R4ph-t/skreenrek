import Foundation
import SkreenrekCore
import Testing

@Suite struct OutputFolderTests {
    static let paris = TimeZone(identifier: "Europe/Paris")!
    /// 2026-11-17 10:42:07 in Paris (09:42:07 UTC).
    static let date = Date(timeIntervalSince1970: 1_794_908_527)

    @Test func theDefaultParentIsMoviesSkreenrek() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(OutputFolder.defaultParent(home: home).path == "/Users/someone/Movies/Skreenrek")
    }

    @Test func folderNamesUseLocalTime() {
        #expect(OutputFolder.baseName(date: Self.date, slug: "safari", timeZone: Self.paris) == "2026-11-17_104207_safari")
        #expect(
            OutputFolder.baseName(date: Self.date, slug: "safari", timeZone: TimeZone(identifier: "UTC")!)
                == "2026-11-17_094207_safari")
    }

    @Test(arguments: [
        ("Safari", "safari"),
        ("Visual Studio Code", "visual-studio-code"),
        ("Café Ünïcode", "cafe-unicode"),
        ("  --Hello__World!!  ", "hello-world"),
        ("iTerm2", "iterm2"),
        ("微信", ""),
        ("Ｆｕｌｌｗｉｄｔｈ", "fullwidth"),
        (String(repeating: "abcdefghij", count: 5), "abcdefghijabcdefghijabcdefghijabcdefghij"),
        ("abcdefghij abcdefghij abcdefghij abcdefghi xyz", "abcdefghij-abcdefghij-abcdefghij-abcdefg"),
        ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ])
    func slugs(input: String, expected: String) {
        let slug = OutputFolder.slug(input)
        #expect(slug == expected)
        #expect(slug.count <= 40)
        #expect(slug.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
    }

    @Test func theSlugComesFromTheAppTheRegionOrTheName() {
        let region = CaptureTarget.region(PixelRect(x: 0, y: 0, width: 100, height: 100), displayId: 1)
        #expect(OutputFolder.slug(for: .window(Fixtures.safari), name: nil) == "safari")
        #expect(OutputFolder.slug(for: region, name: nil) == "region")
        #expect(OutputFolder.slug(for: .window(Fixtures.safari), name: "Login Flow") == "login-flow")
        #expect(OutputFolder.slug(for: region, name: "!!!") == "region")
        var nameless = Fixtures.safari
        nameless.app = "微信"
        #expect(OutputFolder.slug(for: .window(nameless), name: nil) == "window")
    }

    @Test func createMakesTheParentAndAddsASuffixOnACollision() throws {
        let temp = try TempFolder("folders")
        defer { temp.cleanUp() }
        let parent = temp.url.appendingPathComponent("Movies/Skreenrek", isDirectory: true)
        func make(_ name: String? = nil) throws -> URL {
            try OutputFolder.create(
                in: parent, target: .window(Fixtures.safari), name: name, date: Self.date, timeZone: Self.paris)
        }
        let first = try make()
        let second = try make()
        let third = try make()
        #expect(first.lastPathComponent == "2026-11-17_104207_safari")
        #expect(second.lastPathComponent == "2026-11-17_104207_safari-2")
        #expect(third.lastPathComponent == "2026-11-17_104207_safari-3")
        #expect(try make("Demo").lastPathComponent == "2026-11-17_104207_demo")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: third.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func anUnwritableParentFailsBeforeRecording() throws {
        let temp = try TempFolder("unwritable")
        defer { temp.cleanUp() }
        let parent = try temp.clipFolder("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        #expect(throws: SkreenrekError.recordingFailed(.notWritable)) {
            try OutputFolder.create(in: parent, target: .window(Fixtures.safari), name: nil, date: Self.date)
        }
        #expect(throws: SkreenrekError.recordingFailed(.notWritable)) {
            try OutputFolder.create(
                in: parent.appendingPathComponent("deeper"), target: .window(Fixtures.safari), name: nil,
                date: Self.date)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }
}
