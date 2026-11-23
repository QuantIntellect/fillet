import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = Overlay()
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var pendingDefaultsUpdate = false
    private var pendingScreensUpdate: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        overlay.apply(.current)
        updateStatusItem()

        // KVO also reports changes made from Terminal with `defaults write`, so those apply live too.
        for key in Self.observedKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)

        if !UserDefaults.standard.bool(forKey: Pref.hasLaunchedBefore) {
            UserDefaults.standard.set(true, forKey: Pref.hasLaunchedBefore)
            showSettings(nil)
        }
    }

    /// Opening Fillet again (e.g. from Applications) shows Settings, which matters when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.tearDown()
    }

    // MARK: - Reacting to changes

    private static let observedKeys = [Pref.enabled, Pref.matchTopCorners, Pref.radius, Pref.smoothing,
                                       Pref.bottomCorners, Pref.topCorners, Pref.showMenuBarIcon]

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread { defaultsChanged() } else { DispatchQueue.main.async { self.defaultsChanged() } }
    }

    private func defaultsChanged() {
        // Coalesce bursts (e.g. dragging a slider) into one update per run-loop pass.
        guard !pendingDefaultsUpdate else { return }
        pendingDefaultsUpdate = true
        DispatchQueue.main.async { [self] in
            pendingDefaultsUpdate = false
            overlay.apply(.current)
            updateStatusItem()
        }
    }

    @objc private func screensChanged() {
        pendingScreensUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.overlay.screensChanged() }
        pendingScreensUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.overlay.screensChanged()
            self?.overlay.reassert()
        }
    }

    // MARK: - Menu bar

    private func updateStatusItem() {
        let show = UserDefaults.standard.bool(forKey: Pref.showMenuBarIcon)
        if show, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.menuBarImage()
            item.button?.toolTip = "Fillet"
            item.menu = makeStatusMenu()
            statusItem = item
        } else if !show, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            toggleMenuItem = nil
        }
        toggleMenuItem?.state = UserDefaults.standard.bool(forKey: Pref.enabled) ? .on : .off
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Round Corners", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.target = self
        toggleMenuItem = toggle
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings(_:)), key: ","))
        menu.addItem(item("About Fillet", #selector(showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Fillet", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        return menu
    }

    /// Hidden for an agent app, but gives Settings and About the usual shortcuts (⌘, ⌘W ⌘Q).
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("About Fillet", #selector(showAbout(_:))))
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Fillet", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private static func menuBarImage() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "rectangle.roundedbottom", accessibilityDescription: "Fillet") {
            return symbol
        }
        // Fallback: a rectangle outline with rounded bottom corners.
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { rect in
            let r = rect.insetBy(dx: 1.5, dy: 2)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: r.minX, y: r.maxY))
            path.line(to: NSPoint(x: r.maxX, y: r.maxY))
            path.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.minX, y: r.minY), radius: 3.5)
            path.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX, y: r.maxY), radius: 3.5)
            path.close()
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: Pref.enabled), forKey: Pref.enabled)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Fillet"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSMutableAttributedString(
            string: "Rounded bottom corners for your Mac that stay put through Space switches and full screen.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: paragraph])
        credits.append(NSAttributedString(
            string: "github.com/QuantIntellect/fillet",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://github.com/QuantIntellect/fillet")!,
                         .paragraphStyle: paragraph]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
