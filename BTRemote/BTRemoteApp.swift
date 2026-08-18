import SwiftUI

#if os(macOS)
    enum TransportMode: String, CaseIterable, Codable {
        case classic
        case lowEnergy

        static let defaultMode: TransportMode = .lowEnergy
    }
#endif

@main
struct BTRemoteApp: App {
    #if os(iOS)
        @StateObject private var lowEnergy = HIDPeripheral()
        @StateObject private var central = HIDCentral()
        @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = true
    #else
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        @StateObject private var lowEnergy = HIDPeripheral()
        @StateObject private var central = HIDCentral()
        @StateObject private var classic = HIDClassicDevice()
        @StateObject private var clipboardSync = ClipboardSyncController()
        @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.defaultMode.rawValue
    #endif

    @StateObject private var deviceNames = DeviceNameStore()

    init() {
        UserDefaults.standard.register(defaults: [
            AppSettings.useServiceChangedKey: true,
            AppSettings.directInputIndicatorEnabledKey: true,
            AppSettings.macToWindowsModifierRemapKey: false,
            AppSettings.clipboardSyncEnabledKey: true,
            AppSettings.clipboardSyncImagesEnabledKey: true
        ])
    }

    var body: some Scene {
        #if os(macOS)
            WindowGroup(id: "main") { mainContent }
        #else
            WindowGroup { mainContent }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(central)
                .environmentObject(deviceNames)
                .onAppear {
                    central.start()
                    if autoAdvertise {
                        lowEnergy.start()
                    }
                }
        #else
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(central)
                .environmentObject(classic)
                .environmentObject(clipboardSync)
                .environmentObject(deviceNames)
                .environment(\.macTransport, currentMode)
                .onAppear { _onAppear() }
                .onChange(of: modeRaw) { _ in _modeChanged() }
        #endif
    }

    #if os(macOS)
        private var currentMode: TransportMode {
            TransportMode(rawValue: modeRaw) ?? .defaultMode
        }

        private func _onAppear() {
            clipboardSync.attach(peripheral: lowEnergy)
            switch currentMode {
            case .classic:
                classic.start()
            case .lowEnergy:
                lowEnergy.start()
                central.start()
            }
        }

        private func _modeChanged() {
            // tear down the previously-active backend to prevent race
            lowEnergy.stop()
            classic.stop()

            switch currentMode {
            case .classic:
                classic.start()
            case .lowEnergy:
                lowEnergy.start()
                central.start()
            }
        }
    #endif
}

#if os(macOS)
    private struct MacTransportKey: EnvironmentKey {
        static let defaultValue: TransportMode = .defaultMode
    }

    extension EnvironmentValues {
        var macTransport: TransportMode {
            get { self[MacTransportKey.self] }
            set { self[MacTransportKey.self] = newValue }
        }
    }

    /// Keeps the app resident once the main window is closed so the menu-bar item
    /// stays available, and tears the status item down on quit.
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            false
        }

        func applicationWillTerminate(_ notification: Notification) {
            StatusBarController.shared.shutdown()
            CaptureIndicatorController.shared.shutdown()
        }
    }
#endif
