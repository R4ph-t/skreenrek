import AppKit
import SkreenrekCore
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// Draws stand-in traffic lights in the title bar band, for the offscreen renders.
    var drawsTrafficLights = false
    @Environment(\.colorScheme) private var scheme
    public init(model: OnboardingModel) { self.model = model }
    init(model: OnboardingModel, drawsTrafficLights: Bool) {
        self.model = model
        self.drawsTrafficLights = drawsTrafficLights
    }
    /// The size of every step below the title bar: 24 pt margins, and the footer 24 pt below step 4's agent rows.
    /// Connect errors make the window taller.
    public static let size = CGSize(width: 520, height: 400)
    static let footerGap: CGFloat = 24
    /// The transparent title bar's band over the content, where the traffic lights sit (as in Settings).
    static let titleBarHeight = SettingsChromeMetrics.titleBarHeight
    /// The whole window: the title bar band, then `size`.
    public static var windowSize: CGSize { CGSize(width: size.width, height: size.height + titleBarHeight) }
    public var body: some View {
        VStack(spacing: 0) {
            SettingsTitleBarBand(drawsTrafficLights: drawsTrafficLights)
            content
        }
        .frame(width: Self.size.width)
        .background(SkreenrekSurface(scheme).base.color)
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.step == .agents ? UIStrings.Onboarding.agentsTitle : UIStrings.Onboarding.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.step == .agents ? UIStrings.Onboarding.agentsIntroduction : UIStrings.Onboarding.introduction)
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let permission = model.step.permission { permissionStep(permission) } else {
                    agents
                    if let summary = model.connectSummary {
                        Text(summary).font(.system(size: 12))
                            .foregroundStyle(model.allConnectsFailed ? AnyShapeStyle(Self.errorColor) : AnyShapeStyle(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // The footer sits 24 pt below step 4's content, the tallest step; the others keep the same window size.
            Spacer(minLength: Self.footerGap)
            HStack(spacing: 8) {
                Text(UIStrings.Onboarding.step(model.stepNumber, of: model.steps.count))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if model.step == .agents {
                    Button(model.skipTitle) { model.skip() }
                    Button(UIStrings.Onboarding.connect) { model.connect() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    if model.needsRelaunch {
                        Button(UIStrings.Onboarding.quitAndReopen) { model.quitAndReopen() }
                    }
                    if let request = model.requestTitle {
                        Button(request) { model.requestCurrent() }
                            .keyboardShortcut(model.canContinue ? nil : .defaultAction)
                    }
                    Button(model.continueTitle) { model.advance() }
                        .keyboardShortcut(model.canContinue ? .defaultAction : nil)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canContinue)
                }
            }
        }
        .padding(24).frame(width: Self.size.width).frame(minHeight: Self.size.height)
    }

    /// One permission: the progress of all three, the row with its live status and System Settings link, and one
    /// plain sentence on what macOS will ask.
    private func permissionStep(_ permission: Permission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            PermissionRow(title: Self.title(permission), detail: Self.detail(permission),
                          status: model.status(of: permission)) { model.openSystemSettings() }
                .frame(height: 56)
                .padding(.horizontal, 12).surfaceCell()
            // One sentence: what macOS will ask, or, once it asked, the relaunch it needs.
            Text(model.needsRelaunch ? UIStrings.Onboarding.relaunchNote
                 : model.waitsForScreenRecording ? UIStrings.Onboarding.directCaptureWaiting
                 : UIStrings.Onboarding.explanation(permission))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three permissions in order: a green check once allowed, the current one in the primary colour.
    private var progress: some View {
        HStack(spacing: 16) {
            ForEach(OnboardingStep.permissions, id: \.self) { step in
                if let permission = step.permission {
                    let allowed = model.status(of: permission) == .allowed
                    HStack(spacing: 4) {
                        Image(systemName: allowed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(allowed ? Color(nsColor: .systemGreen) : .secondary)
                        Text(Self.title(permission))
                            .foregroundStyle(step == model.step ? .primary : .secondary)
                    }
                    .font(.system(size: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(Self.title(permission)), \(allowed ? UIStrings.Settings.allowed : UIStrings.Onboarding.notAllowed)")
                }
            }
        }
    }

    static func title(_ permission: Permission) -> String {
        switch permission {
        case .screenRecording: UIStrings.Settings.screenRecording
        case .directCapture: UIStrings.Onboarding.directCapture
        case .accessibility: UIStrings.Settings.accessibility
        }
    }

    static func detail(_ permission: Permission) -> String {
        switch permission {
        case .screenRecording: UIStrings.Settings.screenRecordingDetail
        case .directCapture: UIStrings.Onboarding.directCaptureDetail
        case .accessibility: UIStrings.Settings.accessibilityDetail
        }
    }

    private static let errorColor = Color(nsColor: .systemRed)

    private var agents: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { model.selected.contains(row.agent) }, set: {
                        if $0 { model.selected.insert(row.agent) } else { model.selected.remove(row.agent) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.agent.name).font(.system(size: 13))
                            Text(model.didConnect(row.agent) ? UIStrings.Onboarding.connected : row.detail)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox).disabled(!row.detected)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    if let error = model.connectError(for: row.agent) {
                        Text(error).font(.system(size: 12)).foregroundStyle(Self.errorColor)
                            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 12)
                // Drawn over the row's top edge, so the separators don't change the card's height.
                .overlay(alignment: .top) { if index > 0 { SurfaceRowSeparator() } }
            }
        }.surfaceCell()
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let model: OnboardingModel
    private var window: NSWindow?
    private var timer: Timer?
    /// The window closed.
    var onClose: () -> Void = {}
    init(model: OnboardingModel) {
        self.model = model
        super.init()
        model.didComplete = { [weak self] in self?.window?.close() }
    }
    /// The window follows the content's height, so connect errors never push the buttons out of it.
    static func makeWindow(model: OnboardingModel) -> NSWindow {
        let host = NSHostingController(rootView: OnboardingView(model: model))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        // The title stays for the Window menu and VoiceOver; the bar itself is the window's own surface.
        window.title = UIStrings.Onboarding.title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SkreenrekSurface.baseColor
        window.setContentSize(OnboardingView.windowSize)
        window.isReleasedWhenClosed = false
        return window
    }

    /// Opens on the first missing permission. A visible window only refreshes, so agent retries don't steal focus or
    /// ask macOS again.
    func show() {
        guard window?.isVisible != true else { model.refresh(); return }
        model.begin()
        if window == nil {
            let window = Self.makeWindow(model: model)
            window.delegate = self
            window.center()
            self.window = window
        }
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil; onClose() }
}

/// An onboarding permission with its status: Allowed (green check) or Open System Settings….
struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    let open: () -> Void

    var body: some View {
        // One 12 pt minimum gap between the text and the status. The text column takes the room up to the trailing
        // status first, and the status keeps its own size.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if status == .allowed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).frame(width: 16)
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text(UIStrings.Settings.allowed).foregroundStyle(.secondary)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed").font(.system(size: 16)).frame(width: 16)
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    Button(UIStrings.Settings.openSystemSettings, action: open)
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
    }
}
