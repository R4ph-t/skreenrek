import CoreGraphics
import Foundation
import SkreenrekCore
import Testing

/// Spec 13 v2: a size is the clip's exact pixels; the window is the largest of that shape that fits the display
/// (visible frame minus 32 pt a side), between half the clip and the clip in points, and never scales up.
@Suite struct WindowFitTests {
    /// Retina MacBook Pro 14": 1512 × 982 pt, usable ~1448 × 870.
    static let laptop = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 934))
    /// A 1× external display: usable 1856 × 991.
    static let external = DisplayInfo(
        id: 2, name: "Studio Display", scale: 1, frame: PointRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: PointRect(x: 1512, y: 25, width: 1920, height: 1055))
    /// A large 1× display where everything fits.
    static let large = DisplayInfo(
        id: 3, name: "Large Display", scale: 1, frame: PointRect(x: 0, y: 0, width: 5120, height: 2880),
        visibleFrame: PointRect(x: 0, y: 25, width: 5120, height: 2855))
    static let oneAndAHalf = DisplayInfo(
        id: 4, name: "1.5×", scale: 1.5, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 934))

    @Test func roomIsTheVisibleFrameMinus32PointsASide() {
        #expect(WindowFit.room(on: Self.laptop) == WindowPoints(width: 1448, height: 870))
    }

    /// The spec's laptop examples.
    @Test(arguments: [
        (SizePreset.p720, 1280, 720, 2.0),
        (SizePreset.p1080, 1440, 810, 1.5),
        (SizePreset.p1440, 1440, 810, 1.125),
        (SizePreset.square, 870, 870, 1.611),
    ])
    func laptopPresets(preset: SizePreset, width: Int, height: Int, nativeToClip: Double) throws {
        let plan = try WindowFit.plan(clip: preset.size, on: Self.laptop).get()
        #expect(plan.window == WindowPoints(width: width, height: height))
        #expect(plan.clip == preset.size)
        #expect(plan.cropped == nil)
        #expect(plan.nativeToClip == nativeToClip)
        // Recorded natively and scaled down, never up.
        #expect(plan.native.width >= preset.size.width && plan.native.height >= preset.size.height)
    }

    @Test func tenEightyOnTheLaptopIsALargeWindowAndAnExactClip() throws {
        let plan = try WindowFit.plan(clip: PixelSize(width: 1920, height: 1080), on: Self.laptop).get()
        #expect(plan.window == WindowPoints(width: 1440, height: 810))
        #expect(plan.native == PixelSize(width: 2880, height: 1620))
    }

    @Test func fourKAndPortraitDontFitTheLaptop() {
        guard case .failure(let fourK) = WindowFit.plan(clip: SizePreset.uhd4k.size, on: Self.laptop),
            case .failure(let portrait) = WindowFit.plan(clip: SizePreset.portrait.size, on: Self.laptop)
        else {
            Issue.record("4K and Portrait should not fit the laptop")
            return
        }
        #expect(fourK.needs == WindowPoints(width: 1920, height: 1080))
        #expect(fourK.fits == WindowPoints(width: 1448, height: 870))
        #expect(fourK.tooltip == "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p.")
        #expect(portrait.needs == WindowPoints(width: 540, height: 960))
        #expect(
            portrait.tooltip == "Portrait needs room for a 540 × 960 pt window. Use a larger display or pick Square.")
    }

    @Test func oneXWindowIsTheClipSizeAndMustFit() throws {
        let plan = try WindowFit.plan(clip: PixelSize(width: 1280, height: 720), on: Self.external).get()
        #expect(plan.window == WindowPoints(width: 1280, height: 720))
        #expect(plan.nativeToClip == 1)
        guard case .failure(let failure) = WindowFit.plan(clip: SizePreset.p1080.size, on: Self.external) else {
            Issue.record("1080p needs a 1920 × 1080 pt window at 1×")
            return
        }
        #expect(failure.needs == WindowPoints(width: 1920, height: 1080))
        #expect(failure.fits == WindowPoints(width: 1856, height: 991))
        #expect(failure.tooltip == "1080p needs room for a 1920 × 1080 pt window. Use a larger display or pick 720p.")
    }

    @Test func everyPresetFitsTheLargeDisplay() {
        for preset in SizePreset.allCases {
            #expect(WindowFit.fits(preset.size, on: Self.large), "\(preset)")
        }
        let fourK = try? WindowFit.plan(clip: SizePreset.uhd4k.size, on: Self.large).get()
        #expect(fourK?.window == WindowPoints(width: 3840, height: 2160))
    }

    @Test func noPresetEverUpscales() {
        for display in [Self.laptop, Self.external, Self.large, Self.oneAndAHalf] {
            for preset in SizePreset.allCases {
                guard case .success(let plan) = WindowFit.plan(clip: preset.size, on: display) else { continue }
                #expect(plan.nativeToClip >= 1, "\(preset) on \(display.name)")
                #expect(plan.window.width <= preset.size.width && plan.window.height <= preset.size.height)
            }
        }
    }

    @Test func cropsAtMostOnePixelWhenTheExactAspectHasNoWindow() throws {
        let plan = try WindowFit.plan(clip: PixelSize(width: 1006, height: 900), on: Self.oneAndAHalf).get()
        #expect(plan.window == WindowPoints(width: 969, height: 867))
        #expect(plan.cropped == PixelSize(width: 1, height: 1))
    }

    @Test func aCustomSizeThatDoesntFitNamesItsPixels() {
        guard case .failure(let failure) = WindowFit.plan(clip: PixelSize(width: 3000, height: 2000), on: Self.laptop)
        else {
            Issue.record("3000 × 2000 needs 1500 × 1000 pt")
            return
        }
        #expect(failure.error.message == "3000 × 2000 px needs a window at least 1500 × 1000 on screen; this display fits 1448 × 870")
        #expect(
            failure.error.hint
                == "3000 × 2000 px needs room for a 1500 × 1000 pt window. Use a larger display. "
                + "Use a smaller --size, or move the window to a larger display.")
    }

    @Test func sourceRectCropsTheLongSideNeverLetterboxes() {
        #expect(WindowFit.sourceRect(window: CGSize(width: 1440, height: 810), clip: PixelSize(width: 1920, height: 1080)) == nil)
        let wide = WindowFit.sourceRect(window: CGSize(width: 1441, height: 810), clip: PixelSize(width: 1920, height: 1080))
        #expect(wide == CGRect(x: 0.5, y: 0, width: 1440, height: 810))
        let tall = WindowFit.sourceRect(window: CGSize(width: 1440, height: 812), clip: PixelSize(width: 1920, height: 1080))
        #expect(tall == CGRect(x: 0, y: 1, width: 1440, height: 810))
    }
}

