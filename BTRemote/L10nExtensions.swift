import Foundation
import SwiftUI

extension L10n {
    enum DeviceInfo {
        static var title: LocalizedStringKey {
            "device_info.title"
        }

        static var info: LocalizedStringKey {
            "device_info.info"
        }

        static var device: LocalizedStringKey {
            "device_info.device"
        }

        static var manufacturer: LocalizedStringKey {
            "device_info.manufacturer"
        }

        static var advertisement: LocalizedStringKey {
            "device_info.advertisement"
        }

        static var services: LocalizedStringKey {
            "device_info.services"
        }

        static var name: LocalizedStringKey {
            "device_info.name"
        }

        static var identifier: LocalizedStringKey {
            "device_info.identifier"
        }

        static var signal: LocalizedStringKey {
            "device_info.signal"
        }

        static var connectable: LocalizedStringKey {
            "device_info.connectable"
        }

        static var txPower: LocalizedStringKey {
            "device_info.tx_power"
        }

        static var done: LocalizedStringKey {
            "device_info.done"
        }
    }

    enum Setup {
        static var help: LocalizedStringKey {
            "setup.help"
        }

        static var videoInstructions: LocalizedStringKey {
            "setup.video_instructions"
        }

        static var activeLegend: LocalizedStringKey {
            "setup.active_legend"
        }

        static var lowEnergyGuide: LocalizedStringKey {
            "setup.le_guide"
        }

        static var classicGuide: LocalizedStringKey {
            "setup.classic_guide"
        }

        static var classicStep1: LocalizedStringKey {
            "setup.classic_step1"
        }

        static var classicStep2: LocalizedStringKey {
            "setup.classic_step2"
        }

        static var classicStep3: LocalizedStringKey {
            "setup.classic_step3"
        }

        static var classicTroubleshooting: LocalizedStringKey {
            "setup.classic_troubleshooting"
        }

        static var fromApp: LocalizedStringKey {
            "setup.from_app"
        }

        static var fromAppStep1: LocalizedStringKey {
            "setup.from_app_step1"
        }

        static var fromAppStep2: LocalizedStringKey {
            "setup.from_app_step2"
        }

        static var fromDevice: LocalizedStringKey {
            "setup.from_device"
        }

        static var fromDeviceStep1: LocalizedStringKey {
            "setup.from_device_step1"
        }

        static var fromDeviceStep2: LocalizedStringKey {
            "setup.from_device_step2"
        }

        static var fromDeviceStep3: LocalizedStringKey {
            "setup.from_device_step3"
        }

        static var troubleshooting: LocalizedStringKey {
            "setup.troubleshooting"
        }

        static var iCloudPaired: LocalizedStringKey {
            "setup.icloud_paired"
        }

        static var findGuideHint: LocalizedStringKey {
            "setup.find_guide_hint"
        }

        static var deviceNameLimitation: LocalizedStringKey {
            "setup.device_name_limitation"
        }

        static var bluetoothOffTitle: LocalizedStringKey {
            "setup.bluetooth_off_title"
        }

        static var bluetoothOffMessage: LocalizedStringKey {
            "setup.bluetooth_off_message"
        }
    }

    enum Settings {
        static var trackpad: LocalizedStringKey {
            "settings.trackpad"
        }

        static var trackingSpeed: LocalizedStringKey {
            "settings.tracking_speed"
        }

        static var scrollSpeed: LocalizedStringKey {
            "settings.scroll_speed"
        }

        static var connection: LocalizedStringKey {
            "settings.connection"
        }

        static var autoAdvertise: LocalizedStringKey {
            "settings.auto_advertise"
        }

        static var autoAdvertiseHint: LocalizedStringKey {
            "settings.auto_advertise_hint"
        }

        static var advanced: LocalizedStringKey {
            "settings.advanced"
        }

        static var developerMode: LocalizedStringKey {
            "settings.developer_mode"
        }

        static var forceServiceChanged: LocalizedStringKey {
            "settings.force_service_changed"
        }

        static var forceServiceChangedHint: LocalizedStringKey {
            "settings.force_service_changed_hint"
        }

        static var sourceCode: LocalizedStringKey {
            "settings.source_code"
        }

        static var reset: LocalizedStringKey {
            "settings.reset"
        }

        static var resetConfirm: LocalizedStringKey {
            "settings.reset_confirm"
        }

        static var directInputRate: LocalizedStringKey {
            "settings.direct_input_rate"
        }

        static var directInputRateHint: LocalizedStringKey {
            "settings.direct_input_rate_hint"
        }

        static var maxOutstandingWrites: LocalizedStringKey {
            "settings.max_outstanding_writes"
        }

