import SwiftUI

struct ContentView: View {
    @State private var tab = Tab.remote

    private enum Tab {
        case remote, keyboard, settings, setup
    }

    var body: some View {
        TabView(selection: $tab) {
            RemoteView(goToSetup: { tab = .setup })
                .tabItem { Label(L10n.Tab.remote, systemImage: "gamecontroller") }
                .tag(Tab.remote)
            KeyboardView(goToSetup: { tab = .setup })
                .tabItem { Label(L10n.Tab.keyboard, systemImage: "keyboard") }
                .tag(Tab.keyboard)
            SettingsView()
                .tabItem { Label(L10n.Tab.settings, systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(Tab.setup)
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
        #else
            ContentView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
