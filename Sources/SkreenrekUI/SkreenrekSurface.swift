import AppKit
import SwiftUI

/// The one neutral surface every Skreenrek surface reads from: the menu panel, the control bar, the HUDs and the
/// Settings window (addendum 3, 2026-11-19). The colour values live here and nowhere else.
struct SkreenrekSurface: Hashable, Sendable {
    var isDark: Bool

    init(isDark: Bool) {
        self.isDark = isDark
    }

    init(_ scheme: ColorScheme) {
        isDark = scheme == .dark
    }

    static let dark = SkreenrekSurface(isDark: true)
    static let light = SkreenrekSurface(isDark: false)

    /// The panel, control bar and HUD fill, and the whole Settings window, title bar and header included.
    var base: PanelTone { .hex(isDark ? 0x1E1E1E : 0xF5F5F5) }
    /// Settings sections, the panel's Size and Frame Rate cells and the bar's Size pop-up.
    var cell: PanelTone { .hex(isDark ? 0x2A2A2A : 0xFFFFFF) }
    /// The preview well: the cell tone in dark, a light grey in light so the preview reads on white.
    var well: PanelTone { isDark ? cell : .hex(0xEBEBEB) }
    /// Light cells only get a 1 px edge: a dark cell already stands out from the base.
    var cellEdge: PanelTone? { isDark ? nil : .black(0.08) }
    /// Lines between rows (inset 12 pt from a section's leading edge) and the panel's dividers.
    var separator: PanelTone { isDark ? .white(0.08) : .black(0.08) }
    var hover: PanelTone { isDark ? .white(0.08) : .black(0.05) }
    var pressed: PanelTone { isDark ? .white(0.12) : .black(0.09) }

    /// The 1 px inside edge of a floating surface.
    func hairline(increaseContrast: Bool) -> PanelTone {
        let opacity = increaseContrast ? 0.25 : 0.10
        return isDark ? .white(opacity) : .black(opacity)
    }

    /// How far a Settings row separator starts from the section's leading edge.
    static let separatorInset: CGFloat = 12

    /// `base` as a colour that follows the appearance, for AppKit (the Settings window's background).
    static let baseColor = NSColor(name: nil) { appearance in
        SkreenrekSurface(isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua).base.nsColor
    }
}

extension PanelTone {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
            alpha: CGFloat(opacity))
    }
}
