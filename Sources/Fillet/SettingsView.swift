import ServiceManagement
import SwiftUI

/// Wraps SMAppService so the toggle reflects the real login-item state.
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Fillet: login item change failed: \(error.localizedDescription)")
        }
        refresh()
    }

    func refresh() { status = SMAppService.mainApp.status }
}

struct SettingsView: View {
    @AppStorage(Pref.enabled) private var enabled = true
    @AppStorage(Pref.matchTopCorners) private var matchTopCorners = true
    @AppStorage(Pref.radius) private var radius = 20.0
    @AppStorage(Pref.smoothing) private var smoothing = 0.9
    @AppStorage(Pref.bottomCorners) private var bottomCorners = true
    @AppStorage(Pref.topCorners) private var topCorners = false
    @AppStorage(Pref.showMenuBarIcon) private var showMenuBarIcon = true
    @StateObject private var loginItem = LoginItem()

    /// What the overlay draws on the main screen right now.
    private var effective: (radius: CGFloat, smoothing: CGFloat) {
        if matchTopCorners, let screen = NSScreen.main { return (TopCorners.radius(on: screen), TopCorners.smoothing) }
        return (CGFloat(radius), CGFloat(smoothing))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fillet").font(.title2.weight(.semibold))
                        Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Round corners", isOn: $enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Section {
                CornerPreview(radius: effective.radius, smoothing: effective.smoothing)
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Toggle(isOn: $matchTopCorners) {
                    Text("Match the screen's top corners")
                    Text("The MacBook Pro's top corners as drawn in Apple's product bezel artwork: 39 px with a continuous curve.")
                }
                LabeledContent("Radius") {
                    HStack {
                        Slider(value: Binding(get: { Double(effective.radius) }, set: { radius = ($0 * 2).rounded() / 2 }),
                               in: Pref.radiusRange)
                        Text(String(format: "%g pt", (Double(effective.radius) * 2).rounded() / 2))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(matchTopCorners)
                LabeledContent("Smoothing") {
                    Slider(value: Binding(get: { Double(effective.smoothing) }, set: { smoothing = $0 }), in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Circular").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Continuous").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(matchTopCorners)
            } header: {
                Text("Shape")
            }
            .disabled(!enabled)

            Section {
                Toggle("Bottom corners", isOn: $bottomCorners)
                Toggle("Top corners", isOn: $topCorners)
            } header: {
                Text("Corners")
            } footer: {
                Text("Top corners are skipped on displays with a camera notch, which are already rounded at the top.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!enabled)

            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if loginItem.status == .requiresApproval {
                    Button("Allow in Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
            } header: {
                Text("General")
            } footer: {
                Text("With the menu bar icon hidden, open Fillet again from Applications to get back here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                HStack {
                    Link("github.com/QuantIntellect/fillet", destination: URL(string: "https://github.com/QuantIntellect/fillet")!)
                    Spacer()
                    Button("Quit Fillet") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
    }
}

/// The bottom edge of a "screen" at actual size, with the current corner shape applied.
struct CornerPreview: View {
    var radius: CGFloat
    var smoothing: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.16, green: 0.36, blue: 0.95),
                                  Color(red: 0.55, green: 0.33, blue: 0.93),
                                  Color(red: 0.98, green: 0.55, blue: 0.38)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
            let mask = Path(CornerShape.mask(radius: radius, smoothing: smoothing))
            let h = size.height, w = size.width
            ctx.fill(mask.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)), with: .color(.black))
            ctx.fill(mask.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)), with: .color(.black))
            ctx.draw(Text("Actual size").font(.caption2.weight(.medium)).foregroundColor(.white.opacity(0.85)),
                     at: CGPoint(x: w / 2, y: 14))
        }
        .accessibilityLabel("Preview of the corner shape at actual size")
    }
}
