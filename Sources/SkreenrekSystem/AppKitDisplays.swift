import AppKit
import SkreenrekCore

/// The displays from `NSScreen.screens`, in top-left global pt.
public enum AppKitDisplays {
    @MainActor
    public static func current() -> [DisplayInfo] {
        let screens = NSScreen.screens
        // The primary display is the one whose AppKit frame starts at 0, 0 (the first screen).
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        let geometry = ScreenGeometry(primaryHeight: Double(primary?.frame.height ?? 0))
        return screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return DisplayInfo(
                id: number?.uint32Value ?? 0, name: screen.localizedName, scale: Double(screen.backingScaleFactor),
                frame: geometry.topLeft(fromAppKit: screen.frame),
                visibleFrame: geometry.topLeft(fromAppKit: screen.visibleFrame))
        }
    }
}
