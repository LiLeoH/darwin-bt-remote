import SwiftUI

@main
struct BTRemoteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var ble = HIDPeripheral()
    @StateObject private var central = HIDCentral()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(central)
                .onAppear {
                    #if os(iOS)
                    appDelegate.ble = ble
                    #endif
                    // register connection events before publishing HID services
                    central.start()
                }
        }
    }
}
