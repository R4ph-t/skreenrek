import Foundation
import SkreenrekCore
import Testing

/// Release tags compare the semver way, GitHub's answer parses, automatic checks wait 24 h, and Homebrew is used only
/// for the cask's install.
@Suite struct UpdatesTests {
    func v(_ text: String) throws -> SemanticVersion { try #require(SemanticVersion(text), "\(text)") }

    @Test func parsesTagsWithAndWithoutTheV() throws {
        #expect(try v("v1.0.3") == SemanticVersion(major: 1, minor: 0, patch: 3))
        #expect(try v("1.0.3") == SemanticVersion(major: 1, minor: 0, patch: 3))
        #expect(try v("V2") == SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(try v("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(try v("v1.1.0-beta.2+build.7") == SemanticVersion(major: 1, minor: 1, patch: 0, prerelease: "beta.2"))
        #expect(try v(" v1.0.2\n").description == "1.0.2")
        for bad in ["", "v", "1..2", "1.0.x", "1.0.0.0", "latest", "1.0.0-", "-1.0.0", "1.0.٣"] {
            #expect(SemanticVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func comparesNumericallyNotAsText() throws {
        #expect(try v("1.0.10") > v("1.0.9"))
        #expect(try v("1.10.0") > v("1.9.9"))
        #expect(try v("10.0.0") > v("9.99.99"))
        #expect(try v("v1.0.3") > v("1.0.2"))
        #expect(try v("1.0.2") == v("v1.0.2"))
        #expect(try !(v("1.0.2") > v("1.0.2")))
        #expect(try v("2.0.0") > v("1.99.99"))
    }

    @Test func preReleasesComeBeforeTheirRelease() throws {
        #expect(try v("1.1.0-beta.1") < v("1.1.0"))
        #expect(try v("1.1.0-beta.1") > v("1.0.9"))
        #expect(try v("1.1.0-alpha") < v("1.1.0-beta"))
        #expect(try v("1.1.0-beta.2") < v("1.1.0-beta.10"))
        #expect(try v("1.1.0-beta") < v("1.1.0-beta.1"))
        #expect(try v("1.1.0-1") < v("1.1.0-alpha"))
    }

    @Test func parsesGitHubsLatestRelease() throws {
        let body = Data(
            #"{"tag_name":"v1.0.10","html_url":"https://github.com/R4ph-t/skreenrek/releases/tag/v1.0.10","name":"x"}"#
                .utf8)
        let release = try GitHubReleases.parse(body)
        #expect(release.version == (try v("1.0.10")))
        #expect(release.pageURL.absoluteString == "https://github.com/R4ph-t/skreenrek/releases/tag/v1.0.10")
        // No html_url: the releases page.
        let bare = try GitHubReleases.parse(Data(#"{"tag_name":"1.0.3"}"#.utf8))
        #expect(bare.pageURL == GitHubReleases.releasesPage)
        #expect(throws: GitHubReleases.ParseError.badTag("nightly")) {
            try GitHubReleases.parse(Data(#"{"tag_name":"nightly"}"#.utf8))
        }
        #expect(throws: GitHubReleases.ParseError.notJSON) { try GitHubReleases.parse(Data("<html>".utf8)) }
        #expect(GitHubReleases.latestURL.absoluteString
            == "https://api.github.com/repos/R4ph-t/skreenrek/releases/latest")
    }

    @Test func automaticChecksWaitTwentyFourHours() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: last))
        #expect(!UpdateSchedule.isDue(lastCheck: last, now: last))
        #expect(!UpdateSchedule.isDue(lastCheck: last, now: last.addingTimeInterval(23 * 3600 + 3599)))
        #expect(UpdateSchedule.isDue(lastCheck: last, now: last.addingTimeInterval(24 * 3600)))
        #expect(UpdateSchedule.isDue(lastCheck: last, now: last.addingTimeInterval(72 * 3600)))
        // A clock set back doesn't block checks for days.
        #expect(UpdateSchedule.isDue(lastCheck: last, now: last.addingTimeInterval(-60)))
    }

    @Test func homebrewOnlyForTheCasksInstall() {
        #expect(UpdateMethod.decide(bundlePath: "/Applications/Skreenrek.app", brewExists: true) == .homebrew)
        #expect(UpdateMethod.decide(bundlePath: "/Applications/Skreenrek.app/", brewExists: true) == .homebrew)
        #expect(UpdateMethod.decide(bundlePath: "/Applications/Skreenrek.app", brewExists: false) == .releasePage)
        #expect(UpdateMethod.decide(bundlePath: "/Users/you/Downloads/Skreenrek.app", brewExists: true) == .releasePage)
        #expect(UpdateMethod.decide(bundlePath: "/Users/you/dev/skreenrek/.build/debug", brewExists: true) == .releasePage)
        #expect(UpdateMethod.decide(bundlePath: "/Applications/../tmp/Skreenrek.app", brewExists: true) == .releasePage)
        #expect(UpdateMethod.brewPath == "/opt/homebrew/bin/brew")
        #expect(UpdateMethod.caskArguments == ["upgrade", "--cask", "r4ph-t/skreenrek/skreenrek"])
    }
}
