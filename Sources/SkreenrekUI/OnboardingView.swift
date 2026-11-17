import AppKit
import SkreenrekCore
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    public init(model: OnboardingModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.step == 1 ? UIStrings.Onboarding.title : UIStrings.Onboarding.agentsTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(model.step == 1 ? UIStrings.Onboarding.introduction : UIStrings.Onboarding.agentsIntroduction)
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if model.step == 1 { permissions } else { agents }
            Spacer(minLength: 0)
            HStack {
                Text(UIStrings.Onboarding.step(model.step)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if model.step == 1 {
                    Button(UIStrings.Onboarding.continueButton) { model.continueToAgents() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(!model.canContinue)
                } else {
                    Button(UIStrings.Onboarding.skip) { model.skip() }
                    Button(UIStrings.Onboarding.connect) { model.connect() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24).frame(width: 520).frame(minHeight: 496)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                PermissionRow(title: UIStrings.Settings.screenRecording, detail: UIStrings.Settings.screenRecordingDetail,
                              status: model.screenRecording) { model.request(.screenRecording) }
                    .frame(height: 56)
                Divider()
                PermissionRow(title: UIStrings.Settings.accessibility, detail: UIStrings.Settings.accessibilityDetail,
                              status: model.accessibility) { model.request(.accessibility) }
                    .frame(height: 56)
            }
            .padding(.horizontal, 12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Text(UIStrings.Onboarding.accessibilityNote).font(.system(size: 12)).foregroundStyle(.secondary)
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
    func show(missingPermission: Bool = false) {
        if missingPermission { model.showMissingPermission() }
        model.refresh()
        // Agent retries should refresh the visible form without repeatedly taking focus from the user.
        guard window?.isVisible != true else { return }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
            window.title = UIStrings.Onboarding.title
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 496))
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
