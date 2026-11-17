import AppKit
import Foundation
import SkreenrekUI
import Testing

/// `debug render-ui` writes non-empty PNGs of the expected sizes in both appearances.
@MainActor
@Suite struct RenderUITests {
    @Test func rendersEverySurfaceInBothAppearances() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let written = try UIRenderer.renderAll(to: folder)
        let names = Set(written.map(\.url.lastPathComponent))
        for appearance in ["light", "dark"] {
            for state in RenderSamples.states.map(\.name) {
                #expect(names.contains("dropdown-\(state)-\(appearance)@2x.png"))
                #expect(names.contains("statusrow-\(state)-\(appearance)@2x.png"))
                #expect(names.contains("menubaricon-\(state)-\(appearance)@2x.png"))
            }
            #expect(names.contains("submenu-size-\(appearance)@2x.png"))
            #expect(names.contains("submenu-framerate-\(appearance)@2x.png"))
            #expect(names.contains("settings-default-\(appearance)@2x.png"))
        }

        for file in written {
            let data = try Data(contentsOf: file.url)
            let rep = try #require(NSBitmapImageRep(data: data), "\(file.url.lastPathComponent)")
            #expect(rep.pixelsWide == file.pixelWidth)
            #expect(rep.pixelsHigh == file.pixelHeight)
            #expect(Self.hasVisiblePixels(rep), "\(file.url.lastPathComponent) is empty")
        }

        func size(_ name: String) throws -> (Int, Int) {
            let file = try #require(written.first { $0.url.lastPathComponent == name })
            return (file.pixelWidth, file.pixelHeight)
        }
        // Status rows: 300 pt wide, 48 pt tall (64 pt when the detail wraps) at 2×.
        for appearance in ["light", "dark"] {
            #expect(try size("statusrow-idle-\(appearance)@2x.png") == (600, 96))
            #expect(try size("statusrow-recording-\(appearance)@2x.png") == (600, 96))
            #expect(try size("statusrow-armednotexact-\(appearance)@2x.png") == (600, 96))
            #expect(try size("statusrow-errorwindowclosed-\(appearance)@2x.png") == (600, 128))
            #expect(try size("dropdown-idle-\(appearance)@2x.png").0 == 600)
            #expect(try size("settings-default-\(appearance)@2x.png").0 == 960)
        }
        for file in written where file.url.lastPathComponent.hasPrefix("dropdown-") {
            #expect(file.pixelWidth == 600)
        }
    }

    /// Light and dark differ, so the appearance really was forced.
    @Test func appearancesDiffer() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = try UIRenderer.renderAll(to: folder)
        let light = try #require(written.first { $0.url.lastPathComponent == "dropdown-idle-light@2x.png" })
        let dark = try #require(written.first { $0.url.lastPathComponent == "dropdown-idle-dark@2x.png" })
        #expect(try Data(contentsOf: light.url) != Data(contentsOf: dark.url))
    }

    static func hasVisiblePixels(_ rep: NSBitmapImageRep) -> Bool {
        var colors = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 40)
        let stepY = max(1, rep.pixelsHigh / 40)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0 else { continue }
                let key =
                    UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8
                    | UInt32(c.blueComponent * 255)
                colors.insert(key)
                if colors.count > 1 { return true }
            }
        }
        return false
    }
}
