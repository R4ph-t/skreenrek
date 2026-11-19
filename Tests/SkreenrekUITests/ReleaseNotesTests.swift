@testable import SkreenrekUI
import Testing

/// What's new: a release body becomes one line per section heading, item and paragraph.
@Suite struct ReleaseNotesTests {
    typealias Block = ReleaseNotes.Block

    @Test func theVersionHeadingIsDroppedAndSectionsAndItemsKeepTheirOwnLines() {
        let notes = """
            ## [1.0.6] - 2026-11-19

            ### Added

            - A Clear button next to the window's title.
            - An X button at the end of the control bar.

            ### Fixed

            - The outline follows the window.
            """
        #expect(
            ReleaseNotes.blocks(notes) == [
                .heading("Added"), .bullet("A Clear button next to the window's title."),
                .bullet("An X button at the end of the control bar."),
                .heading("Fixed"), .bullet("The outline follows the window."),
            ])
    }

    @Test(arguments: ["## [1.0.6] - 2026-11-19", "## 1.0.6", "# v1.0.6 (2026-11-19)", "### [2.10.0]"])
    func everyVersionHeadingFormIsDropped(heading: String) {
        #expect(ReleaseNotes.blocks("\(heading)\n\n- One") == [.bullet("One")])
    }

    @Test func aLeadingTitleIsDroppedButALaterOneStays() {
        #expect(ReleaseNotes.blocks("# Skreenrek 1.0.6\n- One\n# Later") == [.bullet("One"), .heading("Later")])
    }

    @Test func crlfAndCrLineEndingsSplitLikeNewlines() {
        let blocks: [Block] = [.heading("Added"), .bullet("One"), .bullet("Two")]
        #expect(ReleaseNotes.blocks("## [1.0.6]\r\n### Added\r\n- One\r\n- Two\r\n") == blocks)
        #expect(ReleaseNotes.blocks("### Added\r- One\r- Two") == blocks)
    }

    @Test(arguments: ["", "   ", "\n\n\r\n", "## [1.0.6] - 2026-11-19\n\n---\n"])
    func blankNotesHaveNoBlocks(notes: String) {
        #expect(ReleaseNotes.blocks(notes).isEmpty)
    }

    @Test func notesWithoutHeadingsAreParagraphsAndItems() {
        let notes = "Small fixes.\nWrapped on two lines.\n\nAnother paragraph.\n* Star item\n+ Plus item"
        #expect(
            ReleaseNotes.blocks(notes) == [
                .paragraph("Small fixes. Wrapped on two lines."), .paragraph("Another paragraph."),
                .bullet("Star item"), .bullet("Plus item"),
            ])
    }

    @Test func aWrappedItemStaysOneItemAndInlineMarkdownIsLeftForText() {
        let notes = "- With `--no-hud` the bar\n  hides, see **Settings**.\n  - Nested [link](https://example.com)"
        #expect(
            ReleaseNotes.blocks(notes) == [
                .bullet("With `--no-hud` the bar hides, see **Settings**."),
                .bullet("Nested [link](https://example.com)"),
            ])
    }

    @Test func closingHashesAndEmptyHeadingsAreDropped() {
        #expect(ReleaseNotes.blocks("### Changed ###\n#\n#hashtag") == [.heading("Changed"), .paragraph("#hashtag")])
    }
}
