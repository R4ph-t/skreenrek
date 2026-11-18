import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI

/// Draws the V1 logo kit from its own SVG geometry (`BrandKit`), so the menu-bar glyphs can be split into a template
/// layer and an accent layer, and the mark can sit on the dropdown's graphite tile.
///
/// The kit's SVGs use a small subset: `<g>` groups carrying fill and stroke, `<path>` with absolute M/L/Z,
/// `<circle>`, butt caps and miter joins. Paint is classified rather than copied: the kit's ink (`#000` in the
/// menu-bar set, `#F5F5F7` in the icon) is the template/ink layer, `url(#rec)` is the record dot's gradient, any
/// other colour is the accent layer, and the icon's body, sheen and edge paints are skipped.
enum KitSVG {
    enum Paint: Equatable {
        case ink
        case accent
        case recordGradient
        case other
    }

    enum Geometry: Equatable {
        /// A filled polygon.
        case polygon([CGPoint])
        /// A stroked polyline (closed when `closed`).
        case stroke([CGPoint], width: CGFloat, closed: Bool)
        case disc(center: CGPoint, radius: CGFloat)
        case ring(center: CGPoint, radius: CGFloat, width: CGFloat)
    }

    struct Shape: Equatable {
        var geometry: Geometry
        var paint: Paint
    }

    struct Drawing: Equatable {
        var viewBox: CGRect
        var shapes: [Shape]
    }

    static func parse(_ svg: String) -> Drawing {
        var viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)
        var shapes: [Shape] = []
        // Fill and stroke inherited from enclosing groups; nil entries for groups that set neither.
        var groups: [(fill: String?, stroke: String?)] = []
        var skipDepth = 0  // inside <defs> or <clipPath>
        let tag = /<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/
        for match in svg.matches(of: tag) {
            let closing = !match.output.1.isEmpty
            let name = String(match.output.2)
            let attributes = attributes(String(match.output.3))
            let selfClosing = !match.output.4.isEmpty
            if name == "defs" || name == "clipPath" {
                if closing { skipDepth -= 1 } else if !selfClosing { skipDepth += 1 }
                continue
            }
            if skipDepth > 0 { continue }
            switch name {
            case "svg":
                if let box = attributes["viewBox"]?.split(separator: " ").compactMap({ Double($0) }), box.count == 4 {
                    viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
                }
            case "g":
                if closing {
                    _ = groups.popLast()
                } else if !selfClosing {
                    groups.append((attributes["fill"], attributes["stroke"]))
                }
            case "path", "circle":
                guard !closing else { continue }
                let fill = attributes["fill"] ?? groups.last(where: { $0.fill != nil })?.fill
                let stroke = attributes["stroke"] ?? groups.last(where: { $0.stroke != nil })?.stroke
                let width = attributes["stroke-width"].flatMap(Double.init).map { CGFloat($0) }
                if let shape = shape(name, attributes, fill: fill, stroke: stroke, width: width) {
                    shapes.append(shape)
                }
            default:
                continue
            }
        }
        return Drawing(viewBox: viewBox, shapes: shapes)
    }

    private static func shape(
        _ name: String, _ attributes: [String: String], fill: String?, stroke: String?, width: CGFloat?
    ) -> Shape? {
        let stroked = fill == "none"
        let paint = classify(stroked ? stroke : fill)
        if name == "circle" {
            guard let cx = attributes["cx"].flatMap(Double.init), let cy = attributes["cy"].flatMap(Double.init),
                let r = attributes["r"].flatMap(Double.init)
            else { return nil }
            let center = CGPoint(x: cx, y: cy)
            if stroked, let width { return Shape(geometry: .ring(center: center, radius: r, width: width), paint: paint) }
            return Shape(geometry: .disc(center: center, radius: r), paint: paint)
        }
        guard let d = attributes["d"] else { return nil }
        let (points, closed) = points(d)
        guard points.count >= 2 else { return nil }
        if stroked, let width {
            return Shape(geometry: .stroke(points, width: width, closed: closed), paint: paint)
        }
        return Shape(geometry: .polygon(points), paint: paint)
    }

    static func classify(_ value: String?) -> Paint {
        guard let value else { return .other }
        switch value.uppercased() {
        case "#000", "#000000", "#F5F5F7": return .ink
        case "URL(#REC)": return .recordGradient
        default: return value.hasPrefix("#") ? .accent : .other
        }
    }

    /// Absolute M/L/Z only (all the kit uses).
    static func points(_ d: String) -> ([CGPoint], closed: Bool) {
        let tokens = d.matches(of: /[MLZmlz]|-?\d*\.?\d+/).map { String($0.output) }
        var points: [CGPoint] = []
        var closed = false
        var numbers: [Double] = []
        for token in tokens {
            if let value = Double(token) {
                numbers.append(value)
                if numbers.count == 2 {
                    points.append(CGPoint(x: numbers[0], y: numbers[1]))
                    numbers.removeAll()
                }
            } else if token == "Z" || token == "z" {
                closed = true
            }
        }
        return (points, closed)
    }

    private static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in text.matches(of: /([a-zA-Z:-]+)="([^"]*)"/) {
            result[String(match.output.1)] = String(match.output.2)
        }
        return result
    }

    /// Draws `drawing`'s shapes whose paint is in `paints`, mapping `region` (in SVG units) onto `rect` (in the
    /// context's flipped-or-not space; the drawing is flipped so SVG's y-down holds).
    static func draw(
        _ drawing: Drawing, paints: Set<Paint>, region: CGRect? = nil, in rect: CGRect, context: CGContext,
        color: (Paint) -> CGColor, gradient: CGGradient? = nil
    ) {
        let source = region ?? drawing.viewBox
        context.saveGState()
        defer { context.restoreGState() }
        // SVG is y-down; AppKit image contexts are y-up.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / source.width, y: -rect.height / source.height)
        context.translateBy(x: -source.minX, y: -source.minY)
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        context.setMiterLimit(10)
        for shape in drawing.shapes where paints.contains(shape.paint) {
            let path = CGMutablePath()
            switch shape.geometry {
            case .polygon(let points):
                path.addLines(between: points)
                path.closeSubpath()
                fill(path, shape.paint, context, color, gradient)
            case .stroke(let points, let width, let closed):
                path.addLines(between: points)
                if closed { path.closeSubpath() }
                let outline = path.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
                fill(outline, shape.paint, context, color, gradient)
            case .disc(let center, let radius):
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                fill(path, shape.paint, context, color, gradient)
            case .ring(let center, let radius, let width):
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                let outline = path.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
                fill(outline, shape.paint, context, color, gradient)
            }
        }
    }

    private static func fill(
        _ path: CGPath, _ paint: Paint, _ context: CGContext, _ color: (Paint) -> CGColor, _ gradient: CGGradient?
    ) {
        if paint == .recordGradient, let gradient {
            context.saveGState()
            context.addPath(path)
            context.clip()
            let box = path.boundingBoxOfPath
            context.drawLinearGradient(
                gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
            context.restoreGState()
        } else {
            context.addPath(path)
            context.setFillColor(color(paint))
            context.fillPath()
        }
    }
}

