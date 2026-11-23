// Builds the app icon from the artwork in design/icon/icon-a.png (made with Codex image generation):
// the artwork is fitted to the exact macOS icon squircle (824 px on the 1024 grid) over an opaque base,
// given the standard drop shadow, and written to Resources/AppIcon.icns and docs/images/icon.png.
//
//   swiftc -parse-as-library -O scripts/make-icon.swift Sources/Fillet/CornerShape.swift -o build/make-icon
//   build/make-icon [design/icon/icon-a.png]
import AppKit

@main
struct MakeIcon {
    /// The artwork's squircle body, in its own 1024 px canvas (top-left origin), measured from its alpha channel.
    static let artBody = CGRect(x: 99.5, y: 104, width: 816, height: 816)

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/icon/icon-a.png"
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
              let art = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { fatalError("cannot read \(source)") }

        let iconset = root.appendingPathComponent("build/AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try png(render(art, pixels: points * scale)).write(to: iconset.appendingPathComponent(name))
            }
        }
        try png(render(art, pixels: 512)).write(to: root.appendingPathComponent("docs/images/icon.png"))

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
        try iconutil.run()
        iconutil.waitUntilExit()
        print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and docs/images/icon.png" : "iconutil failed")
    }

    static func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

    static func render(_ art: CGImage, pixels: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

        let body = CGRect(x: 100, y: 100, width: 824, height: 824)   // y-up; symmetric, so same as top-left
        let shape = CornerShape.roundedRect(body, radius: 185, smoothing: 0.6)

        // Drop shadow and opaque base.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.32))
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.165, blue: 0.19, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Artwork, scaled so its body fills the squircle exactly, clipped to it.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let s = body.width / artBody.width
        let artH = CGFloat(art.height), artW = CGFloat(art.width)
        let originX = body.minX - artBody.minX * s
        let originY = body.minY - (artH - artBody.maxY) * s     // artBody is top-left based; CG is y-up
        ctx.draw(art, in: CGRect(x: originX, y: originY, width: artW * s, height: artH * s))
        ctx.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
