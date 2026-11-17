import AppKit
import Observation
import ServiceManagement
import SkreenrekCore
import SwiftUI

/// Open at login. The app passes `MainAppLoginItem`; tests and `render-ui` pass a stand-in.
@MainActor
public protocol LoginItemService: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService.mainApp`: registers Skreenrek.app itself as a login item.
@MainActor
public final class MainAppLoginItem: LoginItemService {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// What the Settings window shows besides the stored values: permission status (read-only, never a prompt) and the
/// login item.
@MainActor
@Observable
public final class SettingsPanelState {
    public var screenRecording: PermissionStatus
    public var accessibility: PermissionStatus
    public var openAtLogin: Bool
    /// Shown under the Open at login row after a failed change.
    public var loginError: String?
    public var agents: AgentsPanelState?

    @ObservationIgnored private let permissions: any PermissionProbe
    @ObservationIgnored private let loginItem: any LoginItemService

    public init(permissions: any PermissionProbe, loginItem: any LoginItemService, agents: AgentsPanelState? = nil) {
        self.permissions = permissions
        self.loginItem = loginItem
        self.agents = agents
        screenRecording = permissions.screenRecording
        accessibility = permissions.accessibility
        openAtLogin = loginItem.isEnabled
    }

    /// Reads the permission and login item state again (when the window shows or the app becomes active).
    public func refresh() {
        screenRecording = permissions.screenRecording
        accessibility = permissions.accessibility
        openAtLogin = loginItem.isEnabled
        agents?.refresh()
    }

    public func setOpenAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = enabled ? UIStrings.Settings.loginItemOnFailed : UIStrings.Settings.loginItemOffFailed
        }
        openAtLogin = loginItem.isEnabled
    }
}

/// Callbacks from the Settings window to the app.
@MainActor
public struct SettingsActions {
    public var chooseOutputFolder: () -> Void
    public var openPrivacyPane: (Permission) -> Void
    public var settingsChanged: () -> Void

    public init(
        chooseOutputFolder: @escaping () -> Void, openPrivacyPane: @escaping (Permission) -> Void,
        settingsChanged: @escaping () -> Void
    ) {
        self.chooseOutputFolder = chooseOutputFolder
        self.openPrivacyPane = openPrivacyPane
        self.settingsChanged = settingsChanged
    }

    public static let none = SettingsActions(chooseOutputFolder: {}, openPrivacyPane: { _ in }, settingsChanged: {})
}

/// The one Settings pane: a 480 pt grouped form, no tabs.
public struct SettingsView: View {
    public static let width: CGFloat = 480

    @Bindable var store: SettingsStore
    @Bindable var panel: SettingsPanelState
    let actions: SettingsActions
    let version: String

    public init(store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions, version: String) {
        self.store = store
        self.panel = panel
        self.actions = actions
        self.version = version
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent(UIStrings.Settings.outputFolder) {
                    HStack(spacing: 8) {
                        Text(store.outputFolderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.outputFolder.path)
                        Button(UIStrings.Settings.choose) { actions.chooseOutputFolder() }
                    }
                }
                Picker(UIStrings.Settings.defaultFrameRate, selection: $store.fps) {
                    ForEach(FrameRate.allCases, id: \.self) { rate in
                        Text(UIStrings.Menu.fps(rate)).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(UIStrings.Settings.showCursor, isOn: $store.cursor).toggleStyle(.checkbox)
                Toggle(UIStrings.Settings.writeClickEvents, isOn: $store.events).toggleStyle(.checkbox)
                Toggle(UIStrings.Settings.showRecordingIndicator, isOn: $store.hud).toggleStyle(.checkbox)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        UIStrings.Settings.openAtLogin,
                        isOn: Binding(get: { panel.openAtLogin }, set: { panel.setOpenAtLogin($0) })
                    )
                    .toggleStyle(.checkbox)
                    if let error = panel.loginError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent(UIStrings.Settings.stopShortcut) {
                    Text(UIStrings.Settings.stopShortcutKeys).foregroundStyle(.secondary)
                }
            }
            if let agents = panel.agents { AgentsSection(panel: agents) }
            Section {
                PermissionRow(
                    title: UIStrings.Settings.screenRecording, detail: UIStrings.Settings.screenRecordingDetail,
                    status: panel.screenRecording
                ) { actions.openPrivacyPane(.screenRecording) }
                PermissionRow(
                    title: UIStrings.Settings.accessibility, detail: UIStrings.Settings.accessibilityDetail,
                    status: panel.accessibility
                ) { actions.openPrivacyPane(.accessibility) }
            } header: {
                Text(UIStrings.Settings.permissions)
            } footer: {
                Text(UIStrings.Settings.version(version))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.controllerSettings) { actions.settingsChanged() }
    }
}

/// Screen Recording or Accessibility, with its status: Allowed (green check) or Open System Settings….
struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    /// The v2 direction mockups (A and C): "Open Settings…" and a one-line detail. The shipping window leaves it off.
    var compact = false
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .layoutPriority(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if status == .allowed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).frame(width: 16)
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text(UIStrings.Settings.allowed).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed").font(.system(size: 16)).frame(width: 16)
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    Button(
                        compact ? UIStrings.Directions.openSettings : UIStrings.Settings.openSystemSettings,
                        action: open)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
