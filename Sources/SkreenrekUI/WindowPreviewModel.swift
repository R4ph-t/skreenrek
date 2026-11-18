import Foundation
import SkreenrekCore

/// Waits before the preview spinner appears. Production sleeps. Tests resume it by hand, so nothing sleeps in a test.
protocol PreviewDelay: Sendable {
    func wait(milliseconds: Int) async
}

struct SystemPreviewDelay: PreviewDelay {
    func wait(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// Loads one window still when the panel opens. The panel is already on screen before the capture returns, the
/// capture runs off the main thread, and a second open takes a new still. A spinner appears only if the still is
/// still missing after 300 ms.
@MainActor
final class WindowPreviewModel {
    private let source: any WindowPreviewSource
    private let permissions: any PermissionProbe
    private let delay: any PreviewDelay
    private var generation = 0
    /// The last still that came back, so a closed window can show it dimmed.
    private var lastStill: WindowStill?
    /// Called on the main actor when the phase or the spinner changes.
    var onChange: (() -> Void)?
    private(set) var phase: PanelPreviewPhase = .noWindow
    private(set) var showSpinner = false
    /// The window the current capture belongs to. A tick of the open panel does not capture again.
    private(set) var requestedWindow: WindowID?
    /// The title of the last window we were asked to photograph.
    private(set) var lastTitle: String?

    init(source: any WindowPreviewSource, permissions: any PermissionProbe, delay: any PreviewDelay = SystemPreviewDelay()) {
        self.source = source
        self.permissions = permissions
        self.delay = delay
    }

    /// Drops an in-flight still. The next open starts a new one.
    func cancel() {
        generation += 1
        showSpinner = false
    }

    /// Starts a still of `window`, or settles immediately when there is nothing to photograph or a capture
    /// permission is missing. Returns before the capture does. `scale` is the screen's backing scale.
    func load(window: WindowInfo?, hasRegion: Bool, scale: CGFloat) {
        generation += 1
        let generation = generation
        showSpinner = false
        requestedWindow = window?.id
        if let window {
            lastTitle = UIStrings.Menu.windowTitle(app: window.app, title: window.title)
        }
        if let missing = permissions.missingCapturePermission {
            phase = .permissionMissing(missing)
            onChange?()
            return
        }
        guard let window else {
            phase = hasRegion ? .region : .noWindow
            onChange?()
            return
        }
        phase = .loading
        onChange?()
        let box = PanelMetrics.capturePixels(scale: scale)
        let source = source
        let delay = delay
        Task { @MainActor [weak self] in
            await delay.wait(milliseconds: PanelMetrics.spinnerDelayMilliseconds)
            guard let self, self.generation == generation, self.isLoading else { return }
            self.showSpinner = true
            self.onChange?()
        }
        Task { @MainActor [weak self] in
            let outcome = await Self.capture(source, window, box)
            guard let self, self.generation == generation else { return }
            guard let outcome else { return }
            switch outcome {
            case .ready(let still):
                self.lastStill = still
                self.phase = .ready(still)
            case .windowClosed:
                self.phase = .windowClosed(self.lastStill)
            case .permissionMissing(let permission):
                self.phase = .permissionMissing(permission)
            case .failed:
                self.phase = .failed
            case .loading, .noWindow, .region:
                self.phase = outcome
            }
            self.showSpinner = false
            self.onChange?()
        }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Nil when the capture was cancelled, so a closed panel doesn't flash a failure.
    private static func capture(
        _ source: any WindowPreviewSource, _ window: WindowInfo, _ box: PixelSize
    ) async -> PanelPreviewPhase? {
        let result: Result<WindowStill, WindowPreviewError>? = await Task.detached {
            do {
                return .success(try await source.captureStill(of: window, fitting: box))
            } catch let error as WindowPreviewError {
                return .failure(error)
            } catch is CancellationError {
                return nil
            } catch {
                return .failure(.failed("Preview capture failed."))
            }
        }.value
        guard let result else { return nil }
        switch result {
        case .success(let still): return .ready(still)
        case .failure(.permissionMissing(let permission)): return .permissionMissing(permission)
        case .failure(.windowClosed): return .windowClosed(nil)
        case .failure(.failed): return .failed
        }
    }
}
