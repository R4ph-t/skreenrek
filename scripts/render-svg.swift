// Render an SVG to a square PNG with a transparent background, through WebKit so SVG filters (the kit's drop
// shadows) render the way they do in a browser. Used by scripts/make-app-icon.sh; not part of the Swift package.
//
//   swift scripts/render-svg.swift <in.svg> <pixels> <out.png>
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 4, let parsed = Int(args[2]), parsed > 0 else {
    FileHandle.standardError.write("usage: render-svg.swift <in.svg> <pixels> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let pixels = Int(args[2])!
let svg = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[3])

func die(_ message: String) -> Never {
    FileHandle.standardError.write("render-svg: \(message)\n".data(using: .utf8)!)
    exit(1)
}

_ = NSApplication.shared
// WebKit snapshots at the screen's backing scale, so lay out in points that come out at `pixels` pixels.
let scale = NSScreen.main?.backingScaleFactor ?? 1
let points = CGFloat(pixels) / scale

final class Snapshotter: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = NSNumber(value: Double(points))
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                die("snapshot failed: \(String(describing: error))")
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard rep.pixelsWide == pixels, rep.pixelsHigh == pixels else {
                die("got \(rep.pixelsWide)x\(rep.pixelsHigh), expected \(pixels)x\(pixels)")
            }
            guard let png = rep.representation(using: .png, properties: [:]) else { die("PNG encoding failed") }
            do { try png.write(to: out) } catch { die("can't write \(out.path): \(error)") }
            exit(0)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        die("load failed: \(error)")
    }
}

guard let data = try? Data(contentsOf: svg) else { die("can't read \(svg.path)") }
let snapshotter = Snapshotter()
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: points, height: points))
webView.setValue(false, forKey: "drawsBackground")
webView.navigationDelegate = snapshotter
let html = """
    <html><body style="margin:0;background:transparent">\
    <img src="data:image/svg+xml;base64,\(data.base64EncodedString())" width="\(points)" height="\(points)" \
    style="display:block"></body></html>
    """
webView.loadHTMLString(html, baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { die("timed out rendering \(svg.path)") }
NSApplication.shared.run()
