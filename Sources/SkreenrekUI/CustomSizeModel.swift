import Foundation
import SkreenrekCore

/// The Custom Size panel's logic (spec 13): two fields in clip px, even numbers only (odd values snap down on
/// Return), and a live line with the window Skreenrek would put on screen, or why the size can't fit. Pure.
public struct CustomSizeModel: Sendable, Hashable {
    public enum Line: Sendable, Hashable {
        /// Quiet secondary text: the prompt, or `Window on screen: 1440 × 810`.
        case quiet(String)
        /// 12 pt red: `Too large for this display.`
        case problem(String)
        case none

        public var text: String? {
            switch self {
            case .quiet(let text), .problem(let text): text
            case .none: nil
            }
        }
    }

    public var widthText: String
    public var heightText: String
    /// The display the window would go on; nil skips the fit check.
    public var display: DisplayInfo?

    public init(widthText: String = "", heightText: String = "", display: DisplayInfo?) {
        self.widthText = widthText
        self.heightText = heightText
        self.display = display
    }

    public init(current: PixelSize?, display: DisplayInfo?) {
        self.init(
            widthText: current.map { String($0.width) } ?? "", heightText: current.map { String($0.height) } ?? "",
            display: display)
    }

    /// The fields as whole px, odd values snapped down to even.
    public var snapped: PixelSize? {
        guard let size = parsed else { return nil }
        return PixelSize(width: Self.even(size.width), height: Self.even(size.height))
    }

    /// Return: rewrites odd values as the even size they snap to.
    public mutating func snap() {
        guard let snapped else { return }
        widthText = String(snapped.width)
        heightText = String(snapped.height)
    }

    /// The (snapped) size when it's in range and fits the display; nil otherwise.
    public var size: PixelSize? {
        guard let size = snapped, (try? SizeRequest(size).validate()) != nil else { return nil }
        if let display, !WindowFit.fits(size, on: display) { return nil }
        return size
    }

    public var isValid: Bool { size != nil }

    public var line: Line {
        guard let size = snapped else { return .quiet(UIStrings.CustomSize.enterSize) }
        do {
            try SizeRequest(size).validate()
        } catch {
            return .problem(error.message)
        }
        guard let display else { return .none }
        switch WindowFit.plan(clip: size, on: display) {
        case .success(let plan): return .quiet(UIStrings.CustomSize.windowOnScreen(plan.window))
        case .failure: return .problem(UIStrings.CustomSize.tooLarge)
        }
    }

    private var parsed: PixelSize? {
        guard let w = Int(widthText.trimmingCharacters(in: .whitespaces)),
            let h = Int(heightText.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return PixelSize(width: w, height: h)
    }

    private static func even(_ value: Int) -> Int { value % 2 == 0 ? value : max(2, value - 1) }
}
