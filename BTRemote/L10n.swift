import Foundation
import SwiftUI

enum L10n {
    enum App {
        static var title: LocalizedStringKey {
            "app.title"
        }
    }

    enum Section {
        static var lastError: LocalizedStringKey {
            "section.last_error"
        }

        static var status: LocalizedStringKey {
            "section.status"
        }

        static var devices: LocalizedStringKey {
            "section.devices"
        }

        static var keyboard: LocalizedStringKey {
            "section.keyboard"
        }

        static var mouse: LocalizedStringKey {
            "section.mouse"
        }

        static var media: LocalizedStringKey {
            "section.media"
        }

        static var battery: LocalizedStringKey {
            "section.battery"
        }
    }

    enum Status {
        static var bluetooth: LocalizedStringKey {
            "status.bluetooth"
        }

        static var advertising: LocalizedStringKey {
            "status.advertising"
        }

        static var hidService: LocalizedStringKey {
            "status.hid_service"
        }

        static var hidServiceAdded: LocalizedStringKey {
            "status.hid_service.added"
        }

        static var subscribedCentrals: LocalizedStringKey {
            "status.subscribed_centrals"
        }

        static var connectedPeripherals: LocalizedStringKey {
            "status.connected_peripherals"
        }

        static var hostLEDs: LocalizedStringKey {
            "status.host_leds"
        }

        static var central: LocalizedStringKey {
            "status.central"
        }
    }

    enum Value {
        static var yes: LocalizedStringKey {
            "value.yes"
        }

        static var no: LocalizedStringKey {
            "value.no"
        }

        static var none: LocalizedStringKey {
            "value.none"
        }

        static var noneString: String {
            String(localized: "value.none")
        }
    }

    enum Action {
        static var startAdvertising: LocalizedStringKey {
            "action.start_advertising"
        }

        static var stopAdvertising: LocalizedStringKey {
            "action.stop_advertising"
        }

        static var scanNearbyDevices: LocalizedStringKey {
            "action.scan_nearby_devices"
        }

        static var stopScanning: LocalizedStringKey {
            "action.stop_scanning"
        }
    }

    enum Device {
        static var emptyState: LocalizedStringKey {
            "device.empty_state"
        }

        static var unknownName: String {
            String(localized: "device.unknown_name")
        }

