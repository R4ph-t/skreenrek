import AppKit
import SkreenrekCore
import SwiftUI

/// The Settings window's chrome (addendum 3): a transparent 28 pt title bar with only the traffic lights, then a
/// 56 pt header in the same tone with the app icon, name and version on the left and the tab switch on the right.
public enum SettingsChromeMetrics {
    public static let titleBarHeight: CGFloat = 28
    public static let headerHeight: CGFloat = 56
    /// The gap between the header and the first section.
    public static let contentGap: CGFloat = 8
    /// The title bar and the header: where the old toolbar was.
    public static var headerBottom: CGFloat { titleBarHeight + headerHeight }
    /// Where the content starts, from the top of the window.
    public static var contentTop: CGFloat { headerBottom + contentGap }
    /// The header's leading and trailing edges are at x 16 and x 464.
    public static let headerInset: CGFloat = 16
    public static let iconSize: CGFloat = 32
    /// The name and version start at x 56.
    public static let textGap: CGFloat = 8
    public static let nameVersionSpacing: CGFloat = 2
    public static let segmentWidth: CGFloat = 88
    public static let segmentHeight: CGFloat = 24
    public static var tabsWidth: CGFloat { segmentWidth * CGFloat(SettingsTab.allCases.count) }
    /// The content crossfade on a tab switch. Instant under Reduce Motion.
    public static let crossfade: Double = 0.15
}

extension SettingsTab {
    /// The tab `offset` places away, stopping at the first and last tabs (←/→ on the segmented control).
    public func moved(by offset: Int) -> SettingsTab {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + offset, 0), all.count - 1)]
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// What the header says. The version is always `SkreenrekVersion.current`.
public struct SettingsHeaderModel: Equatable, Sendable {
    public var name: String
    public var version: String
    public var accessibilityLabel: String

    public init(version: String = SkreenrekVersion.current) {
        name = UIStrings.Settings.headerName
        self.version = UIStrings.Settings.headerVersion(version)
        accessibilityLabel = UIStrings.Settings.headerLabel(version)
    }
}

/// The whole Settings window content: the title bar band, the header, then the selected tab, all on `surface.base`.
struct SettingsWindowContent: View {
    @Bindable var store: SettingsStore
    let panel: SettingsPanelState
    let actions: SettingsActions
    /// Each tab's content height as it lays out, so the window can fit it.
    var contentHeight: (SettingsTab, CGFloat) -> Void = { _, _ in }
    /// Draws stand-in traffic lights in the title bar band, for the offscreen renders.
    var drawsTrafficLights = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            SettingsTitleBarBand(drawsTrafficLights: drawsTrafficLights)
            SettingsHeader(selection: $store.settingsTab)
            Color.clear.frame(height: SettingsChromeMetrics.contentGap)
            ZStack(alignment: .top) {
                let tab = store.settingsTab
                SettingsView(tab: tab, store: store, panel: panel, actions: actions)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight(tab, $0) }
                    .id(tab)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: SettingsChromeMetrics.crossfade), value: store.settingsTab)
        }
        .frame(width: SettingsMetrics.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SkreenrekSurface(scheme).base.color)
        .ignoresSafeArea()
    }
}

/// The title bar's 28 pt: the window draws the real traffic lights over it. Renders draw three dots in their place.
struct SettingsTitleBarBand: View {
    var drawsTrafficLights = false

    var body: some View {
        HStack(spacing: 8) {
            if drawsTrafficLights {
                ForEach([NSColor.systemRed, .systemYellow, .systemGreen], id: \.self) { color in
                    Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12)
                }
            }
        }
        .padding(.leading, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SettingsChromeMetrics.titleBarHeight)
        .accessibilityHidden(true)
    }
}

/// The 56 pt header: icon, name and version on the left, the tab switch on the right, all on one centre line.
struct SettingsHeader: View {
    @Binding var selection: SettingsTab
    var model = SettingsHeaderModel()

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: SettingsChromeMetrics.textGap) {
                Image(nsImage: BrandIcon.appIcon(size: SettingsChromeMetrics.iconSize))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: SettingsChromeMetrics.iconSize, height: SettingsChromeMetrics.iconSize)
                VStack(alignment: .leading, spacing: SettingsChromeMetrics.nameVersionSpacing) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelSurface.primaryText)
                    Text(model.version)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelSurface.secondaryText)
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityLabel)
            Spacer(minLength: 12)
            SettingsTabsControl(selection: $selection)
                .frame(width: SettingsChromeMetrics.tabsWidth, height: SettingsChromeMetrics.segmentHeight)
        }
        .padding(.horizontal, SettingsChromeMetrics.headerInset)
        .frame(height: SettingsChromeMetrics.headerHeight)
    }
}

/// `General | Agents | Permissions`: a system segmented control, 3 × 88 pt, Tab-reachable, with ←/→ switching tabs
/// while it has focus.
struct SettingsTabsControl: NSViewRepresentable {
    @Binding var selection: SettingsTab

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> SettingsSegmentedControl {
        let control = SettingsSegmentedControl.make()
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.onMove = { [weak coordinator = context.coordinator] in coordinator?.move(by: $0) }
        return control
    }

    func updateNSView(_ control: SettingsSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.selectedSegment != selection.index { control.selectedSegment = selection.index }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<SettingsTab>

        init(selection: Binding<SettingsTab>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            select(index: sender.selectedSegment)
        }

        /// A click on a segment.
        func select(index: Int) {
            guard SettingsTab.allCases.indices.contains(index) else { return }
            selection.wrappedValue = SettingsTab.allCases[index]
        }

        /// ←/→ while the control has focus. Stops at the ends.
        func move(by offset: Int) {
            selection.wrappedValue = selection.wrappedValue.moved(by: offset)
        }
    }
}

/// The segmented control, made Tab-reachable even without Full Keyboard Access, with ←/→ reporting a move.
final class SettingsSegmentedControl: NSSegmentedControl {
    var onMove: ((Int) -> Void)?

    static func make() -> SettingsSegmentedControl {
        let control = SettingsSegmentedControl()
        control.segmentCount = SettingsTab.allCases.count
        control.trackingMode = .selectOne
        control.controlSize = .regular
        control.segmentDistribution = .fillEqually
        for (index, tab) in SettingsTab.allCases.enumerated() {
            control.setLabel(tab.title, forSegment: index)
            control.setWidth(SettingsChromeMetrics.segmentWidth, forSegment: index)
        }
        control.setAccessibilityLabel(UIStrings.Settings.tabsLabel)
        return control
    }

    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: onMove?(-1)
        case .rightArrow?: onMove?(1)
        default: super.keyDown(with: event)
        }
    }
}
