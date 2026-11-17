import CoreGraphics
import SkreenrekCore

/// All picker geometry is top-left global points; results are display-local output pixels.
public struct PickerModel: Sendable {
    public let windows: [WindowInfo]
    public let displays: [DisplayInfo]
    public private(set) var hovered: WindowInfo?
    public private(set) var region: PixelRect?
    public private(set) var regionDisplay: DisplayInfo?
    private var anchor: CGPoint?

    public init(windows: [WindowInfo], displays: [DisplayInfo], ownPid: Int32) {
        self.displays = displays
        self.windows = windows.filter {
            $0.pid != ownPid && $0.onScreen && $0.layer == 0
                && $0.frame.width >= WindowDirectory.minimumSide && $0.frame.height >= WindowDirectory.minimumSide
                && !WindowDirectory.systemAppNames.contains($0.app)
                && !WindowDirectory.systemBundleIds.contains($0.bundleId ?? "")
        }
    }

    public mutating func hover(_ point: CGPoint) {
        guard anchor == nil else { return }
        hovered = windows.first { $0.frame.cgRect.contains(point) }
    }

    public mutating func move(forward: Bool = true) {
        guard !windows.isEmpty, region == nil else { return }
        let current = hovered.flatMap { window in windows.firstIndex { $0.id == window.id } }
        let index = current.map { ($0 + (forward ? 1 : windows.count - 1)) % windows.count }
            ?? (forward ? 0 : windows.count - 1)
        hovered = windows[index]
    }

    public mutating func beginDrag(_ point: CGPoint) {
        anchor = point
        region = nil
        regionDisplay = displays.first { $0.frame.cgRect.contains(point) }
    }

    public mutating func drag(to point: CGPoint) {
        guard let anchor, let display = regionDisplay else { return }
        guard hypot(point.x - anchor.x, point.y - anchor.y) >= 3 || region != nil else { return }
        let frame = display.frame.cgRect
        let end = CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
        let x = Int(((min(anchor.x, end.x) - frame.minX) * display.scale).rounded())
        let y = Int(((min(anchor.y, end.y) - frame.minY) * display.scale).rounded())
        let width = Int((abs(end.x - anchor.x) * display.scale).rounded()) / 2 * 2
        let height = Int((abs(end.y - anchor.y) * display.scale).rounded()) / 2 * 2
        region = PixelRect(x: x, y: y, width: width, height: height)
        hovered = nil
    }

    public var selection: PickResult {
        if let region, let display = regionDisplay, region.width >= 2, region.height >= 2 {
            return .region(region, displayId: display.id)
        }
        if region == nil, let hovered { return .window(hovered.id) }
        return .cancelled
    }

    public var regionFrame: PointRect? {
        guard let region, let display = regionDisplay else { return nil }
        return PointRect(x: display.frame.x + Double(region.x) / display.scale,
                         y: display.frame.y + Double(region.y) / display.scale,
                         width: Double(region.width) / display.scale, height: Double(region.height) / display.scale)
    }

    public var pixelSize: PixelSize? {
        guard let hovered, let display = displays.first(where: { $0.id == hovered.displayId }) else { return nil }
        return hovered.frame.pixelSize(scale: display.scale)
    }
    public var title: String { hovered.map { UIStrings.Menu.windowTitle(app: $0.app, title: $0.title) } ?? "" }
    public var detail: String { pixelSize.map(UIStrings.Picker.detail) ?? "" }
    public var voiceOver: String {
        guard let hovered, let size = pixelSize else { return "" }
        return UIStrings.Picker.voiceOver(app: hovered.app, title: hovered.title, size: size)
    }
}
