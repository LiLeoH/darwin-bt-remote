import SwiftUI

struct ContentView: View {
    @State private var tab = Tab.setup

    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @Environment(\.macTransport) private var macTransport
    #endif

    private enum Tab {
        case setup, remote, keyboard, settings
    }

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: macTransport == .classic)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(Tab.setup)
            KeyboardView(goToSetup: { tab = .setup })
                .tabItem { Label(L10n.Tab.keyboard, systemImage: "keyboard") }
                .tag(Tab.keyboard)
            RemoteView(goToSetup: { tab = .setup })
                .tabItem { Label(L10n.Tab.remote, systemImage: "gamecontroller") }
                .tag(Tab.remote)
            SettingsView()
                .tabItem { Label(L10n.Tab.settings, systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
        }
        .onChange(of: hid.isConnected) { connected in
            if connected, tab == .setup { tab = .keyboard }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 640, idealHeight: 800)
        #endif
    }
}

#if DEBUG
    #Preview {
        #if os(iOS)
            ContentView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(DeviceNameStore())
        #else
            ContentView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(DeviceNameStore())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