        static func rssi(_ value: Int) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.rssi_format"),
                value
            )
        }

        static func connectAccessibilityLabel(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.connect_accessibility_label"),
                name
            )
        }

        static func disconnectAccessibilityLabel(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.disconnect_accessibility_label"),
                name
            )
        }
    }

    enum Keyboard {
        static var typeHello: LocalizedStringKey {
            "keyboard.type_hello"
        }

        static var pressReturn: LocalizedStringKey {
            "keyboard.press_return"
        }

        static var pressEscape: LocalizedStringKey {
            "keyboard.press_escape"
        }
    }

    enum DirectInput {
        static var section: LocalizedStringKey {
            "section.direct_input"
        }

        static var toggle: LocalizedStringKey {
            "direct_input.toggle"
        }

        static var releaseHint: LocalizedStringKey {
            "direct_input.release_hint"
        }

        static var captureFailedString: String {
            String(localized: "direct_input.capture_failed")
        }
    }

    enum Mouse {
        static var dragToMovePointer: LocalizedStringKey {
            "mouse.drag_to_move_pointer"
        }

        static var leftButton: LocalizedStringKey {
            "mouse.button.left"
        }

        static var middleButton: LocalizedStringKey {
            "mouse.button.middle"
        }

        static var rightButton: LocalizedStringKey {
            "mouse.button.right"
        }

        static var wheelUp: LocalizedStringKey {
            "mouse.wheel.up"
        }

        static var wheelDown: LocalizedStringKey {
            "mouse.wheel.down"
        }
    }

    enum Media {
        static var previousTrack: LocalizedStringKey {
            "media.previous_track"
        }

        static var playPause: LocalizedStringKey {
            "media.play_pause"
        }

        static var nextTrack: LocalizedStringKey {
            "media.next_track"
        }

        static var mute: LocalizedStringKey {
            "media.mute"
        }

        static var volumeDown: LocalizedStringKey {
            "media.volume_down"
        }

        static var volumeUp: LocalizedStringKey {
            "media.volume_up"
        }
    }

    enum Battery {
        static var level: LocalizedStringKey {
            "battery.level"
        }
    }

    enum BluetoothState {
        static var unknown: LocalizedStringKey {
            "bluetooth_state.unknown"
        }

        static var resetting: LocalizedStringKey {
            "bluetooth_state.resetting"
        }

        static var unsupported: LocalizedStringKey {
            "bluetooth_state.unsupported"
        }

        static var unauthorized: LocalizedStringKey {
            "bluetooth_state.unauthorized"
        }

        static var poweredOff: LocalizedStringKey {
            "bluetooth_state.powered_off"
        }

        static var poweredOn: LocalizedStringKey {
            "bluetooth_state.powered_on"
        }

        static var unavailable: LocalizedStringKey {
            "bluetooth_state.unavailable"
        }
    }

    enum KeyboardLED {
        static var numLock: String {
            String(localized: "keyboard_led.num_lock")
        }

        static var capsLock: String {
            String(localized: "keyboard_led.caps_lock")
        }

        static var scrollLock: String {
            String(localized: "keyboard_led.scroll_lock")
        }
    }

    enum Bluetooth {
        static var advertisedName: String {
            String(localized: "bluetooth.advertised_name")
        }

        static var serviceDescription: String {
            String(localized: "bluetooth.service_description")
        }

        static var providerName: String {
            String(localized: "bluetooth.provider_name")
        }
    }

    enum ErrorMessage {
        static func peripheralNotRetained(_ identifier: UUID) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.peripheral_not_retained"),
                identifier.uuidString
            )
        }

        static func failedToConnect(_ reason: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.failed_to_connect"),
                reason
            )
        }

        static var sdpPublishFailed: String {
            String(localized: "error.sdp_publish_failed")
        }

        static var classicBondRequired: String {
            String(localized: "error.classic_bond_required")
        }

        static func deviceNotPaired(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.device_not_paired"),
                name
            )
        }

        static func openConnectionFailed(_ code: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.open_connection_failed"),
                code
            )
        }

        static func openL2CAPFailed(_ psm: UInt16, _ code: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.open_l2cap_failed"),
                psm,
                code
            )
        }

        static func writeFailed(_ code: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "error.write_failed"),
                code
            )
        }
    }

    enum TransportMode {
        static var section: LocalizedStringKey { "section.transport_mode" }
        static var label: LocalizedStringKey { "transport_mode.label" }
        static var classic: LocalizedStringKey { "transport_mode.classic" }
        static var ble: LocalizedStringKey { "transport_mode.ble" }
        static var classicHint: LocalizedStringKey { "transport_mode.classic.hint" }
        static var bleHint: LocalizedStringKey { "transport_mode.ble.hint" }
    }

    enum Classic {
        static var pairedDevicesSection: LocalizedStringKey {
            "section.paired_devices"
        }

        static var noPairedDevices: LocalizedStringKey {
            "classic.no_paired_devices"
        }

        static var refresh: LocalizedStringKey {
            "classic.refresh"
        }

        static var connect: LocalizedStringKey {
            "classic.connect"
        }

        static var disconnect: LocalizedStringKey {
            "classic.disconnect"
        }

        static var connected: LocalizedStringKey {
            "classic.connected"
        }

        static var ready: LocalizedStringKey {
            "classic.ready"
        }

        static var sdpPublished: LocalizedStringKey {
            "classic.sdp_published"
        }

        static var pairFromSystemSettings: LocalizedStringKey {
            "classic.pair_from_system_settings"
        }

        static var pairNewDevice: LocalizedStringKey {
            "classic.pair_new_device"
        }

        static var pairWindowTitle: String {
            String(localized: "classic.pair_window.title")
        }

        static var pairWindowHeader: String {
            String(localized: "classic.pair_window.header")
        }

        static var pairWindowDescription: String {
            String(localized: "classic.pair_window.description")
        }
    }
}
