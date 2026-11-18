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
    /// The Updates row; nil hides it.
    public var updates: UpdateChecker?

    @ObservationIgnored private let permissions: any PermissionProbe
    @ObservationIgnored private let loginItem: any LoginItemService

    public init(
        permissions: any PermissionProbe, loginItem: any LoginItemService, agents: AgentsPanelState? = nil,
        updates: UpdateChecker? = nil
    ) {
        self.permissions = permissions
        self.loginItem = loginItem
        self.agents = agents
        self.updates = updates
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

/// The Settings window's tabs, in toolbar order.
public enum SettingsTab: String, CaseIterable, Sendable {
    case general
    case agents
    case permissions

    public var title: String {
        switch self {
        case .general: UIStrings.Settings.general
        case .agents: UIStrings.Agents.title
        case .permissions: UIStrings.Settings.permissions
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .permissions: "hand.raised"
        }
    }
}

/// The Settings layout. Groups run x 16–464, labels start at x 28, and trailing controls end at x 452.
public enum SettingsMetrics {
    public static let width: CGFloat = 480
    public static let rowHeight: CGFloat = 44
    public static let labelX: CGFloat = 28
    public static let trailingX: CGFloat = 452
    /// The least room between a label and its trailing control.
    public static let labelGap: CGFloat = 12
    public static let buttonMinWidth: CGFloat = 80
    /// Every Agents button, so they line up as one column.
    public static let agentButtonWidth: CGFloat = 88

    /// A grouped `Form` puts its own space around rows, and has no setting for it. It keeps 20 pt around each group,
    /// 10 inside it, 10.5 above and below a row, and 32 above a section header. These turn that into the design's 16,
    /// 12, 44 and 16.
    static let formMarginAdjustment: CGFloat = -4
    static let rowInsetAdjustment: CGFloat = 2
    static let formRowVerticalInset: CGFloat = 10.5
    static let sectionHeaderAdjustment: CGFloat = -16
}

/// One permission's row. The shape of the status icon carries the state, so colour is never the only cue.
public struct PermissionRowModel: Sendable, Hashable {
    public var permission: Permission
    public var title: String
    public var detail: String
    public var allowed: Bool
    public var symbol: String
    /// The sentence on the warning triangle. Nil when allowed.
    public var warning: String?
    public var accessibilityLabel: String

    public init(_ permission: Permission, status: PermissionStatus) {
        self.permission = permission
        switch permission {
        case .accessibility:
            title = UIStrings.Settings.accessibility
            detail = UIStrings.Settings.accessibilityDetail
        case .screenRecording, .directCapture:
            title = UIStrings.Settings.screenRecording
            detail = UIStrings.Settings.screenRecordingDetail
        }
        allowed = status == .allowed
        symbol = allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        if allowed {
            warning = nil
            accessibilityLabel = UIStrings.Settings.permissionAllowedLabel(title)
        } else {
            warning = permission == .accessibility
                ? UIStrings.Settings.accessibilityNotAllowed : UIStrings.Settings.screenRecordingNotAllowed
            accessibilityLabel = UIStrings.Settings.permissionMissingLabel(title, detail: detail)
        }
    }
}

/// The content of one Settings tab: a grouped form, as tall as its rows, with no scrolling.
public struct SettingsView: View {
    let tab: SettingsTab
    @Bindable var store: SettingsStore
    @Bindable var panel: SettingsPanelState
    let actions: SettingsActions

    public init(tab: SettingsTab, store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions) {
        self.tab = tab
        self.store = store
        self.panel = panel
        self.actions = actions
    }

    public var body: some View {
        Form {
            switch tab {
            case .general: general
            case .agents: agents
            case .permissions: permissions
            }
        }
        .formStyle(.grouped)
        .contentMargins(SettingsMetrics.formMarginAdjustment, for: .scrollContent)
        .scrollDisabled(true)
        .frame(width: SettingsMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.controllerSettings) { actions.settingsChanged() }
    }

    // MARK: - General

    @ViewBuilder
    private var general: some View {
        Section {
            SettingsRow {
                SettingsRowText(
                    title: UIStrings.Settings.outputFolder, detail: store.outputFolderDisplayPath,
                    detailHelp: store.outputFolder.path, truncation: .middle)
            } trailing: {
                SettingsButton(title: UIStrings.Settings.choose) { actions.chooseOutputFolder() }
            }
            SettingsRow {
                SettingsRowText(
                    title: UIStrings.Settings.openAtLogin, detail: panel.loginError, detailHelp: panel.loginError)
            } trailing: {
                TrailingSwitch(
                    title: UIStrings.Settings.openAtLogin,
                    isOn: Binding(get: { panel.openAtLogin }, set: { panel.setOpenAtLogin($0) }))
            }
        }
        Section {
            SettingsRow {
                SettingsRowText(title: UIStrings.Settings.defaultFrameRate)
            } trailing: {
                FrameRateSegments(selection: $store.fps)
            }
            switchRow(UIStrings.Settings.showCursor, isOn: $store.cursor)
            switchRow(UIStrings.Settings.writeClickEvents, isOn: $store.events)
            switchRow(UIStrings.Settings.showRecordingIndicator, isOn: $store.hud)
            SettingsRow {
                SettingsRowText(title: UIStrings.Settings.stopShortcut)
            } trailing: {
                Text(UIStrings.Settings.stopShortcutKeys).foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(title: UIStrings.Settings.recording)
        }
        Section {
            if let updates = panel.updates { UpdatesRows(checker: updates) }
            GitHubRow()
        } header: {
            SettingsSectionHeader(title: UIStrings.Settings.about)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        SettingsRow {
            SettingsRowText(title: title)
        } trailing: {
            TrailingSwitch(title: title, isOn: isOn)
        }
    }

    // MARK: - Agents

    @ViewBuilder
    private var agents: some View {
        if let agents = panel.agents {
            Section {
                ForEach(agents.rows) { row in
                    SettingsRow {
                        SettingsRowText(title: row.title, detail: row.status, detailHelp: row.statusHelp)
                    } trailing: {
                        SettingsButton(title: row.buttonTitle, width: SettingsMetrics.agentButtonWidth) {
                            agents.change(row.agent, remove: row.removes)
                        }
                        .disabled(!row.enabled)
                        .help(row.buttonHelp ?? "")
                    }
                }
            } footer: {
                Text(UIStrings.Agents.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsMetrics.rowInsetAdjustment)
            }
        }
    }

    // MARK: - Permissions

    private var permissions: some View {
        Section {
            SettingsPermissionRow(model: PermissionRowModel(.screenRecording, status: panel.screenRecording)) {
                actions.openPrivacyPane(.screenRecording)
            }
            SettingsPermissionRow(model: PermissionRowModel(.accessibility, status: panel.accessibility)) {
                actions.openPrivacyPane(.accessibility)
            }
        }
    }
}

// MARK: - Rows

/// A 44 pt form row: the label column, then a trailing control that always keeps its own size.
struct SettingsRow<Label: View, Trailing: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: SettingsMetrics.labelGap) {
            label.frame(maxWidth: .infinity, alignment: .leading)
            trailing.fixedSize()
        }
        .modifier(SettingsRowLayout())
    }
}

