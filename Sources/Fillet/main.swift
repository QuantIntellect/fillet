import AppKit
import ServiceManagement

Pref.registerDefaults()

let arguments = CommandLine.arguments

if arguments.contains("--version") {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    exit(0)
}

// `Fillet --login-item on|off|status` — scriptable alternative to the Settings toggle.
if let i = arguments.firstIndex(of: "--login-item"), i + 1 < arguments.count {
    do {
        switch arguments[i + 1] {
        case "on": try SMAppService.mainApp.register()
        case "off": try SMAppService.mainApp.unregister()
        default: break
        }
        let names: [SMAppService.Status: String] = [.enabled: "enabled", .notRegistered: "not registered",
                                                    .requiresApproval: "requires approval", .notFound: "not found"]
        print("login item:", names[SMAppService.mainApp.status] ?? "unknown")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// One instance only (relaunching through Finder or `open` reaches the running copy instead).
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

// Clean up the private space on `kill` / `pkill` too, not only on Quit.
signal(SIGTERM, SIG_IGN)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    delegate.overlay.tearDown()
    exit(0)
}
sigtermSource.resume()

app.run()
