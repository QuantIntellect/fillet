import CoreGraphics
import Foundation

/// Continuous ("squircle") corners, built with the corner-smoothing construction from Figma's
/// "Desperately seeking squircles" article, as implemented in figma-squircle (MIT, © 2021 Tien Pham):
/// a Bézier curve, a circular arc, then a mirrored Bézier curve.
/// `smoothing` 0 gives a plain circular arc; 0.6 is close to Apple's continuous corners.
enum CornerShape {

    /// How far along each edge a corner of this radius and smoothing reaches.
    static func extent(radius: CGFloat, smoothing: CGFloat) -> CGFloat {
        (1 + smoothing) * radius
    }

    /// The area between a bottom-left screen corner (at the origin, y up) and the corner curve.
    /// Filling it black rounds that corner of the screen.
    static func mask(radius: CGFloat, smoothing: CGFloat) -> CGPath {
        let p = extent(radius: radius, smoothing: smoothing)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: p, y: 0))
        addCorner(to: path, at: .zero, along: CGVector(dx: 1, dy: 0), then: CGVector(dx: 0, dy: 1),
                  radius: radius, smoothing: smoothing)
        path.closeSubpath()
        return path
    }

    /// Just the curve of a bottom-left corner (y up), from (extent, 0) to (0, extent).
    static func curve(radius: CGFloat, smoothing: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: extent(radius: radius, smoothing: smoothing), y: 0))
        addCorner(to: path, at: .zero, along: CGVector(dx: 1, dy: 0), then: CGVector(dx: 0, dy: 1),
                  radius: radius, smoothing: smoothing)
        return path
    }

    /// A rectangle (y up) with continuous rounded corners.
    static func roundedRect(_ r: CGRect, radius: CGFloat, smoothing: CGFloat) -> CGPath {
        roundedRect(r, bottom: radius, top: radius, smoothing: smoothing)
    }

    /// A rectangle (y up) whose bottom and top corners can have different radii.
    static func roundedRect(_ r: CGRect, bottom: CGFloat, top: CGFloat, smoothing: CGFloat) -> CGPath {
        let limit = min(r.width, r.height) / 2 / (1 + smoothing)
        let bottom = min(bottom, limit), top = min(top, limit)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        let corners: [(CGPoint, CGVector, CGVector, CGFloat)] = [
            (CGPoint(x: r.maxX, y: r.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1), bottom),
            (CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0), top),
            (CGPoint(x: r.minX, y: r.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1), top),
            (CGPoint(x: r.minX, y: r.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0), bottom),
        ]
        for (corner, incoming, outgoing, radius) in corners {
            let p = extent(radius: radius, smoothing: smoothing)
            path.addLine(to: CGPoint(x: corner.x + incoming.dx * p, y: corner.y + incoming.dy * p))
            addCorner(to: path, at: corner, along: incoming, then: outgoing, radius: radius, smoothing: smoothing)
        }
        path.closeSubpath()
        return path
    }

    /// Appends the curve from `corner + p·u` to `corner + p·v`, where `u` points from the corner along the
    /// edge the path arrives on and `v` along the edge it leaves on. The path must already be at `corner + p·u`.
    private static func addCorner(to path: CGMutablePath, at corner: CGPoint, along u: CGVector, then v: CGVector,
                                  radius r: CGFloat, smoothing xi: CGFloat) {
        func rad(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }
        let p = extent(radius: r, smoothing: xi)
        let arcMeasure = 90 * (1 - xi)
        let arcSection = sin(rad(arcMeasure / 2)) * r * 2.squareRoot()
        let alpha = (90 - arcMeasure) / 2
        let p3ToP4 = r * tan(rad(alpha / 2))
        let beta = 45 * xi
        let c = p3ToP4 * cos(rad(beta))
        let d = c * tan(rad(beta))
        let b = (p - arcSection - c - d) / 3
        let a = 2 * b

        // Local coordinates: x along u, y along v, corner at the origin.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: corner.x + u.dx * x + v.dx * y, y: corner.y + u.dy * x + v.dy * y)
        }
        path.addCurve(to: pt(p - a - b - c, d), control1: pt(p - a, 0), control2: pt(p - a - b, 0))

        // Circular arc around (r, r), sampled finely enough to be smooth at any display scale.
        let start = atan2(d - r, (p - a - b - c) - r)
        var end = atan2((p - a - b - c) - r, d - r)
        if end > start { end -= 2 * .pi }   // sweep the short way round (matters when smoothing is 0)
        let steps = 48
        for i in 1...steps {
            let t = start + (end - start) * CGFloat(i) / CGFloat(steps)
            path.addLine(to: pt(r + r * cos(t), r + r * sin(t)))
        }

        path.addCurve(to: pt(0, p), control1: pt(0, p - a - b), control2: pt(0, p - a))
    }
}