/// Puts a row's content on the design's edges, inside the space the form adds around it.
struct SettingsRowLayout: ViewModifier {
    @Environment(\.settingsRowProbe) private var probe

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: .infinity)
            .background {
                if let probe {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        Color.clear
                            .onAppear { probe(frame) }
                            .onChange(of: frame) { probe(frame) }
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowInsetAdjustment)
            .frame(height: SettingsMetrics.rowHeight)
            .padding(.vertical, -SettingsMetrics.formRowVerticalInset)
    }
}

extension EnvironmentValues {
    /// Set by the layout tests, to read where each row landed.
    @Entry var settingsRowProbe: (@MainActor (CGRect) -> Void)?
}

/// A row's title, with the optional 12 pt secondary line. It truncates so the trailing control never has to.
struct SettingsRowText: View {
    let title: String
    var detail: String?
    var detailHelp: String?
    var truncation: Text.TruncationMode = .tail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(truncation)
                    .help(detailHelp ?? "")
            }
        }
    }
}

/// A push button, at least 80 pt wide, or exactly `width`.
struct SettingsButton: View {
    let title: String
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .frame(minWidth: width ?? SettingsMetrics.buttonMinWidth, maxWidth: width)
    }
}

/// A section header at 13 semibold, on the labels' edge.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.leading, SettingsMetrics.rowInsetAdjustment)
            .padding(.top, SettingsMetrics.sectionHeaderAdjustment)
    }
}

