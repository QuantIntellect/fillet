import AppKit

enum Corner: CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight
}

/// Draws the black corner mask, mirrored for whichever corner the window sits in.
final class CornerView: NSView {
    let corner: Corner
    var path: CGPath { didSet { needsDisplay = true } }

    init(corner: Corner, path: CGPath, size: CGFloat) {
        self.corner = corner
        self.path = path
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        switch corner {   // the mask is drawn for the bottom-left corner; mirror it for the others
        case .bottomLeft: break
        case .bottomRight: ctx.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        case .topLeft: ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))
        case .topRight: ctx.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        }
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
    }
}

/// Owns the private space and the corner windows on every display.
final class Overlay {
    private struct Item {
        let window: NSWindow
        let view: CornerView
        let screen: NSScreen
    }

    private let cid = _CGSDefaultConnection()
    private var space: CGSSpaceID = 0
    private var items: [Item] = []
    private var config: OverlayConfig?
    private var layout = ""

    /// Applies new settings with the least disruption: a radius or smoothing change only resizes and
    /// redraws the existing windows; the windows and space are rebuilt only when the displays or the
    /// chosen corners change.
    func apply(_ new: OverlayConfig) {
        defer { config = new }
        guard new.enabled else {
            tearDown()
            return
        }
        let newLayout = Self.layoutKey(for: new)
        if newLayout != layout || items.isEmpty {
            rebuild(new, layout: newLayout)
        } else if new != config {
            reshape(new)
        }
    }

    /// Called when displays change. The system also sends this when the menu bar hides for a
    /// full-screen app; the layout key makes that a no-op, so the corners don't blink.
    func screensChanged() {
        if let config { apply(config) }
    }

    /// After sleep, make sure the space is still shown and the windows are still in it.
    func reassert() {
        guard space != 0, !items.isEmpty else { return }
        CGSShowSpaces(cid, [NSNumber(value: space)] as CFArray)
        CGSAddWindowsToSpaces(cid, ids(items), [NSNumber(value: space)] as CFArray)
        items.forEach { $0.window.orderFrontRegardless() }
    }

    func tearDown() {
        remove(space: space, items: items)
        space = 0
        items = []
        layout = ""
    }

    // MARK: - Private

    private static func placements(for config: OverlayConfig) -> [(Corner, NSScreen)] {
        NSScreen.screens.flatMap { screen -> [(Corner, NSScreen)] in
            var corners: [Corner] = []
            if config.bottomCorners { corners += [.bottomLeft, .bottomRight] }
            // Displays with a camera notch are physically rounded at the top already.
            if config.topCorners && screen.safeAreaInsets.top == 0 { corners += [.topLeft, .topRight] }
            return corners.map { ($0, screen) }
        }
    }

    private static func layoutKey(for config: OverlayConfig) -> String {
        let screens = NSScreen.screens.map { "\($0.frame)@\($0.backingScaleFactor)n\($0.safeAreaInsets.top > 0)" }
        return screens.joined(separator: "|") + "|b\(config.bottomCorners)t\(config.topCorners)"
    }

    private static func frame(for corner: Corner, in screen: NSRect, side: CGFloat) -> NSRect {
        switch corner {
        case .bottomLeft: return NSRect(x: screen.minX, y: screen.minY, width: side, height: side)
        case .bottomRight: return NSRect(x: screen.maxX - side, y: screen.minY, width: side, height: side)
        case .topLeft: return NSRect(x: screen.minX, y: screen.maxY - side, width: side, height: side)
        case .topRight: return NSRect(x: screen.maxX - side, y: screen.maxY - side, width: side, height: side)
        }
    }

    /// Builds the new space and windows before removing the old ones, so there is never a gap.
    private func rebuild(_ config: OverlayConfig, layout newLayout: String) {
        let oldSpace = space, oldItems = items
        space = 0
        items = []
        layout = newLayout

        let placements = Self.placements(for: config)
        if !placements.isEmpty {
            space = CGSSpaceCreate(cid, 1, nil)
            if space != 0 {
                CGSSpaceSetAbsoluteLevel(cid, space, 2_147_483_647)
                CGSShowSpaces(cid, [NSNumber(value: space)] as CFArray)
            } else {
                NSLog("Fillet: could not create a space; falling back to ordinary all-Spaces windows")
            }
            items = placements.map { corner, screen in
                let shape = config.shape(on: screen)
                let side = ceil(CornerShape.extent(radius: shape.radius, smoothing: shape.smoothing))
                return makeItem(corner: corner, frame: Self.frame(for: corner, in: screen.frame, side: side), screen: screen,
                                path: CornerShape.mask(radius: shape.radius, smoothing: shape.smoothing))
            }
            if space != 0 { CGSAddWindowsToSpaces(cid, ids(items), [NSNumber(value: space)] as CFArray) }
        }

        remove(space: oldSpace, items: oldItems)
    }

    private func reshape(_ config: OverlayConfig) {
        for item in items {
            let shape = config.shape(on: item.screen)
            let side = ceil(CornerShape.extent(radius: shape.radius, smoothing: shape.smoothing))
            item.window.setFrame(Self.frame(for: item.view.corner, in: item.screen.frame, side: side), display: false)
            item.view.path = CornerShape.mask(radius: shape.radius, smoothing: shape.smoothing)
        }
    }

    private func makeItem(corner: Corner, frame: NSRect, screen: NSScreen, path: CGPath) -> Item {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        // Above everything an app can put on screen, the screen saver included. The private space keeps the
        // corners in place during animations; the level decides what they're drawn over.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = CornerView(corner: corner, path: path, size: frame.width)
        window.contentView = view
        window.orderFrontRegardless()
        return Item(window: window, view: view, screen: screen)
    }

    private func remove(space: CGSSpaceID, items: [Item]) {
        if space != 0 {
            if !items.isEmpty { CGSRemoveWindowsFromSpaces(cid, ids(items), [NSNumber(value: space)] as CFArray) }
            CGSHideSpaces(cid, [NSNumber(value: space)] as CFArray)
            CGSSpaceDestroy(cid, space)
        }
        items.forEach { $0.window.orderOut(nil) }
    }

    private func ids(_ items: [Item]) -> CFArray {
        items.map { NSNumber(value: $0.window.windowNumber) } as CFArray
    }
}
