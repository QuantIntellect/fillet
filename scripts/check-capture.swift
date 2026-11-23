// Fails unless a screenshot matches the staged backdrop, so a capture that shows anything else on screen
// (other apps, notifications) is never used. Ignores the corners and the top-right status area.
//
//   swiftc -O scripts/check-capture.swift -o build/check-capture
//   build/check-capture build/expected.png build/after.png
import AppKit

func pixels(_ path: String) -> (UnsafeMutablePointer<UInt8>, Int, Int) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(path)"); exit(2) }
    let w = image.width, h = image.height
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
    let ctx = CGContext(data: buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buffer, w, h)
}

let (a, w, h) = pixels(CommandLine.arguments[1])
let (b, w2, h2) = pixels(CommandLine.arguments[2])
guard w == w2, h == h2 else { print("FAIL: size \(w)x\(h) vs \(w2)x\(h2)"); exit(1) }
var worst = 0.0, total = 0.0, count = 0
for gy in 0..<40 {
    for gx in 0..<60 {
        let x = 160 + gx * (w - 320) / 59, y = 160 + gy * (h - 320) / 39
        var d = 0.0
        for c in 0..<3 { d += abs(Double(a[(y * w + x) * 4 + c]) - Double(b[(y * w + x) * 4 + c])) }
        worst = max(worst, d); total += d; count += 1
    }
}
let mean = total / Double(count)
print(String(format: "mean difference %.1f, worst %.0f", mean, worst))
if mean > 12 || worst > 120 { print("FAIL: the capture doesn't match the backdrop"); exit(1) }
print("OK")
