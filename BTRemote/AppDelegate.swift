#if os(iOS)
import os
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var ble: HIDPeripheral?
    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let restored = launchOptions?[.bluetoothPeripherals] {
            log.info("launched with bluetooth-peripheral restoration payload: \(String(describing: restored), privacy: .public)")
            ble?.adoptRestoredLaunchOptions(restored)
        }
        return true
    }
}
#endif
