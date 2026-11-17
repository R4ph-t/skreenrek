import AVFoundation
import AppKit

/// The Last Clip row's thumbnail: the clip's first frame, decoded once off the main thread and kept for the newest
/// clip only. Reads a file the app wrote; needs no permission.
@MainActor
final class ClipThumbnails {
    /// Called on the main actor when a thumbnail finishes loading.
    var onLoad: (() -> Void)?

    private var path: String?
    private var image: NSImage?
    private var loading: String?
    private var failed: Set<String> = []

    /// The thumbnail for `path`, or nil while it loads (the row shows a neutral fill, then `onLoad` fires).
    func image(for path: String) -> NSImage? {
        if path == self.path { return image }
        guard loading != path, !failed.contains(path) else { return nil }
        loading = path
        Task { [weak self] in
            let frame = await Self.firstFrame(URL(fileURLWithPath: path))
            guard let self, self.loading == path else { return }
            self.loading = nil
            guard let frame else {
                self.failed.insert(path)
                return
            }
            self.path = path
            self.image = NSImage(cgImage: frame, size: NSSize(width: frame.width / 2, height: frame.height / 2))
            self.onLoad?()
        }
        return nil
    }

    /// Two thumbnail widths (72 pt) at 2×, so the 16:10 frame stays sharp on Retina.
    nonisolated static let maximumSize = CGSize(width: 288, height: 180)

    nonisolated static func firstFrame(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        return try? await generator.image(at: .zero).image
    }
}
