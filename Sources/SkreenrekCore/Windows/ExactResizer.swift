import CoreGraphics

/// Resizes a window to an exact output-pixel size of its whole frame and proves it by reading the frame back.
///
/// It tries up to `maxAttempts` times and stops at the first read-back that matches to the pixel. It never reports
/// `exact: true` without such a read-back.
public struct ExactResizer: Sendable {
    public static let defaultAttempts = 3

    public let resizer: any WindowResizer
    public let maxAttempts: Int

    public init(resizer: any WindowResizer, maxAttempts: Int = ExactResizer.defaultAttempts) {
        self.resizer = resizer
        self.maxAttempts = max(1, maxAttempts)
    }

    /// Resizes `target` to `size` px. Throws `usage` (exit 2) for a size the display can't take, before any resize,
    /// and `not_exact` (exit 4) when the read-back still differs after the last attempt, unless `allowInexact`.
    public func resize(_ target: ResolvedWindow, to size: PixelSize, allowInexact: Bool = false) async throws
        -> Readback
    {
        let display = target.display
        let points = try SizeRequest(size).points(scale: display.scale)
        let frame = Self.targetFrame(origin: target.window.frame, size: points, visibleFrame: display.visibleFrame)

        var actuals: [PixelSize] = []
        var readFrame = target.window.frame
        for _ in 1...maxAttempts {
            try await resizer.setFrame(frame, of: target.window)
            readFrame = try await resizer.readFrame(of: target.window)
            let actual = readFrame.pixelSize(scale: display.scale)
            actuals.append(actual)
            if actual == size { break }
        }

        let actual = actuals[actuals.count - 1]
        let readback = Readback(
            window: Readback.Window(target.window), display: Readback.Display(display), requested: size,
            actual: actual, frame: readFrame, exact: actual == size, attempts: actuals.count)
        guard readback.exact || allowInexact else {
            throw SkreenrekError.notExact(
                app: target.window.app, requested: size, actual: actual,
                reason: Self.reason(requested: size, actuals: actuals))
        }
        return readback
    }

    /// Same top-left origin and `size` pt, except that a frame crossing the visible frame's right or bottom edge (or
    /// starting outside it) is moved to start inside it: the visible frame's top-left corner at worst.
    public static func targetFrame(origin current: PointRect, size: CGSize, visibleFrame: PointRect) -> PointRect {
        var x = current.x
        var y = current.y
        let width = Double(size.width)
        let height = Double(size.height)
        let maxX = visibleFrame.x + visibleFrame.width
        let maxY = visibleFrame.y + visibleFrame.height
        if x + width > maxX { x = maxX - width }
        if y + height > maxY { y = maxY - height }
        x = max(x, visibleFrame.x)
        y = max(y, visibleFrame.y)
        return PointRect(x: x, y: y, width: width, height: height)
    }

    /// Why the read-back isn't the requested size. Steps when both dimensions are off, or when the size changed
    /// between the later attempts; otherwise a minimum or maximum for the one dimension that is off.
    public static func reason(requested: PixelSize, actuals: [PixelSize]) -> NotExactReason {
        guard let actual = actuals.last else { return .steps }
        let settled = actuals.dropFirst()
        if let first = settled.first, settled.contains(where: { $0 != first }) { return .steps }
        let dw = actual.width - requested.width
        let dh = actual.height - requested.height
        switch (dw, dh) {
        case (0, 0): return .steps
        case (_, 0): return dw > 0 ? .minWidth(actual.width) : .maxWidth(actual.width)
        case (0, _): return dh > 0 ? .minHeight(actual.height) : .maxHeight(actual.height)
        default: return .steps
        }
    }
}
