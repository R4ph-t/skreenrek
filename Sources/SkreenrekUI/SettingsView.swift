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

/// The one Settings pane: a 480 pt grouped form, no tabs. An 88 pt hero (the V1 app icon, the name, the version and
/// the project link), then rows with monochrome icon tiles and trailing switches. The only colour in the window is
/// the accent on the switches, the selected frame rate and the link.
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
            Section { hero }
            Section {
                SettingsRow(symbol: "folder.fill") {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(store.outputFolderDisplayPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(store.outputFolder.path)
                            Button(UIStrings.Settings.choose) { actions.chooseOutputFolder() }
                        }
                    } label: {
                        Text(UIStrings.Settings.outputFolder)
                    }
                }
                SettingsRow(symbol: "speedometer") {
                    LabeledContent {
                        FrameRateSegments(selection: $store.fps)
                    } label: {
                        Text(UIStrings.Settings.defaultFrameRate)
                    }
                }
                switchRow(UIStrings.Settings.showCursor, symbol: "cursorarrow", isOn: $store.cursor)
                switchRow(UIStrings.Settings.writeClickEvents, symbol: "cursorarrow.click", isOn: $store.events)
                switchRow(UIStrings.Settings.showRecordingIndicator, symbol: "record.circle", isOn: $store.hud)
                SettingsRow(symbol: "power") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            UIStrings.Settings.openAtLogin,
                            isOn: Binding(get: { panel.openAtLogin }, set: { panel.setOpenAtLogin($0) })
                        )
                        .modifier(SettingsSwitch())
                        if let error = panel.loginError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                SettingsRow(symbol: "keyboard") {
                    LabeledContent {
                        Text(UIStrings.Settings.stopShortcutKeys).foregroundStyle(.secondary)
                    } label: {
                        Text(UIStrings.Settings.stopShortcut)
                    }
                }
            }
            if let agents = panel.agents { AgentsSection(panel: agents) }
            Section {
                SettingsRow(symbol: "rectangle.dashed.badge.record") {
                    PermissionRow(
                        title: UIStrings.Settings.screenRecording, detail: UIStrings.Settings.screenRecordingDetail,
                        status: panel.screenRecording
                    ) { actions.openPrivacyPane(.screenRecording) }
                }
                SettingsRow(symbol: "accessibility") {
                    PermissionRow(
                        title: UIStrings.Settings.accessibility, detail: UIStrings.Settings.accessibilityDetail,
                        status: panel.accessibility
                    ) { actions.openPrivacyPane(.accessibility) }
                }
            } header: {
                SettingsSectionHeader(title: UIStrings.Settings.permissions)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.controllerSettings) { actions.settingsChanged() }
    }

    private func switchRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol) {
            Toggle(title, isOn: isOn).modifier(SettingsSwitch())
        }
    }

    /// The V1 app icon (icon-dark) at 56, the name at 20 semibold (SF Pro, the system stand-in for the wordmark's
    /// Inter SemiBold) over the version, and the project link on the right, 88 pt tall.
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            KitAppIcon(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(UIStrings.productName).font(.system(size: 20, weight: .semibold))
                Text(version).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(UIStrings.Settings.version(version))
            Spacer(minLength: 8)
            if let url = URL(string: UIStrings.Brand.repoURL) {
                Link(UIStrings.Brand.repoLink, destination: url)
                    .font(.system(size: 12))
                    .help(UIStrings.Brand.repoHelp)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)
            }
        }
        .frame(height: 88)
    }
}

/// A Settings row: the 22 pt icon tile, 10 pt, then the row's content; at least 44 pt tall.
struct SettingsRow<Tile: View, Content: View>: View {
    let tile: Tile
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            tile
            content
        }
        .frame(minHeight: 44)
    }
}

extension SettingsRow where Tile == SettingsIconTile {
    init(symbol: String, @ViewBuilder content: () -> Content) {
        self.init(tile: SettingsIconTile(symbol: symbol), content: content)
    }
}

/// A section header at 13 semibold.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }
}

/// Screen Recording or Accessibility, with its status: Allowed (green check) or Open System Settings….
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
