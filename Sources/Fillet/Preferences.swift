import AppKit

/// UserDefaults keys and defaults. Everything can also be changed from Terminal and applies immediately, e.g.
/// `defaults write com.quantintellect.fillet matchTopCorners -bool false`
/// `defaults write com.quantintellect.fillet radius -float 30`
enum Pref {
    static let enabled = "enabled"
    static let matchTopCorners = "matchTopCorners"
    static let radius = "radius"
    static let smoothing = "smoothing"
    static let bottomCorners = "bottomCorners"
    static let topCorners = "topCorners"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let hasLaunchedBefore = "hasLaunchedBefore"

    static let radiusRange: ClosedRange<Double> = 4...60

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabled: true,
            matchTopCorners: true,
            radius: 20.0,
            smoothing: 0.9,
            bottomCorners: true,
            topCorners: false,
            showMenuBarIcon: true,
        ])
    }
}

/// The MacBook Pro's rounded top screen corners as drawn in the screen cut-out of Apple's MacBook Pro
/// product bezel artwork (Apple Design Resources): 16-inch 39 px radius / 0.9 smoothing, 14-inch 38.5 px / 0.8,
/// in native panel pixels.
enum TopCorners {
    static let radiusInPixels: CGFloat = 39
    static let smoothing: CGFloat = 0.9

    /// The radius in points at a MacBook Pro's default scaling (2 native pixels per point).
    static let defaultRadiusInPoints: CGFloat = 19.5

    /// The matching radius in points for a screen. On the built-in display it follows the scaling
    /// ("Looks like …") so the curve keeps its physical size; other displays get the default size in points.
    static func radius(on screen: NSScreen) -> CGFloat {
        guard let display = displayID(screen), CGDisplayIsBuiltin(display) != 0 else { return defaultRadiusInPoints }
        return radiusInPixels / nativePixelsPerPoint(screen)
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Native panel pixels per point: 2 at the default scaling of a MacBook Pro, less at "More Space".
    static func nativePixelsPerPoint(_ screen: NSScreen) -> CGFloat {
        guard let display = displayID(screen), screen.frame.width > 0 else { return screen.backingScaleFactor }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
        let nativeFlag: UInt32 = 0x0200_0000   // kDisplayModeNativeFlag
        let native = modes.first { $0.ioFlags & nativeFlag != 0 }?.pixelWidth ?? modes.map(\.pixelWidth).max()
        guard let native, native > 0 else { return screen.backingScaleFactor }
        return CGFloat(native) / screen.frame.width
    }
}

/// A snapshot of the settings that affect the overlay.
struct OverlayConfig: Equatable {
    var enabled: Bool
    var matchTopCorners: Bool
    var radius: CGFloat
    var smoothing: CGFloat
    var bottomCorners: Bool
    var topCorners: Bool

    static var current: OverlayConfig {
        let d = UserDefaults.standard
        return OverlayConfig(
            enabled: d.bool(forKey: Pref.enabled),
            matchTopCorners: d.bool(forKey: Pref.matchTopCorners),
            radius: CGFloat(min(max(d.double(forKey: Pref.radius), Pref.radiusRange.lowerBound), Pref.radiusRange.upperBound)),
            smoothing: CGFloat(min(max(d.double(forKey: Pref.smoothing), 0), 1)),
            bottomCorners: d.bool(forKey: Pref.bottomCorners),
            topCorners: d.bool(forKey: Pref.topCorners)
        )
    }

    /// The radius and smoothing to use on a given screen.
    func shape(on screen: NSScreen) -> (radius: CGFloat, smoothing: CGFloat) {
        matchTopCorners ? (TopCorners.radius(on: screen), TopCorners.smoothing) : (radius, smoothing)
    }
}
