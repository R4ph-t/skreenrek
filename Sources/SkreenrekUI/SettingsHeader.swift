import AppKit
import SkreenrekCore
import SwiftUI

/// The Settings window's chrome: standard toolbar tabs over the shared solid surface, and the identity row (app icon,
/// name and version) at the top of General.
public enum SettingsChromeMetrics {
    /// The onboarding window's transparent title bar band, where the traffic lights sit.
    public static let titleBarHeight: CGFloat = 28
    /// The space above every tab's first element, under the toolbar.
    public static let contentTopGap: CGFloat = 8
    /// The identity row on General: 48 tall, the icon on the sections' leading edge (x 16).
    public static let identityHeight: CGFloat = 48
    public static let iconSize: CGFloat = 32
    /// The name and version start 12 pt after the icon.
    public static let textGap: CGFloat = 12
    public static let nameVersionSpacing: CGFloat = 2
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

/// Where the header's icon comes from: the Dock's icon (`NSApp.applicationIconImage`) when running from the .app
/// bundle, so the two always match. An unbundled run (swift run, tests, offscreen renders) would get the generic
/// executable icon, so it draws the V1 artwork the bundle icon was made from instead.
enum SettingsHeaderIcon {
    static func image(isAppBundle: Bool, applicationIcon: () -> NSImage, fallback: () -> NSImage) -> NSImage {
        isAppBundle ? applicationIcon() : fallback()
    }

    static func isAppBundle(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app"
    }

    @MainActor
    static func current(size: CGFloat) -> NSImage {
        image(
            isAppBundle: isAppBundle(.main), applicationIcon: { NSApp.applicationIconImage },
            fallback: { BrandIcon.appIcon(size: size) })
    }
}

/// The onboarding window's 28 pt title bar band: the window draws the real traffic lights over it. Renders draw three
/// dots in their place.
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

/// The identity row at the top of General: the app icon on the sections' leading edge, then `Skreenrek` over
/// `Version 1.0.5`, centred together on the icon. On the window base, with no card. VoiceOver reads it as one element.
struct SettingsIdentityRow: View {
    var model = SettingsHeaderModel()

    var body: some View {
        HStack(spacing: SettingsChromeMetrics.textGap) {
            Image(nsImage: SettingsHeaderIcon.current(size: SettingsChromeMetrics.iconSize))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SettingsChromeMetrics.identityHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

/// One tab as the toolbar tab controller hosts it: the tab's content at the top of the window's one fixed height,
/// on `surface.base`, so every tab is the same size and switching never resizes the window.
struct SettingsTabContent: View {
    let tab: SettingsTab
    let store: SettingsStore
    let panel: SettingsPanelState
    let actions: SettingsActions
    let height: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SettingsView(tab: tab, store: store, panel: panel, actions: actions)
            .padding(.top, SettingsChromeMetrics.contentTopGap)
            .frame(width: SettingsMetrics.width, height: height, alignment: .top)
            .background(SkreenrekSurface(scheme).base.color)
    }
}