/// Screen Recording or Accessibility: a green check and Allowed, or a warning triangle and Open System Settings….
struct SettingsPermissionRow: View {
    let model: PermissionRowModel
    let open: () -> Void

    var body: some View {
        SettingsRow {
            // Not allowed, the button's label reads the whole row.
            SettingsRowText(title: model.title, detail: model.detail, detailHelp: model.detail)
                .accessibilityHidden(!model.allowed)
        } trailing: {
            if model.allowed {
                HStack(spacing: 4) {
                    Image(systemName: model.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text(UIStrings.Settings.allowed)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: model.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .help(model.warning ?? "")
                        .accessibilityLabel(model.warning ?? "")
                    Button(UIStrings.Settings.openSystemSettings, action: open)
                        .accessibilityLabel(model.accessibilityLabel)
                }
            }
        }
        .modifier(PermissionRowAccessibility(model: model))
    }
}

/// An allowed row is one element. A row that isn't keeps its triangle and button separate.
private struct PermissionRowAccessibility: ViewModifier {
    let model: PermissionRowModel

    func body(content: Content) -> some View {
        if model.allowed {
            content.accessibilityElement(children: .ignore).accessibilityLabel(model.accessibilityLabel)
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

/// Updates: the state's line and button, then What's new while a newer release with notes is waiting. The version and
/// the app name are carried by the line.
struct UpdatesRows: View {
    let checker: UpdateChecker

    var body: some View {
        let row = UpdateRowModel(state: checker.state, current: checker.current, method: checker.method)
        SettingsRow {
            SettingsRowText(title: UIStrings.Updates.title, detail: row.detail, detailHelp: row.detail)
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(UIStrings.Settings.updatesLabel(row.detail))
        } trailing: {
            HStack(spacing: 8) {
                if row.busy { ProgressView().controlSize(.small).accessibilityHidden(true) }
                button(row.button)
            }
        }
        if let notes = row.notes {
            WhatsNewNotes(markdown: notes)
                .padding(.horizontal, SettingsMetrics.rowInsetAdjustment)
        }
    }

    @ViewBuilder
    private func button(_ model: UpdateRowModel.Button) -> some View {
        let button = SettingsButton(title: model.title) { Task { await checker.perform(model.action) } }
            .disabled(!model.enabled)
        if model.prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }
}

/// The project link: the whole row is the button.
struct GitHubRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIStrings.Brand.repoURL) { openURL(url) }
        } label: {
            SettingsRow {
                SettingsRowText(title: UIStrings.Settings.viewOnGitHub)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(UIStrings.Brand.repoHelp)
        .accessibilityLabel(UIStrings.Settings.viewOnGitHub)
        .accessibilityAddTraits(.isLink)
    }
}

/// The newer release's notes, as simple Markdown, open so they're visible, and capped so a long section scrolls
/// instead of stretching Settings.
private struct WhatsNewNotes: View {
    let markdown: String

    /// Long notes scroll inside this height.
    static let maxHeight: CGFloat = 160

    @State private var open = true
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            ScrollView {
                notesText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: NotesHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxHeight) : Self.maxHeight)
            .onPreferenceChange(NotesHeightKey.self) { contentHeight = $0 }
        } label: {
            Text(UIStrings.Updates.whatsNew)
        }
        .font(.system(size: 12))
    }

    private var notesText: Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return Text(attributed)
        } else {
            return Text(markdown)
        }
    }
}

/// The height of the notes text, so the scroll view can shrink to it and stop at `WhatsNewNotes.maxHeight`.
private struct NotesHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
