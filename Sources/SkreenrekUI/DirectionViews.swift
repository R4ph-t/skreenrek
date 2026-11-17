import AppKit
import SkreenrekCore
import SwiftUI

/// Shared pieces of the v2 direction mockups. Render-only: nothing in the shipping app uses them.
enum DirectionTheme {
    /// C's placeholder brand accent, a warm record red, until the chosen logo gives the real one.
    static let accent = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// C's header tile behind the white mark: graphite, a touch lighter in dark mode.
    static let graphite = Color(
        nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.22 : 0.16, alpha: 1)
        })
    /// The menu material's tone (the same one the shipping dropdown preview draws on).
    static let menuBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
                : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        })
    /// B's panel: the window material's tone, a touch lighter than the menu in dark mode.
    static let panelBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.19, green: 0.19, blue: 0.20, alpha: 1)
                : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
        })
}

/// The placeholder mark: `record.circle` inside `viewfinder` corners. Not the final logo.
struct BrandMark: View {
    var size: CGFloat
    var color: Color = .primary

    var body: some View {
        ZStack {
            Image(systemName: "viewfinder").font(.system(size: size, weight: .regular))
            Image(systemName: "record.circle").font(.system(size: size * 0.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A stand-in app icon (the real one comes with the logo): the placeholder mark in white on the accent.
struct AppIconPlaceholder: View {
    var size: CGFloat

    var body: some View {
        let base = DirectionTheme.accent
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [base.mix(with: .white, by: 0.15), base],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(BrandMark(size: size * 0.6, color: .white))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: size * 0.03, y: size * 0.02)
            .accessibilityHidden(true)
    }
}

/// The clip's first frame, 16:10, with a thin separator stroke and an optional `play.fill` glyph bottom-left.
struct ClipThumbnail: View {
    var image: NSImage?
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var showsPlay = true
    /// C draws a 1 pt system-accent stroke while the clip is the newest from this session.
    var accentStroke = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
            if showsPlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1.5)
                    .padding(5)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    accentStroke ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                    lineWidth: accentStroke ? 1 : 0.5)
        )
        .accessibilityElement()
        .accessibilityLabel(UIStrings.Directions.thumbnailLabel)
    }
}

/// A synthetic first frame for the mockups: a light browser window on a local page. Fixed colours, since it stands
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

    /// The frame as an image at 2×, the way the app would decode a clip's first frame.
    @MainActor
    static func image() -> NSImage? {
        let renderer = ImageRenderer(content: SampleFrame())
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// A System Settings-style icon tile: 22 × 22, radius 6, a white 13 pt symbol on a fill. C makes it monochrome.
struct SettingsIconTile: View {
    var symbol: String
    var color: Color
    var monochrome = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(monochrome ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(color.gradient))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(monochrome ? Color.primary : Color.white)
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

/// A trailing switch: the native small switch in the app, an active-state stand-in in the renders. `tint` is C's
/// accent; nil keeps the system accent.
struct DirectionSwitch: ViewModifier {
    var tint: Color?
    @Environment(\.drawsActiveControls) private var drawsActive

    func body(content: Content) -> some View {
        if drawsActive {
            content.toggleStyle(DrawnSwitchStyle()).tint(tint)
        } else {
            content.toggleStyle(.switch).controlSize(.small).tint(tint)
        }
    }
}

/// The label, then a small switch at the trailing edge, drawn as an active window draws it.
struct DrawnSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.5).padding(2)
                }
                .frame(width: 40, height: 22)
                .onTapGesture { configuration.isOn.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
    }
}

/// C's frame-rate control: the native segmented picker in the app; in the renders, a stand-in whose selected segment
/// carries the accent the way an active window draws it.
struct FrameRateSegments: View {
    @Binding var selection: FrameRate
    var tint: Color?
    @Environment(\.drawsActiveControls) private var drawsActive

    var body: some View {
        if drawsActive, let tint {
            HStack(spacing: 2) {
                ForEach(FrameRate.allCases, id: \.self) { rate in
                    Text(UIStrings.Menu.fps(rate))
                        .font(.system(size: 13, weight: rate == selection ? .medium : .regular))
                        .foregroundStyle(rate == selection ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(rate == selection ? AnyShapeStyle(tint) : AnyShapeStyle(.clear)))
                        .onTapGesture { selection = rate }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.fill.tertiary))
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
            .tint(tint)
        }
    }
}
