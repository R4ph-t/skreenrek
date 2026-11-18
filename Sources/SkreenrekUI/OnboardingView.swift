import AppKit
import SkreenrekCore
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    public init(model: OnboardingModel) { self.model = model }
    /// One fixed size for every step: 24 pt margins, and the footer 24 pt below step 4's agent rows.
    public static let size = CGSize(width: 520, height: 400)
    static let footerGap: CGFloat = 24
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.step == .agents ? UIStrings.Onboarding.agentsTitle : UIStrings.Onboarding.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.step == .agents ? UIStrings.Onboarding.agentsIntroduction : UIStrings.Onboarding.introduction)
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let permission = model.step.permission { permissionStep(permission) } else { agents }
            }
            // The footer sits 24 pt below step 4's content, the tallest step; the others keep the same window size.
            Spacer(minLength: Self.footerGap)
            HStack(spacing: 8) {
                Text(UIStrings.Onboarding.step(model.stepNumber, of: model.steps.count))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if model.step == .agents {
                    Button(UIStrings.Onboarding.skip) { model.skip() }
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// One permission: the progress of all three, the row with its live status and System Settings link, and one
    /// plain sentence on what macOS will ask.
    private func permissionStep(_ permission: Permission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            PermissionRow(title: Self.title(permission), detail: Self.detail(permission),
                          status: model.status(of: permission)) { model.openSystemSettings() }
                .frame(height: 56)
                .padding(.horizontal, 12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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

    private var agents: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.agents) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { model.selected.contains(row.agent) }, set: {
                        if $0 { model.selected.insert(row.agent) } else { model.selected.remove(row.agent) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.agent.name).font(.system(size: 13))
                            Text(row.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox).disabled(!row.detected)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    ForEach(Array(model.results.filter { $0.agent == row.agent && !$0.success }.enumerated()), id: \.offset) { _, result in
                        Text(result.message).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.padding(.horizontal, 12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let model: OnboardingModel
    private var window: NSWindow?
    private var timer: Timer?
    init(model: OnboardingModel) {
        self.model = model
        super.init()
        model.didComplete = { [weak self] in self?.window?.close() }
    }
    /// Opens on the first missing permission. A visible window only refreshes, so agent retries don't steal focus or
    /// ask macOS again.
    func show() {
        guard window?.isVisible != true else { model.refresh(); return }
        model.begin()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
            window.title = UIStrings.Onboarding.title
            window.styleMask = [.titled, .closable]
            window.setContentSize(OnboardingView.size)
            window.isReleasedWhenClosed = false
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
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }
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
