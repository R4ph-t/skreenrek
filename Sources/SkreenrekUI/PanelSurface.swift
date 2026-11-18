import AppKit
import SwiftUI

/// An sRGB colour from the solid-panel addendum, kept as numbers so the tests can read the spec's values.
struct PanelTone: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var opacity: Double = 1

    /// A fully opaque `0xRRGGBB` colour.
    static func hex(_ value: UInt32) -> PanelTone {
        PanelTone(
            red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
    }

    static func white(_ opacity: Double) -> PanelTone {
        PanelTone(red: 255, green: 255, blue: 255, opacity: opacity)
    }

    static func black(_ opacity: Double) -> PanelTone {
        PanelTone(red: 0, green: 0, blue: 0, opacity: opacity)
    }

    var color: Color {
        Color(
            .sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: opacity)
    }
}

/// A black drop shadow from the addendum. `blur` is the design value, and SwiftUI's radius is half of it.
struct PanelShadow: Hashable, Sendable {
    var opacity: Double
    var blur: CGFloat
    var y: CGFloat

    var radius: CGFloat { blur / 2 }
    var color: Color { PanelTone.black(opacity).color }
}

/// What the pointer is doing to a control. Pressed wins over hover.
enum PanelInteraction: Hashable, Sendable {
    case rest
    case hover
    case pressed

    init(enabled: Bool = true, hovering: Bool, pressed: Bool) {
        if !enabled {
            self = .rest
        } else if pressed {
            self = .pressed
        } else {
            self = hovering ? .hover : .rest
        }
    }
}

/// The menu panel's solid surface, for one appearance (addendum of 2026-11-18). Nothing here is a material.
struct PanelPalette: Hashable, Sendable {
    var isDark: Bool

    init(_ scheme: ColorScheme) {
        isDark = scheme == .dark
    }

    var fill: PanelTone { .hex(isDark ? 0x1E1E20 : 0xF6F6F8) }
    var separator: PanelTone { isDark ? .white(0.10) : .black(0.08) }
    var cellFill: PanelTone { .hex(isDark ? 0x2C2C2F : 0xFFFFFF) }
    /// Light cells only: a dark cell already stands out from the panel.
    var cellHairline: PanelTone? { isDark ? nil : .black(0.08) }
    var wellFill: PanelTone { .hex(isDark ? 0x2C2C2F : 0xE9E9EE) }
    var dropShadow: PanelShadow {
        isDark ? PanelShadow(opacity: 0.35, blur: 24, y: 8) : PanelShadow(opacity: 0.15, blur: 20, y: 6)
    }

    func hairline(increaseContrast: Bool) -> PanelTone {
        let opacity = increaseContrast ? 0.25 : 0.10
        return isDark ? .white(opacity) : .black(opacity)
    }

    /// The row highlight. Nil at rest.
    func rowFill(_ interaction: PanelInteraction) -> PanelTone? {
        switch interaction {
        case .rest: nil
        case .hover: isDark ? .white(0.08) : .black(0.05)
        case .pressed: isDark ? .white(0.12) : .black(0.09)
        }
    }

    func rowColor(_ interaction: PanelInteraction) -> Color {
        rowFill(interaction)?.color ?? .clear
    }
}

/// The parts of the surface that don't depend on the appearance.
enum PanelSurface {
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)
    static let stop = Color(nsColor: .systemRed)

    /// The label on a hero button: white on its solid fill, tertiary when disabled.
    static func heroForeground(enabled: Bool) -> Color {
        enabled ? .white : tertiaryText
    }

    /// How much black goes over a solid hero button.
    static func heroDarkening(_ interaction: PanelInteraction) -> Double {
        switch interaction {
        case .rest: 0
        case .hover: 0.06
        case .pressed: 0.12
        }
    }

    /// One device pixel, in points.
    static func pixel(displayScale: CGFloat) -> CGFloat {
        1 / max(displayScale, 1)
    }
}

/// Who draws a floating surface's one shadow.
enum HUDShadowSource {
    /// The surface fills its own window, and the window server shadows it.
    case window
    /// The surface sits inside a larger window, so SwiftUI draws the shadow.
    case drawn
}

/// The panel's solid surface on the picker and recording HUDs: fill, clipped content, inside hairline, one shadow.
struct HUDSurface: ViewModifier {
    var shadow: HUDShadowSource
    var increaseContrast: Bool
    var radius = PanelMetrics.radiusPanel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let palette = PanelPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .foregroundStyle(PanelSurface.primaryText)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    palette.hairline(increaseContrast: increaseContrast).color,
                    lineWidth: PanelSurface.pixel(displayScale: displayScale)
                )
                .allowsHitTesting(false)
            }
            .background {
                switch shadow {
                case .window:
                    shape.fill(palette.fill.color)
                case .drawn:
                    let drop = palette.dropShadow
                    shape.fill(palette.fill.color).shadow(color: drop.color, radius: drop.radius, y: drop.y)
                }
            }
    }
}
