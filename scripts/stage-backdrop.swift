// Covers the whole main display (menu bar and Dock included) with an image, for clean README screenshots.
//
//   swiftc -O scripts/stage-backdrop.swift -o build/stage-backdrop
//   build/stage-backdrop design/wallpaper/wallpaper.png 30 build/expected.png
//   (image, seconds to stay up, optional path to write exactly what is shown, for checking captures)
import AppKit

let args = CommandLine.arguments
guard args.count >= 2, let image = NSImage(contentsOfFile: args[1]) else {
    print("usage: stage-backdrop <image> [seconds]")
    exit(2)
}
let seconds = args.count > 2 ? Double(args[2]) ?? 30 : 30

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.main!.frame
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .screenSaver
// Also show up in a full-screen app's Space, so the capture never contains whatever is open there.
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
window.isOpaque = true
window.hasShadow = false
window.ignoresMouseEvents = true
let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
view.image = image
view.imageScaling = .scaleAxesIndependently
window.contentView = view

// Aspect-fill: crop the image to the screen's aspect ratio.
let imageAspect = image.size.width / image.size.height, screenAspect = frame.width / frame.height
var crop = NSRect(origin: .zero, size: image.size)
if imageAspect > screenAspect {
    crop.size.width = image.size.height * screenAspect
    crop.origin.x = (image.size.width - crop.width) / 2
} else {
    crop.size.height = image.size.width / screenAspect
    crop.origin.y = (image.size.height - crop.height) / 2
}
view.image = NSImage(size: frame.size, flipped: false) { rect in
    image.draw(in: rect, from: crop, operation: .copy, fraction: 1)
    return true
}

if args.count > 3 {
    let scale = NSScreen.main!.backingScaleFactor
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frame.width * scale), pixelsHigh: Int(frame.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    view.image!.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[3]))
}

window.orderFrontRegardless()
print("READY")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()
