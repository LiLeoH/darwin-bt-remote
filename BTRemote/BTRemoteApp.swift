import SwiftUI

#if os(macOS)
    enum TransportMode: String, CaseIterable, Codable {
        case classic // classic
        case ble // low energy

        static let defaultMode: TransportMode = .ble
    }
#endif

@main
struct BTRemoteApp: App {
    #if os(iOS)
        @StateObject private var ble = HIDPeripheral()
        @StateObject private var central = HIDCentral()
        @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = true
    #else
        @StateObject private var ble = HIDPeripheral()
        @StateObject private var central = HIDCentral()
        @StateObject private var classic = HIDClassicDevice()
        @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.defaultMode.rawValue
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
                ContentView()
                    .environmentObject(ble)
                    .environmentObject(central)
                    .onAppear {
                        central.start()
                        if autoAdvertise { ble.start() }
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
            TransportMode(rawValue: modeRaw) ?? .defaultMode
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
        static let defaultValue: TransportMode = .defaultMode
    }

    extension EnvironmentValues {
        var macTransport: TransportMode {
            get { self[MacTransportKey.self] }
            set { self[MacTransportKey.self] = newValue }
        }
    }
#endif
