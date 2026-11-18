import Foundation
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Synchronization
import Testing

/// The update check's state machine, its 24 h throttle, the Homebrew path, the Settings row and the dropdown's
/// footer line. Every check goes to `FakeReleaseFeed`; nothing touches the network or the clock.
@Suite struct UpdateCheckerTests {
    /// A settable clock for the throttle.
    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 2_000_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(hours: Double) { value.withLock { $0 = $0.addingTimeInterval(hours * 3600) } }
    }

    /// Opened URLs and relaunches.
    @MainActor final class Effects {
        var opened: [URL] = []
        var relaunches = 0
    }

    @MainActor
    static func checker(
        current: String = "1.0.2", feed: FakeReleaseFeed, installer: FakeUpdateInstaller? = nil,
        method: UpdateMethod = .releasePage, defaults: UserDefaults = freshDefaults(), clock: Clock = Clock(),
        effects: Effects
    ) -> UpdateChecker {
        UpdateChecker(
            current: current, feed: feed, installer: installer, method: method, defaults: defaults,
            now: { clock.now }, openURL: { effects.opened.append($0) }, relaunch: { effects.relaunches += 1 })
    }

    static func freshDefaults() -> UserDefaults {
        let name = "skreenrek.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(
            version: SemanticVersion(version)!,
            pageURL: URL(string: "https://github.com/R4ph-t/skreenrek/releases/tag/v\(version)")!)
    }

    // MARK: - State machine

    @Test func newerReleaseIsAvailable() async throws {
        try await onMain("available") {
            let effects = Effects()
            let checker = Self.checker(current: "1.0.9", feed: FakeReleaseFeed(latest: "1.0.10"), effects: effects)
            #expect(checker.state == .idle)
            await checker.checkNow()
            #expect(checker.state == .available(Self.release("1.0.10")))
            #expect(checker.availableVersion?.description == "1.0.10")
        }
    }

    @Test func sameOrOlderReleaseIsUpToDate() async throws {
        try await onMain("up to date") {
            let effects = Effects()
            let same = Self.checker(feed: FakeReleaseFeed(latest: "1.0.2"), effects: effects)
            await same.checkNow()
            #expect(same.state == .upToDate(current: SemanticVersion("1.0.2")!))
            #expect(same.availableVersion == nil)
            let older = Self.checker(feed: FakeReleaseFeed(latest: "1.0.1"), effects: effects)
            await older.checkNow()
            #expect(older.state == .upToDate(current: SemanticVersion("1.0.2")!))
        }
    }

    @Test func showsCheckingWhileTheRequestRuns() async throws {
        let feed = FakeReleaseFeed(latest: "1.0.3", gated: true)
        let checker = try await onMain("make") { Self.checker(feed: feed, effects: Effects()) }
        let task = Task { @MainActor in await checker.checkNow() }
        var calls = feed.calls.makeAsyncIterator()
        _ = await calls.next()
        try await onMain("checking") {
            #expect(checker.state == .checking)
            // A second check while one runs doesn't start another request.
            await checker.checkNow()
            #expect(feed.callCount == 1)
        }
        feed.release()
        await task.value
        try await onMain("done") { #expect(checker.state == .available(Self.release("1.0.3"))) }
    }

    @Test func failureIsQuietAndRetryWorks() async throws {
        try await onMain("failed") {
            let feed = FakeReleaseFeed(.failure(.init()))
            let checker = Self.checker(feed: feed, effects: Effects())
            await checker.checkNow()
            #expect(checker.state == .failed)
            #expect(checker.availableVersion == nil)
            let row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.button.title == "Retry" && row.button.action == .check && row.quiet)
            feed.setResult(.success(Self.release("1.0.4")))
            await checker.perform(.check)
            #expect(checker.state == .available(Self.release("1.0.4")))
            // A later failure keeps the update it already knows about.
            feed.setResult(.failure(.init()))
            await checker.checkNow()
            #expect(checker.state == .available(Self.release("1.0.4")))
        }
    }

    @Test func remembersTheLastAnswerAcrossLaunches() async throws {
        try await onMain("remembered") {
            let defaults = Self.freshDefaults()
            let clock = Clock()
            let first = Self.checker(feed: FakeReleaseFeed(latest: "1.0.3"), defaults: defaults, clock: clock, effects: Effects())
            await first.checkIfDue()
            // Relaunched within 24 h: no request, the update still shows.
            let feed = FakeReleaseFeed(latest: "1.0.3")
            let second = Self.checker(feed: feed, defaults: defaults, clock: clock, effects: Effects())
            #expect(second.state == .available(Self.release("1.0.3")))
            await second.checkIfDue()
            #expect(feed.callCount == 0)
            // Once 1.0.3 is the running version, the remembered answer reads up to date.
            let updated = Self.checker(current: "1.0.3", feed: feed, defaults: defaults, clock: clock, effects: Effects())
            #expect(updated.state == .upToDate(current: SemanticVersion("1.0.3")!))
        }
    }

    // MARK: - Throttle

    @Test func automaticChecksRunAtMostOnceEvery24Hours() async throws {
        try await onMain("throttle") {
            let clock = Clock()
            let feed = FakeReleaseFeed(latest: "1.0.2")
            let checker = Self.checker(feed: feed, clock: clock, effects: Effects())
            await checker.checkIfDue()  // launch
            #expect(feed.callCount == 1)
            #expect(checker.lastCheck == clock.now)
            clock.advance(hours: 1)
            await checker.checkIfDue()  // the hourly timer
            clock.advance(hours: 22.9)
            await checker.checkIfDue()
            #expect(feed.callCount == 1)
            clock.advance(hours: 0.1)
            await checker.checkIfDue()
            #expect(feed.callCount == 2)
            // Check for Updates ignores the throttle, and restarts it.
            await checker.checkNow()
            #expect(feed.callCount == 3)
            clock.advance(hours: 23)
            await checker.checkIfDue()
            #expect(feed.callCount == 3)
        }
    }

    @Test func aFailedCheckAlsoWaits24Hours() async throws {
        try await onMain("failed throttle") {
            let clock = Clock()
            let feed = FakeReleaseFeed(.failure(.init()))
            let checker = Self.checker(feed: feed, clock: clock, effects: Effects())
            await checker.checkIfDue()
            clock.advance(hours: 12)
            await checker.checkIfDue()
            #expect(feed.callCount == 1)
        }
    }

    // MARK: - Installing

    @Test func homebrewUpgradesThenOffersRelaunch() async throws {
        try await onMain("homebrew") {
            let effects = Effects()
            let installer = FakeUpdateInstaller(lines: ["==> Upgrading 1 outdated package:", "", "🍺  done"])
            let checker = Self.checker(
                feed: FakeReleaseFeed(latest: "1.0.3"), installer: installer, method: .homebrew, effects: effects)
            await checker.checkNow()
            var row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.button.title == "Update" && row.button.prominent)
            await checker.perform(row.button.action)
            #expect(installer.runs == 1)
            #expect(checker.state == .installed(Self.release("1.0.3")))
            #expect(!checker.isInstalling)
            #expect(effects.opened.isEmpty)
            row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.button.title == "Relaunch" && row.button.action == .relaunch)
            #expect(row.detail == "Skreenrek 1.0.3 is installed. Relaunch to use it.")
            // Checking again can't knock the installed state over.
            await checker.checkNow()
            #expect(checker.state == .installed(Self.release("1.0.3")))
            await checker.perform(.relaunch)
            #expect(effects.relaunches == 1)
        }
    }

    @Test func homebrewFailureOffersTheReleasePage() async throws {
        try await onMain("homebrew failed") {
            let effects = Effects()
            let installer = FakeUpdateInstaller(fails: true)
            let checker = Self.checker(
                feed: FakeReleaseFeed(latest: "1.0.3"), installer: installer, method: .homebrew, effects: effects)
            await checker.checkNow()
            await checker.update()
            #expect(checker.state == .installFailed(Self.release("1.0.3")))
            let row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.button.title == "Open Release Page" && row.quiet)
            await checker.perform(row.button.action)
            #expect(effects.opened == [Self.release("1.0.3").pageURL])
            #expect(installer.runs == 1)
        }
    }

    @Test func withoutHomebrewUpdateOpensTheReleasePage() async throws {
        try await onMain("release page") {
            let effects = Effects()
            // No installer means the release page, whatever the method says.
            let checker = Self.checker(feed: FakeReleaseFeed(latest: "1.0.3"), method: .homebrew, effects: effects)
            #expect(checker.method == .releasePage)
            await checker.checkNow()
            let row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.button.title == "Download…")
            await checker.update()
            #expect(effects.opened == [Self.release("1.0.3").pageURL])
            #expect(checker.state == .available(Self.release("1.0.3")))
            #expect(effects.relaunches == 0)
        }
    }

    @Test func onChangeFollowsEveryStep() async throws {
        try await onMain("onChange") {
            let checker = Self.checker(feed: FakeReleaseFeed(latest: "1.0.3"), effects: Effects())
            var seen: [UpdateState] = []
            checker.onChange = { seen.append(checker.state) }
            await checker.checkNow()
            #expect(seen == [.checking, .available(Self.release("1.0.3"))])
        }
    }

    // MARK: - Settings row

    @Test func rowCopyForEveryState() {
        let current = SemanticVersion("1.0.2")!
        let info = Self.release("1.0.3")
        func row(_ state: UpdateState, _ method: UpdateMethod = .homebrew) -> UpdateRowModel {
            UpdateRowModel(state: state, current: current, method: method)
        }
        #expect(row(.idle).detail == "Skreenrek 1.0.2")
        #expect(row(.idle).button.title == "Check for Updates")
        #expect(row(.checking).detail == "Checking…")
        #expect(row(.checking).busy && !row(.checking).button.enabled)
        #expect(row(.upToDate(current: current)).detail == "Skreenrek 1.0.2 is up to date.")
        #expect(row(.upToDate(current: current)).button.action == .check)
        #expect(row(.available(info)).detail == "Skreenrek 1.0.3 is available. You have 1.0.2.")
        #expect(row(.available(info)).button.action == .update)
        #expect(row(.available(info), .releasePage).button.title == "Download…")
        #expect(row(.failed).detail == "Couldn't check for updates.")
        #expect(row(.installing(info, line: nil)).detail == "Updating with Homebrew…")
        #expect(row(.installing(info, line: "==> Upgrading skreenrek")).detail == "==> Upgrading skreenrek")
        #expect(row(.installing(info, line: nil)).busy && !row(.installing(info, line: nil)).button.enabled)
        #expect(row(.installFailed(info)).detail == "Homebrew couldn't update Skreenrek.")
        // Only the actionable update states use the prominent button.
        let prominent = [UpdateState.idle, .checking, .upToDate(current: current), .available(info), .failed,
                         .installing(info, line: nil), .installed(info), .installFailed(info)]
            .filter { row($0).button.prominent }
        #expect(prominent == [.available(info), .installing(info, line: nil), .installed(info)])
    }

    /// What's new is the release body, and only while that release is available. Blank notes stay hidden.
    @Test func availableUpdateShowsItsNotes() {
        let current = SemanticVersion("1.0.2")!
        let url = URL(string: "https://github.com/R4ph-t/skreenrek/releases/tag/v1.0.3")!
        let notes = "### Added\n\n- A compact Record pill"
        let info = ReleaseInfo(version: SemanticVersion("1.0.3")!, pageURL: url, notes: notes)
        let row = UpdateRowModel(state: .available(info), current: current, method: .homebrew)
        #expect(row.notes == notes)
        let blank = ReleaseInfo(version: info.version, pageURL: url, notes: " \n\t")
        #expect(UpdateRowModel(state: .available(blank), current: current, method: .homebrew).notes == nil)
        let states: [UpdateState] = [
            .idle, .checking, .upToDate(current: current), .failed, .installing(info, line: nil), .installed(info),
            .installFailed(info),
        ]
        for state in states {
            #expect(UpdateRowModel(state: state, current: current, method: .homebrew).notes == nil)
        }
    }

    @Test func notesComeFromTheFeedAndSurviveRelaunch() async throws {
        try await onMain("notes") {
            let defaults = Self.freshDefaults()
            let notes = "### Fixed\n\n- Sandboxed shells get a clear error"
            let checker = Self.checker(
                feed: FakeReleaseFeed(latest: "1.0.3", notes: notes), defaults: defaults, effects: Effects())
            await checker.checkNow()
            let row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
            #expect(row.notes == notes)
            // Relaunched within 24 h: no new request, and the notes are still the ones GitHub returned.
            let feed = FakeReleaseFeed(latest: "9.0.0", notes: "ignored")
            let remembered = Self.checker(feed: feed, defaults: defaults, effects: Effects())
            #expect(feed.callCount == 0)
            #expect(remembered.state == .available(
                ReleaseInfo(version: SemanticVersion("1.0.3")!, pageURL: Self.release("1.0.3").pageURL, notes: notes)))
            let again = UpdateRowModel(
                state: remembered.state, current: remembered.current, method: remembered.method)
            #expect(again.notes == notes)
        }
    }

    // MARK: - Dropdown footer

    @Test func footerShowsUpdateAvailableOnlyWhenThereIsOne() throws {
        func footerItems(_ update: String?) throws -> [MenuItemModel] {
            var context = try #require(RenderSamples.states.first { $0.name == "idle" }).context
            context.updateAvailable = update
            return DropdownModel.rows(for: context).compactMap { row -> MenuItemModel? in
                if case .item(let item) = row { return item }
                return nil
            }
        }
        let none = try footerItems(nil)
        #expect(!none.contains { $0.action == .showUpdate })
        let items = try footerItems("1.0.3")
        let update = try #require(items.first { $0.action == .showUpdate })
        #expect(update.title == "Update available · 1.0.3")
        // It leads the footer, before Open Output Folder.
        let titles = items.map(\.title)
        #expect(titles.suffix(4) == ["Update available · 1.0.3", "Open Output Folder", "Settings…", "Quit Skreenrek"])
        let context = try #require(RenderSamples.states.first { $0.name == "updateavailable" }).context
        #expect(DropdownModel.symbol(for: .showUpdate) == "arrow.down.circle")
        #expect(DropdownModel.iconTint(for: update, context: context) == .accent)
        // While recording too.
        var recording = try #require(RenderSamples.states.first { $0.name == "recording" }).context
        recording.updateAvailable = "1.0.3"
        #expect(MenuModel.entries(for: recording).contains(.item(update)))
    }
}
