import AppKit
@testable import SkreenrekUI
import SwiftUI
import Testing

/// The hosted header and Last Clip row keep the menu's 300 pt width, and the leading icons follow the menu's
/// highlight unless they carry the primary tint.
@Suite struct DropdownLayoutTests {
    @Test func headerAndClipRowKeepTheMenuWidth() async throws {
        try await onMain("dropdown hosted rows") {
            for sample in RenderSamples.states {
                for row in DropdownModel.rows(for: sample.context) {
                    switch row {
                    case .header(let header):
                        let size = MenuController.hosted(DropdownHeaderView(header: header)).fittingSize
                        #expect(size.width == MenuMetrics.width, "\(sample.name)")
                        #expect(size.height >= DropdownHeaderView.minHeight, "\(sample.name)")
                        // One-line details keep the 64 pt band (the not-exact reason lives in the tooltip).
                        #expect(DropdownHeaderView.bandHeight == 64)
                        if ["idle", "armed", "armednotexact", "lastclip"].contains(sample.name) {
                            #expect(size.height == DropdownHeaderView.minHeight, "\(sample.name)")
                        }
                    case .clip(let clip):
                        let size = MenuController.hosted(ClipRowView(clip: clip, thumbnail: nil)).fittingSize
                        #expect(size == CGSize(width: MenuMetrics.width, height: ClipRowView.height), "\(sample.name)")
                    default:
                        continue
                    }
                }
            }
        }
    }

    @Test func leadingIconsAreTemplatesUnlessTinted() async throws {
        try await onMain("menu icons") {
            #expect(MenuController.icon("folder", .neutral)?.isTemplate == true)
            #expect(MenuController.icon("record.circle", .red)?.isTemplate == false)
            #expect(MenuController.icon("macwindow", .accent)?.isTemplate == false)
            #expect(MenuController.icon(nil, .neutral) == nil)
        }
    }

    @Test func statusItemImageIsMonoUnlessRecording() async throws {
        try await onMain("status item image") {
            #expect(BrandStatusGlyph.statusItemImage(.idle, accent: false).isTemplate)
            let recording = BrandStatusGlyph.statusItemImage(.recording, accent: true)
            #expect(!recording.isTemplate)
            #expect(recording.size == NSSize(width: BrandStatusGlyph.size, height: BrandStatusGlyph.size))
        }
    }
}