@Suite struct SizeSpecTests {
    @Test(arguments: [
        ("720p", 1280, 720), ("1080p", 1920, 1080), ("1440p", 2560, 1440), ("4k", 3840, 2160), ("4K", 3840, 2160),
        ("square", 1080, 1080), ("Portrait", 1080, 1920), ("1720x1080", 1720, 1080), ("1720X1080", 1720, 1080),
        ("1720×1080", 1720, 1080), ("1720x1080px", 1720, 1080), ("1920x1080PX", 1920, 1080),
    ])
    func parses(text: String, width: Int, height: Int) throws {
        #expect(try SizeSpec.parse(text) == PixelSize(width: width, height: height))
    }

    @Test(arguments: ["8k", "1080", "x1080", "1920x", "1920x1080pt", "-2x4", "px", ""])
    func rejects(text: String) {
        let error = #expect(throws: SkreenrekError.self) { try SizeSpec.parse(text) }
        #expect(error?.exitCode == 2)
        #expect(error?.hint == "Pass --size 720p|1080p|1440p|4k|square|portrait, or WxH in pixels, e.g. --size 1920x1080.")
    }

    @Test func presetNamesAndTitles() {
        #expect(SizePreset.allCases.map(\.title) == ["720p", "1080p", "1440p", "4K", "Square", "Portrait"])
        #expect(SizePreset(size: PixelSize(width: 1920, height: 1080)) == .p1080)
        #expect(SizePreset(size: PixelSize(width: 1280, height: 800)) == nil)
    }
}
