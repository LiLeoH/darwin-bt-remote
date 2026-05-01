import SwiftUI

@main
struct BTRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ble = HIDPeripheral()
    @StateObject private var central = HIDCentral()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(central)
                .onAppear {
                    appDelegate.ble = ble
                    // Register connection events before publishing HID services.
                    central.start()
                }
        }
    }
}
