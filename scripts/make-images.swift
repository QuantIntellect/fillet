// Composes the README images from real screenshots and Apple's official MacBook Pro bezel.
//
//   swiftc -parse-as-library -O scripts/make-images.swift -o build/make-images
//   build/make-images <bezel.png> <before.png> <after.png> <settings.png>
//
// <bezel.png>     MacBook Pro 16-inch PNG from Apple Design Resources (Product Bezels). Not redistributed here.
// <before.png>    full-resolution screenshot of the display with Fillet off
// <after.png>     the same scene with Fillet on
// <settings.png>  screenshot of the Settings window (screencapture -l, with shadow)
import AppKit

@main
struct MakeImages {
    static func main() throws {
        let a = CommandLine.arguments
        guard a.count == 5 else {
            print("usage: make-images <bezel.png> <before.png> <after.png> <settings.png>")
            exit(2)
        }
        let bezel = try load(a[1]), settings = try load(a[4])
        let before = removeStatusDot(try load(a[2])), after = removeStatusDot(try load(a[3]))
        let cut = cutout(in: bezel)
        print("bezel \(bezel.width)x\(bezel.height), screen cut-out \(cut)")

        // Hero: the real "after" screen with the Settings window, inside the bezel.
        let hero = compose(bezel: bezel, screen: after, cut: cut, overlay: settings)
        try save(scaled(hero, width: 2000), "docs/images/hero.png")

        // Close-ups: bottom-left corner before / after, and the hardware top-left corner for comparison.
        let plainBefore = compose(bezel: bezel, screen: before, cut: cut, overlay: nil)
        let plainAfter = compose(bezel: bezel, screen: after, cut: cut, overlay: nil)
        let size = 420, pad = 90
        let bottomLeft = CGRect(x: Int(cut.minX) - pad, y: Int(cut.maxY) - size + pad, width: size, height: size)
        let topLeft = CGRect(x: Int(cut.minX) - pad, y: Int(cut.minY) - pad, width: size, height: size)
        let panels: [(CGImage, String, String)] = [
            (plainBefore.cropping(to: bottomLeft)!, "Before", "Square bottom corner"),
            (plainAfter.cropping(to: bottomLeft)!, "With Fillet", "Rounded bottom corner"),
            (plainAfter.cropping(to: topLeft)!, "Top corner", "As drawn in Apple's bezel"),
        ]
        try save(closeups(panels), "docs/images/corners.png")
        print("wrote docs/images/hero.png and docs/images/corners.png")
    }

    // MARK: - Helpers

    static func load(_ path: String) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw NSError(domain: "make-images", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read \(path)"]) }
        return img
    }

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// The transparent screen area of the bezel, in top-left-origin pixel coordinates.
    static func cutout(in bezel: CGImage) -> CGRect {
        let w = bezel.width, h = bezel.height
        let ctx = context(w, h)
        ctx.draw(bezel, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[y * ctx.bytesPerRow + x * 4 + 3] }
        let cy = h / 2, cx = w / 2
        var l = cx; while l > 0 && alpha(l - 1, cy) < 128 { l -= 1 }
        var r = cx; while r < w - 1 && alpha(r + 1, cy) < 128 { r += 1 }
        let qx = l + (r - l) / 6
        var t = cy; while t > 0 && alpha(qx, t - 1) < 128 { t -= 1 }
        var b = cy; while b < h - 1 && alpha(qx, b + 1) < 128 { b += 1 }
        return CGRect(x: l, y: t, width: r - l + 1, height: b - t + 1)
    }

    /// Screen (and optional centred overlay) under the bezel. Returns a top-left-origin image.
    static func compose(bezel: CGImage, screen: CGImage, cut: CGRect, overlay: CGImage?) -> CGImage {
        let w = bezel.width, h = bezel.height
        let ctx = context(w, h)
        let screenRect = CGRect(x: cut.minX, y: CGFloat(h) - cut.maxY, width: cut.width, height: cut.height)
        ctx.draw(screen, in: screenRect)
        if let overlay {
            let ow = CGFloat(overlay.width), oh = CGFloat(overlay.height)
            ctx.draw(overlay, in: CGRect(x: screenRect.midX - ow / 2, y: screenRect.midY - oh / 2 - 40, width: ow, height: oh))
        }
        ctx.draw(bezel, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// macOS draws a small privacy indicator in the top-right corner while the screen is being captured.
    /// Paint over it with the wallpaper just to its left.
    static func removeStatusDot(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let ctx = context(w, h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = ctx.bytesPerRow
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: row * h)
        var box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in 0..<min(80, h) {           // memory row 0 is the top of the image
            for x in max(0, w - 120)..<w {
                let i = y * row + x * 4
                if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) < 60 {
                    box = (min(box?.minX ?? x, x), max(box?.maxX ?? x, x), min(box?.minY ?? y, y), max(box?.maxY ?? y, y))
                }
            }
        }
        guard let b = box else { return image }
        let x0 = max(0, b.minX - 8), x1 = min(w - 1, b.maxX + 8), y0 = max(0, b.minY - 8), y1 = min(h - 1, b.maxY + 8)
        let shift = x1 - x0 + 12
        for y in y0...y1 {
            for x in x0...x1 where x - shift >= 0 {
                let dst = y * row + x * 4, src = y * row + (x - shift) * 4
                for c in 0..<4 { px[dst + c] = px[src + c] }
            }
        }
        print("patched status dot at x \(x0)...\(x1), y \(y0)...\(y1)")
        return ctx.makeImage()!
    }

    static func scaled(_ image: CGImage, width: Int) -> CGImage {
        let height = Int(Double(image.height) * Double(width) / Double(image.width))
        let ctx = context(width, height)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func closeups(_ panels: [(CGImage, String, String)]) -> CGImage {
        let tile = 480, gap = 48, margin = 40, captionHeight = 96
        let w = margin * 2 + panels.count * tile + (panels.count - 1) * gap
        let h = margin + tile + captionHeight
        let ctx = context(w, h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, panel) in panels.enumerated() {
            let x = CGFloat(margin + i * (tile + gap))
            let rect = CGRect(x: x, y: CGFloat(captionHeight), width: CGFloat(tile), height: CGFloat(tile))
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil))
            ctx.clip()
            ctx.interpolationQuality = .high
            ctx.draw(panel.0, in: rect)
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 28, cornerHeight: 28, transform: nil))
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.35))
            ctx.setLineWidth(1)
            ctx.strokePath()

            let center = NSMutableParagraphStyle()
            center.alignment = .center
            NSAttributedString(string: panel.1, attributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor(white: 0.45, alpha: 1),
                .paragraphStyle: center,
            ]).draw(in: CGRect(x: x, y: 44, width: CGFloat(tile), height: 40))
            NSAttributedString(string: panel.2, attributes: [
                .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor(white: 0.5, alpha: 1), .paragraphStyle: center,
            ]).draw(in: CGRect(x: x, y: 10, width: CGFloat(tile), height: 32))
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    static func save(_ image: CGImage, _ path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
