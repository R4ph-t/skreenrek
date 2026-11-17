import AppKit
@testable import SkreenrekUI
import Testing

@Suite struct StatusRowLayoutTests {
    @Test func everyStatusRowReservesSixteenPointsAndWrapsLongDetails() async throws {
        try await onMain("dropdown status insets") {
            #expect(MenuMetrics.statusTrailingPadding == 16)
            #expect(MenuMetrics.textWidth == 252)
            for sample in RenderSamples.states {
                for entry in MenuModel.entries(for: sample.context) {
                    guard case .status(let row) = entry else { continue }
                    let view = StatusRowView(row)
                    let labels = view.subviews.compactMap { $0 as? NSTextField }
                    for label in labels {
                        // NSTextField reserves 2 pt on each side; actual text stays inside the 16 pt inset.
                        #expect(label.frame.maxX - 2 <= view.bounds.width - 16)
                    }
                    if sample.name == "armednotexact" {
                        // One line: the reason lives in the tooltip and the VoiceOver label.
                        #expect(view.frame.height == 48)
                        #expect(labels.last?.stringValue == "1286 × 800 px · not exact")
                        let reason =
                            "Safari won't go narrower than 1286 px, so the clip is 1286 × 800 instead of 1280 × 800."
                        #expect(view.toolTip == reason)
                        #expect(view.accessibilityLabel()?.hasSuffix(reason) == true)
                    }
                }
            }
        }
    }
}
