import AppKit
import SkreenrekCore
import SwiftUI

/// Settings for the v2 directions: A's grouped form with System Settings-style icon tiles and trailing switches; B
/// adds a 64 pt hero row; C makes the tiles monochrome, tints the switches with the brand accent and adds an 88 pt
/// hero. Same rows, copy and behaviour as the shipping `SettingsView`. Mockup only.
struct DirectionSettingsView: View {
    static let width: CGFloat = 480

    let direction: UIDirection
    @Bindable var store: SettingsStore
    @Bindable var panel: SettingsPanelState
    let actions: SettingsActions
    let version: String
    /// The agent's own app icon where available; the renders pass none, so the `terminal.fill` fallback shows.
    var agentIcon: (AgentClient) -> NSImage? = { _ in nil }

    private var monochrome: Bool { direction == .c }
    /// C's selected segment and switches take the system accent; red stays for record and stop.
    private var accent: Color? { direction == .c ? Color.accentColor : nil }
    /// A and C shorten the permission button to "Open Settings…" so the detail stays on one line; B keeps A's
    /// first-review rows unchanged.
    private var compactPermissions: Bool { direction != .b }

    var body: some View {
        Form {
            if direction == .b { Section { compactHero } }
            if direction == .c { Section { brandedHero } }
            Section {
                row(tile: tile("folder.fill", .blue)) {
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
                row(tile: tile("speedometer", .indigo)) {
                    LabeledContent {
                        FrameRateSegments(selection: $store.fps, tint: accent)
                    } label: {
                        Text(UIStrings.Settings.defaultFrameRate)
                    }
                }
                switchRow(UIStrings.Settings.showCursor, tile: tile("cursorarrow", .gray), isOn: $store.cursor)
                switchRow(
                    UIStrings.Settings.writeClickEvents, tile: tile("cursorarrow.click", .gray), isOn: $store.events)
                switchRow(UIStrings.Settings.showRecordingIndicator, tile: tile("record.circle", .red), isOn: $store.hud)
                row(tile: tile("power", .green)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            UIStrings.Settings.openAtLogin,
                            isOn: Binding(get: { panel.openAtLogin }, set: { panel.setOpenAtLogin($0) })
                        )
                        .modifier(DirectionSwitch(tint: accent))
                        if let error = panel.loginError {
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                row(tile: tile("keyboard", .gray)) {
                    LabeledContent {
                        Text(UIStrings.Settings.stopShortcutKeys).foregroundStyle(.secondary)
                    } label: {
                        Text(UIStrings.Settings.stopShortcut)
                    }
                }
            }
            if let agents = panel.agents {
                Section {
                    ForEach(agents.connections) { connection in
                        row(tile: agentTile(connection.agent)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.agent.name).font(.system(size: 13))
                                    Text(connection.status).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button(connection.connected ? UIStrings.Agents.remove : UIStrings.Agents.connect) {
                                    agents.change(connection.agent, remove: connection.connected)
                                }
                            }
                            .disabled(!connection.detected && !connection.connected)
                        }
                    }
                } header: {
                    sectionHeader(UIStrings.Agents.title)
                }
            }
            Section {
                row(tile: tile("rectangle.dashed.badge.record", .purple)) {
                    PermissionRow(
                        title: UIStrings.Settings.screenRecording, detail: UIStrings.Settings.screenRecordingDetail,
                        status: panel.screenRecording, compact: compactPermissions
                    ) { actions.openPrivacyPane(.screenRecording) }
                }
                row(tile: tile("accessibility", .blue)) {
                    PermissionRow(
                        title: UIStrings.Settings.accessibility, detail: UIStrings.Settings.accessibilityDetail,
                        status: panel.accessibility, compact: compactPermissions
                    ) { actions.openPrivacyPane(.accessibility) }
                }
            } header: {
                sectionHeader(UIStrings.Settings.permissions)
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.controllerSettings) { actions.settingsChanged() }
    }

    // MARK: - Rows

    private func tile(_ symbol: String, _ color: Color) -> SettingsIconTile {
        SettingsIconTile(symbol: symbol, color: color, monochrome: monochrome)
    }

    @ViewBuilder
    private func agentTile(_ agent: AgentClient) -> some View {
        if let icon = agentIcon(agent) {
            Image(nsImage: icon).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
        } else {
            SettingsIconTile(symbol: "terminal.fill", color: .black, monochrome: monochrome)
        }
    }

    /// An icon tile, 10 pt, then the row's content; at least 44 pt tall.
    private func row<Tile: View, Content: View>(tile: Tile, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            tile
            content()
        }
        .frame(minHeight: 44)
    }

    private func switchRow<Tile: View>(_ title: String, tile: Tile, isOn: Binding<Bool>) -> some View {
        row(tile: tile) {
            Toggle(title, isOn: isOn).modifier(DirectionSwitch(tint: accent))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }

    // MARK: - Hero and footer

    /// B: the app icon at 48, the name at 15 semibold and the tagline, 64 pt tall.
    private var compactHero: some View {
        HStack(spacing: 12) {
            AppIconPlaceholder(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(UIStrings.productName).font(.system(size: 15, weight: .semibold))
                Text(UIStrings.Directions.tagline).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 64)
    }

    /// C: the V1 app icon (icon-dark) at 56, the name at 20 semibold (SF Pro, the system stand-in for the wordmark's
    /// Inter SemiBold), the
    /// version, and the repository link on the right, 88 pt tall.
    private var brandedHero: some View {
        HStack(alignment: .center, spacing: 14) {
            KitAppIcon(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(UIStrings.productName).font(.system(size: 20, weight: .semibold))
                Text(version).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            }
            Spacer(minLength: 8)
            if let url = URL(string: UIStrings.Directions.repoURL) {
                Link(UIStrings.Directions.repoLink, destination: url)
                    .font(.system(size: 12))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)
            }
        }
        .frame(height: 88)
    }

    /// A: the app icon at 32 above `Skreenrek 0.1.0`, centred, 16 above and 20 below. B keeps the version line (its
    /// hero already shows the icon); C's hero carries the version, so it has no footer.
    @ViewBuilder
    private var footer: some View {
        switch direction {
        case .a:
            VStack(spacing: 6) {
                AppIconPlaceholder(size: 32)
                versionLine
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 20)
        case .b:
            versionLine.frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 20)
        case .c:
            EmptyView()
        }
    }

    private var versionLine: some View {
        Text(UIStrings.Settings.version(version)).font(.system(size: 11)).foregroundStyle(.tertiary)
    }
}