/// The V1 menu-bar glyph: mono (one template image, the default) or bichrome (a template layer plus an accent
/// layer: systemRed for the recording dot, systemOrange for the error "!").
enum BrandStatusGlyph {
    enum Style: String, CaseIterable, Sendable {
        case mono
        case bichrome
    }

    /// The kit's glyph size, in points.
    static let size: CGFloat = 18

    static func state(for state: ControllerState) -> BrandKit.MenuBarState {
        switch state {
        case .idle: .idle
        case .armed: .armed
        case .recording: .recording
        case .writing: .saving
        case .error: .error
        }
    }

    /// Mono: the whole glyph as a template image. Bichrome: the ink parts only, as a template image.
    @MainActor
    static func templateLayer(_ state: BrandKit.MenuBarState, style: Style) -> NSImage {
        let svg = style == .mono ? BrandKit.monoSVG(state) : BrandKit.bichromeSVG(state)
        let drawing = KitSVG.parse(svg)
        let paints: Set<KitSVG.Paint> = style == .mono ? [.ink, .accent] : [.ink]
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            KitSVG.draw(drawing, paints: paints, in: rect, context: context) { _ in NSColor.black.cgColor }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The status item's image. Mono is one template image that follows the menu bar. With `accent` (recording),
    /// the bichrome glyph in one image: the ink drawn in `labelColor` each time it's drawn, so it still follows the
    /// bar's appearance, and the record dot in systemRed.
    @MainActor
    static func statusItemImage(_ state: BrandKit.MenuBarState, accent: Bool) -> NSImage {
        guard accent else { return templateLayer(state, style: .mono) }
        let drawing = KitSVG.parse(BrandKit.bichromeSVG(state))
        let color = state == .recording ? NSColor.systemRed : NSColor.systemOrange
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            KitSVG.draw(drawing, paints: [.ink, .accent], in: rect, context: context) { paint in
                paint == .accent ? color.cgColor : NSColor.labelColor.cgColor
            }
            return true
        }
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    /// Bichrome's accent layer (not a template), or nil when the state has no accent part.
    @MainActor
    static func accentLayer(_ state: BrandKit.MenuBarState) -> NSImage? {
        let drawing = KitSVG.parse(BrandKit.bichromeSVG(state))
        guard drawing.shapes.contains(where: { $0.paint == .accent }) else { return nil }
        let color = state == .recording ? NSColor.systemRed : NSColor.systemOrange
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            KitSVG.draw(drawing, paints: [.accent], in: rect, context: context) { _ in color.cgColor }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// What the status item's button holds, for the renders: the template layer, the accent layer above it (bichrome), and the
/// elapsed time beside the glyph while recording. In a real `NSStatusBarButton` the system tints the template layer
/// for the bar; this preview tints it with `labelColor` for the forced appearance, which is what the bar does when
/// active (an offscreen `NSImageView` would draw it dimmed).
final class BrandStatusGlyphView: NSView {
    static let height: CGFloat = 24
    static let padding: CGFloat = 8
    static let gap: CGFloat = 4
    static var elapsedFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular) }

    let template: NSImage
    let accent: NSImage?
    let elapsed: String?

    init(state: BrandKit.MenuBarState, style: BrandStatusGlyph.Style, elapsed: String?, sentence: String) {
        template = BrandStatusGlyph.templateLayer(state, style: style)
        accent = style == .bichrome ? BrandStatusGlyph.accentLayer(state) : nil
        self.elapsed = elapsed
        let elapsedWidth = elapsed.map { ceil(($0 as NSString).size(withAttributes: [.font: Self.elapsedFont]).width) }
        let width = Self.padding * 2 + BrandStatusGlyph.size + (elapsedWidth.map { Self.gap + $0 } ?? 0)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(sentence)
        toolTip = sentence
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        Self.menuBarBackground.setFill()
        bounds.fill()
        let glyph = BrandStatusGlyph.size
        let rect = NSRect(x: Self.padding, y: (bounds.height - glyph) / 2, width: glyph, height: glyph)
        Self.tinted(template, .labelColor).draw(in: rect)
        accent?.draw(in: rect)
        if let elapsed {
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.elapsedFont, .foregroundColor: NSColor.labelColor]
            let size = (elapsed as NSString).size(withAttributes: attributes)
            (elapsed as NSString).draw(
                at: NSPoint(x: rect.maxX + Self.gap, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
    }

    /// A template image filled with `color`, the way AppKit renders templates.
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// A neutral menu-bar tone for the renders (the real bar is translucent over the wallpaper).
    static let menuBarBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    }
}

/// The V1 icon artwork.
@MainActor
enum BrandIcon {
    /// `icon-dark`: the app icon, every PNG size from the kit as one multi-resolution image of `size` points.
    static func appIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        for base64 in [BrandKit.iconDark16PNG, BrandKit.iconDark32PNG, BrandKit.iconDark64PNG,
                       BrandKit.iconDark128PNG, BrandKit.iconDark256PNG] {
            guard let data = Data(base64Encoded: base64), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = NSSize(width: size, height: size)
            image.addRepresentation(rep)
        }
        return image
    }

    /// `icon-dark`'s mark (white k's and the red record dot) without its body, for the header's graphite tile. The icon's
    /// body spans 100…924 of its 1024 grid, so that square maps onto the tile. Small tiles use `icon-dark-small`'s
    /// heavier stroke, as the kit does for 64 px and below.
    static func tileMark(size: CGFloat) -> NSImage {
        if let cached = marks[size] { return cached }
        let image = drawTileMark(size: size)
        marks[size] = image
        return image
    }

    /// Parsed once per size: the icon SVG is large, and the header redraws while the menu is open.
    private static var marks: [CGFloat: NSImage] = [:]

    private static func drawTileMark(size: CGFloat) -> NSImage {
        let svg = size * 2 <= 64 ? BrandKit.iconDarkSmallSVG : BrandKit.iconDarkSVG
        let drawing = KitSVG.parse(svg)
        let ink = NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1).cgColor
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                NSColor(srgbRed: 1, green: 0x5F / 255, blue: 0x55 / 255, alpha: 1).cgColor,
                NSColor(srgbRed: 0xE5 / 255, green: 0x28 / 255, blue: 0x1E / 255, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            KitSVG.draw(
                drawing, paints: [.ink, .recordGradient], region: CGRect(x: 100, y: 100, width: 824, height: 824),
                in: rect, context: context, color: { _ in ink }, gradient: gradient)
            return true
        }
    }
}

/// The dropdown header's tile: the kit mark on graphite (0.16 light, 0.22 dark).
struct KitMarkTile: View {
    var size: CGFloat = 40
    var radius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(BrandTheme.graphite)
            .overlay(Image(nsImage: BrandIcon.tileMark(size: size)).resizable().interpolation(.high))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
