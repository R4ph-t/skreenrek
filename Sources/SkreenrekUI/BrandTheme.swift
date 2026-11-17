import AppKit
import SkreenrekCore
import SwiftUI

/// The branded dropdown's and Settings' shared tones. The accent is the system accent (switches, the selected
/// segment, the primary item); red stays for record and stop, orange for errors. Everything else is neutral.
enum BrandTheme {
    /// The header tile behind the V1 mark: graphite, a touch lighter in dark mode (the kit keeps it graphite, not red).
    static let graphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.22 : 0.16, alpha: 1)
        })
    /// The menu material's tone, for the composed renders (an offscreen `NSMenu` can't be drawn).
    static let menuBackground = Color(nsColor: menuBackgroundColor)
    static let menuBackgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    }

    /// The header band: neutral, red while recording, orange for an error. Increase Contrast makes it stronger and
    /// adds a stroke.
    static func band(_ kind: DropdownHeader.Kind, increaseContrast: Bool) -> AnyShapeStyle {
        switch kind {
        case .recording: AnyShapeStyle(Color.red.opacity(increaseContrast ? 0.24 : 0.14))
        case .error: AnyShapeStyle(Color.orange.opacity(increaseContrast ? 0.22 : 0.12))
        default: AnyShapeStyle(increaseContrast ? neutralBandContrast : neutralBand)
        }
    }

    /// A neutral band that reads on the menu material in both appearances (`.fill.quinary` vanishes in dark).
    static let neutralBand = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.04)
        })
    static let neutralBandContrast = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.09)
        })

    static func bandStroke(_ kind: DropdownHeader.Kind) -> AnyShapeStyle {
        switch kind {
        case .recording: AnyShapeStyle(Color.red)
        case .error: AnyShapeStyle(Color.orange)
        default: AnyShapeStyle(.separator)
        }
    }
}

/// The clip's first frame, 16:10, with a thin separator stroke (the accent while it's the newest clip from this
/// session) and a `play.fill` glyph bottom-left.
struct ClipThumbnail: View {
    var image: NSImage?
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var accentStroke = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .padding(5)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    accentStroke ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                    lineWidth: accentStroke || contrast == .increased ? 1 : 0.5)
        )
        .accessibilityElement()
        .accessibilityLabel(UIStrings.Brand.thumbnailLabel)
    }
}

/// A synthetic first frame for the renders: a light browser window on a local page. Fixed colours, since it stands
/// for video pixels, not UI.
struct SampleFrame: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(
                    [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self
                ) { Circle().fill($0).frame(width: 10, height: 10) }
                Spacer(minLength: 20)
                Capsule().fill(Color(white: 0.87)).frame(width: 150, height: 16)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(white: 0.94))
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.2)).frame(width: 130, height: 12)
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.75)).frame(width: 160, height: 7)
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.75)).frame(width: 120, height: 7)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.2, green: 0.45, blue: 0.95)).frame(width: 64, height: 20)
                        .padding(.top, 6)
                }
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.7, blue: 1), Color(red: 0.75, green: 0.55, blue: 0.95)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
        .frame(width: 320, height: 200)
        .environment(\.colorScheme, .light)
    }

    /// The frame as an image at 2×, the way the app decodes a clip's first frame.
    @MainActor
    static func image() -> NSImage? {
        let renderer = ImageRenderer(content: SampleFrame())
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// A Settings row's icon tile: 22 × 22, radius 6, monochrome (`.fill.tertiary` with a `.primary` 13 pt symbol), so
/// the only colour in the window is the accent on the switches and the hero.
struct SettingsIconTile: View {
    var symbol: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(contrast == .increased ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

extension NSHostingView {
    /// A hosting view sized to its content, for the offscreen renders.
    @MainActor
    static func fitted(_ root: Content) -> Self {
        let view = Self(rootView: root)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return view
    }
}

extension EnvironmentValues {
    /// Set by the offscreen renders: AppKit-backed switches and segmented controls only draw their active (accent)
    /// state in a key window of an active app, so the renders draw stand-ins that look like it.
    @Entry var drawsActiveControls = false
}

/// A trailing switch: the native small switch in the app, an active-state stand-in in the renders.
struct SettingsSwitch: ViewModifier {
    @Environment(\.drawsActiveControls) private var drawsActive

    func body(content: Content) -> some View {
        if drawsActive {
            content.toggleStyle(DrawnSwitchStyle())
        } else {
            content.toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// The label, then a small switch at the trailing edge, drawn as an active window draws it (renders only).
struct DrawnSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.5).padding(2)
                }
                .frame(width: 32, height: 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
    }
}

/// The frame-rate control: the native segmented picker in the app; in the renders, a stand-in whose selected segment
/// carries the accent the way an active window draws it.
struct FrameRateSegments: View {
    @Binding var selection: FrameRate
    @Environment(\.drawsActiveControls) private var drawsActive

    var body: some View {
        if drawsActive {
            HStack(spacing: 2) {
                ForEach(FrameRate.allCases, id: \.self) { rate in
                    Text(UIStrings.Menu.fps(rate))
                        .font(.system(size: 13, weight: rate == selection ? .medium : .regular))
                        .foregroundStyle(rate == selection ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(rate == selection ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear)))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.fill.tertiary))
            .accessibilityElement(children: .contain)
        } else {
            Picker(UIStrings.Settings.defaultFrameRate, selection: $selection) {
                ForEach(FrameRate.allCases, id: \.self) { rate in
                    Text(UIStrings.Menu.fps(rate)).tag(rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}
