import SwiftUI

#if os(macOS)
enum TransportMode: String, CaseIterable, Codable {
    case classic // BR/EDR HID
    case ble     // HOGP over LE (iCloud)
}
#endif

@main
struct BTRemoteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ble = HIDPeripheral()
    @StateObject private var central = HIDCentral()
    #else
    @StateObject private var ble = HIDPeripheral()
    @StateObject private var central = HIDCentral()
    @StateObject private var classic = HIDClassicDevice()
    @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.classic.rawValue
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            ContentView()
                .environmentObject(ble)
                .environmentObject(central)
                .onAppear {
                    appDelegate.ble = ble
                    central.start()
                }
            #else
            ContentView()
                .environmentObject(ble)
                .environmentObject(central)
                .environmentObject(classic)
                .environment(\.macTransport, currentMode)
                .onAppear { _onAppear() }
                .onChange(of: modeRaw) { _ in _modeChanged() }
            #endif
        }
    }

    #if os(macOS)
    private var currentMode: TransportMode {
        TransportMode(rawValue: modeRaw) ?? .classic
    }

    private func _onAppear() {
        switch currentMode {
        case .classic:
            classic.start()
        case .ble:
            ble.start()
            central.start()
        }
    }

    private func _modeChanged() {
        // tear down the previously-active backend to prevent race
        ble.stop()
        classic.stop()

        switch currentMode {
        case .classic:
            classic.start()
        case .ble:
            ble.start()
            central.start()
        }
    }
    #endif
}

#if os(macOS)
private struct MacTransportKey: EnvironmentKey {
    static let defaultValue: TransportMode = .classic
}

extension EnvironmentValues {
    var macTransport: TransportMode {
        get { self[MacTransportKey.self] }
        set { self[MacTransportKey.self] = newValue }
    }
}
#endif