        static var maxOutstandingWritesHint: LocalizedStringKey {
            "settings.max_outstanding_writes_hint"
        }

        static var directInputIndicator: LocalizedStringKey {
            "settings.direct_input_indicator"
        }

        static var directInputIndicatorHint: LocalizedStringKey {
            "settings.direct_input_indicator_hint"
        }

        static var macToWindowsModifierRemap: LocalizedStringKey {
            "settings.mac_to_windows_modifier_remap"
        }

        static var macToWindowsModifierRemapHint: LocalizedStringKey {
            "settings.mac_to_windows_modifier_remap_hint"
        }

        static var clipboardSync: LocalizedStringKey {
            "settings.clipboard_sync"
        }

        static var clipboardSyncHint: LocalizedStringKey {
            "settings.clipboard_sync_hint"
        }

        static var clipboardSyncImages: LocalizedStringKey {
            "settings.clipboard_sync_images"
        }

        static var clipboardSyncImagesHint: LocalizedStringKey {
            "settings.clipboard_sync_images_hint"
        }
    }

    enum CaptureIndicator {
        static var label: LocalizedStringKey {
            "capture_indicator.label"
        }

        static var exitPrefix: LocalizedStringKey {
            "capture_indicator.exit_prefix"
        }
    }

    enum StatusBar {
        static var title: LocalizedStringKey {
            "status_bar.title"
        }

        static var windowsShortcuts: LocalizedStringKey {
            "status_bar.windows_shortcuts"
        }

        static var startDirectInput: LocalizedStringKey {
            "status_bar.start_direct_input"
        }

        static var stopDirectInput: LocalizedStringKey {
            "status_bar.stop_direct_input"
        }

        static var active: LocalizedStringKey {
            "status_bar.active"
        }

        static var tooltipIdle: LocalizedStringKey {
            "status_bar.tooltip_idle"
        }

        static var tooltipCapturing: LocalizedStringKey {
            "status_bar.tooltip_capturing"
        }

        static var openMain: LocalizedStringKey {
            "status_bar.open_main"
        }

        static var typeSection: LocalizedStringKey {
            "status_bar.type_section"
        }

        static var typeHintDisconnected: LocalizedStringKey {
            "status_bar.type_hint_disconnected"
        }
    }

    enum Shortcut {
        static var section: LocalizedStringKey {
            "shortcut.section"
        }

        static var recorderIdle: LocalizedStringKey {
            "shortcut.recorder_idle"
        }

        static var recording: LocalizedStringKey {
            "shortcut.recording"
        }

        static var clear: LocalizedStringKey {
            "shortcut.clear"
        }

        static var disabled: LocalizedStringKey {
            "shortcut.disabled"
        }

        static var requiresKey: LocalizedStringKey {
            "shortcut.requires_key"
        }

        static var conflictApp: LocalizedStringKey {
            "shortcut.conflict_app"
        }

        static var conflictSystem: LocalizedStringKey {
            "shortcut.conflict_system"
        }

        static var hint: LocalizedStringKey {
            "shortcut.hint"
        }

        static var bannerOn: LocalizedStringKey {
            "shortcut.banner_on"
        }

        static var bannerOff: LocalizedStringKey {
            "shortcut.banner_off"
        }

        static var recorderHelp: LocalizedStringKey {
            "shortcut.recorder_help"
        }

        static var setupUnsetHint: LocalizedStringKey {
            "shortcut.setup_unset"
        }

        static var statusToggleOff: LocalizedStringKey {
            "shortcut.status_toggle_off"
        }

        static var statusToggleOffString: String {
            String(localized: "shortcut.status_toggle_off")
        }

        static var statusNoShortcut: LocalizedStringKey {
            "shortcut.status_no_shortcut"
        }

        static var statusNoShortcutString: String {
            String(localized: "shortcut.status_no_shortcut")
        }

        static var recorderIdleString: String {
            String(localized: "shortcut.recorder_idle")
        }

        static var recordingString: String {
            String(localized: "shortcut.recording")
        }

        static var clearString: String {
            String(localized: "shortcut.clear")
        }

        static var disabledString: String {
            String(localized: "shortcut.disabled")
        }

        static var requiresKeyString: String {
            String(localized: "shortcut.requires_key")
        }

        static var conflictAppString: String {
            String(localized: "shortcut.conflict_app")
        }

        static var conflictSystemString: String {
            String(localized: "shortcut.conflict_system")
        }

        static var hintString: String {
            String(localized: "shortcut.hint")
        }

        static var bannerOnString: String {
            String(localized: "shortcut.banner_on")
        }

        static var bannerOffString: String {
            String(localized: "shortcut.banner_off")
        }

        static var recorderHelpString: String {
            String(localized: "shortcut.recorder_help")
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
}
