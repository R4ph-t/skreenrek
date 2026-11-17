import CoreGraphics

/// Resizes a window for an exact clip size and proves it by reading the frame back.
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

    /// Resizes `target` so it records as a `size` px clip: the window gets `WindowFit`'s size on its display and is
    /// read back. Throws `usage` (exit 2) for a size that's invalid or can't fit without scaling up, before any
    /// resize, and `not_exact` (exit 4) when the window read back still differs after the last attempt, unless
    /// `allowInexact`.
    public func resize(_ target: ResolvedWindow, to size: PixelSize, allowInexact: Bool = false) async throws
        -> Readback
    {
        let display = target.display
        try SizeRequest(size).validate()
        let plan: WindowPlan
        switch WindowFit.plan(clip: size, on: display) {
        case .success(let fit): plan = fit
        case .failure(let failure): throw failure.error
        }
        let points = CGSize(width: plan.window.width, height: plan.window.height)
        let frame = Self.targetFrame(origin: target.window.frame, size: points, visibleFrame: display.visibleFrame)

        var actuals: [PixelSize] = []
        var readFrame = target.window.frame
        for _ in 1...maxAttempts {
            try await resizer.setFrame(frame, of: target.window)
            readFrame = try await resizer.readFrame(of: target.window)
            let actual = Self.clipSize(of: readFrame, plan: plan)
            actuals.append(actual)
            if actual == size { break }
        }

        let actual = actuals[actuals.count - 1]
        let readback = Readback(
            window: Readback.Window(target.window), display: Readback.Display(display), requested: size,
            actual: actual, frame: readFrame, exact: actual == size, attempts: actuals.count,
            cropped: actual == size ? plan.cropped : nil)
        guard readback.exact || allowInexact else {
            throw SkreenrekError.notExact(
                app: target.window.app, requested: size, actual: actual,
                reason: Self.reason(requested: size, actuals: actuals))
        }
        return readback
    }

    /// The clip a read-back frame gives: the requested clip when the window reached the planned size to the pixel,
    /// otherwise the window's pixels scaled by the plan's native-to-clip ratio (so a window that stopped short shows
    /// how far off it is, in clip px).
    static func clipSize(of frame: PointRect, plan: WindowPlan) -> PixelSize {
        let native = frame.pixelSize(scale: plan.displayScale)
        if native == plan.native { return plan.clip }
        let ratio = Double(plan.native.width) / Double(plan.clip.width + (plan.cropped?.width ?? 0))
        let ratioH = Double(plan.native.height) / Double(plan.clip.height + (plan.cropped?.height ?? 0))
        return PixelSize(
            width: Int((Double(native.width) / ratio).rounded()), height: Int((Double(native.height) / ratioH).rounded()))
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
