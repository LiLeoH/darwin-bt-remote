import Combine
import CoreBluetooth
import os
import SwiftUI

// HID-over-GATT peripheral engine.

@MainActor
final class HIDPeripheral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var isHIDServiceAdded = false
    @Published private(set) var subscribedCentrals: Set<UUID> = []
    @Published private(set) var keyboardLEDs: KeyboardLEDs = []
    @Published private(set) var lastError: String?
    @Published private(set) var batteryLevel: UInt8 = 100

    var advertiseLocalName: String = L10n.Bluetooth.advertisedName

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDPeripheral")
    private var pManager: CBPeripheralManager?
    private var batteryServiceObj: CBMutableService?
    private var hidServiceObj: CBMutableService?
    private var isHIDServiceAllowed = false
    private var isReadyToSendNotification = true

    private var charsByReportID: [UInt8: CBMutableCharacteristic] = [:]
    private var bootMouseInputChar: CBMutableCharacteristic?
    private var bootKeyboardInputChar: CBMutableCharacteristic?
    private var bootKeyboardOutputChar: CBMutableCharacteristic?
    private var batteryLevelChar: CBMutableCharacteristic?

    /// Last-sent payloads for reads and new subscriptions.
    private var cachedReports: [UInt8: Data] = [
        ReportID.mouse.rawValue: MouseReport.zero.data,
        ReportID.keyboard.rawValue: KeyboardReport.zero.data,
        ReportID.systemControl.rawValue: SystemControlReport.zero.data,
        ReportID.consumerControl.rawValue: ConsumerReport.zero.data
    ]

    private var pendingBroadcast: (Data, CBMutableCharacteristic)?

    func start() {
        isHIDServiceAllowed = true
        if pManager == nil {
            pManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [
                    CBPeripheralManagerOptionRestoreIdentifierKey: HIDProfile.restoreIdentifier,
                    CBPeripheralManagerOptionShowPowerAlertKey: true
                ]
            )
        } else if state == .poweredOn {
            installServices()
        }
    }

    func stop() {
        isHIDServiceAllowed = false
        pManager?.stopAdvertising()
        isAdvertising = false
    }

    func sendMouse(_ report: MouseReport) {
        broadcast(report.data, reportID: .mouse)
    }

    func sendKeyboard(_ report: KeyboardReport) {
        broadcast(report.data, reportID: .keyboard)
        // Boot mode hosts read this characteristic instead.
        bootKeyboardInputChar.map { _ = updateValue(report.data, for: $0) }
    }

    func sendConsumer(_ report: ConsumerReport) {
        broadcast(report.data, reportID: .consumerControl)
    }

    func sendSystemControl(_ report: SystemControlReport) {
        broadcast(report.data, reportID: .systemControl)
    }

    func updateBatteryLevel(_ level: UInt8) {
        let clamped = min(level, 100)
        batteryLevel = clamped
        let asHIDReport = Data([clamped])
        cachedReports[ReportID.battery.rawValue] = asHIDReport
        if let batteryLevelChar { _ = updateValue(asHIDReport, for: batteryLevelChar) }
    }

    func adoptRestoredLaunchOptions(_ value: Any) {
        log.info("received restored bluetoothPeripherals key: \(String(describing: value), privacy: .public)")
    }

    private func installServices() {
        guard let pManager, !isHIDServiceAdded, batteryServiceObj == nil else { return }
        let battery = buildBatteryService()
        batteryServiceObj = battery
        pManager.add(battery)
    }

    private func buildBatteryService() -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.batteryService, primary: true)
        let level = CBMutableCharacteristic(
            type: HIDProfile.batteryLevel,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: .readEncryptionRequired
        )
        // Expose battery as HID Report ID 4 too.
        let reportRef = CBMutableDescriptor(
            type: HIDProfile.reportReference,
            value: ReportID.battery.descriptor(.input)
        )
        level.descriptors = [reportRef]
        service.characteristics = [level]
        batteryLevelChar = level
        return service
    }

    /// Builds the HID service.
    private func buildHIDService(includingBattery battery: CBMutableService?) -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.hidService, primary: true)
        if let battery { service.includedServices = [battery] }

        // Matches the original app's read-only control point.
        let controlPoint = CBMutableCharacteristic(
            type: HIDProfile.hidControlPoint,
            properties: .read,
            value: nil,
            permissions: .readEncryptionRequired
        )

        // extendedProperties is required for iOS to accept this service.
        let protocolMode = CBMutableCharacteristic(
            type: HIDProfile.protocolMode,
            properties: [.read, .writeWithoutResponse, .extendedProperties],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        // 3. HID Information.
        let hidInfo = CBMutableCharacteristic(
            type: HIDProfile.hidInformation,
            properties: .read,
            value: HIDProfile.hidInformationValue,
            permissions: .readEncryptionRequired
        )

        // 4-6. Boot mode characteristics.
        let bootMouseInput = CBMutableCharacteristic(
            type: HIDProfile.bootMouseInputReport,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let bootKbdInput = CBMutableCharacteristic(
            type: HIDProfile.bootKeyboardInputReport,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let bootKbdOutput = CBMutableCharacteristic(
            type: HIDProfile.bootKeyboardOutputReport,
            properties: [.read, .writeWithoutResponse, .write, .extendedProperties],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        // Links the HID report map to Battery Level.
        let reportMap = CBMutableCharacteristic(
            type: HIDProfile.reportMap,
            properties: .read,
            value: HIDProfile.reportMapData,
            permissions: .readEncryptionRequired
        )
        reportMap.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.externalReportReference,
                value: HIDProfile.externalReportReferenceValue
            )
        ]

        // Report characteristic order matters.
        let systemReportChar = makeReportChar(.systemControl, type: .input)
        let consumerReportChar = makeReportChar(.consumerControl, type: .input)
        let mouseReportChar = makeReportChar(.mouse, type: .input)
        let keyboardReportChar = makeReportChar(.keyboard, type: .input)
        let outputReportChar = CBMutableCharacteristic(
            type: HIDProfile.report,
            properties: [.read, .writeWithoutResponse, .write, .extendedProperties],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        outputReportChar.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.reportReference,
                value: ReportID.keyboardLEDs.descriptor(.output)
            )
        ]

        service.characteristics = [
            controlPoint,
            protocolMode,
            hidInfo,
            bootMouseInput,
            bootKbdInput,
            bootKbdOutput,
            reportMap,
            systemReportChar,
            consumerReportChar,
            mouseReportChar,
            keyboardReportChar,
            outputReportChar
        ]

        bootMouseInputChar = bootMouseInput
        bootKeyboardInputChar = bootKbdInput
        bootKeyboardOutputChar = bootKbdOutput
        charsByReportID[ReportID.systemControl.rawValue] = systemReportChar
        charsByReportID[ReportID.consumerControl.rawValue] = consumerReportChar
        charsByReportID[ReportID.mouse.rawValue] = mouseReportChar
        charsByReportID[ReportID.keyboard.rawValue] = keyboardReportChar
        charsByReportID[ReportID.keyboardLEDs.rawValue] = outputReportChar

        return service
    }

    private func makeReportChar(_ id: ReportID, type: ReportType) -> CBMutableCharacteristic {
        let char = CBMutableCharacteristic(
            type: HIDProfile.report,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: .readEncryptionRequired
        )
        char.descriptors = [
            CBMutableDescriptor(type: HIDProfile.reportReference, value: id.descriptor(type))
        ]
        return char
    }

    private func startAdvertisingNow() {
        guard let pManager, !isAdvertising else { return }
        pManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertiseLocalName,
            CBAdvertisementDataServiceUUIDsKey: [HIDProfile.batteryService, HIDProfile.hidService]
        ])
    }

    private func broadcast(_ data: Data, reportID: ReportID) {
        cachedReports[reportID.rawValue] = data
        guard let char = charsByReportID[reportID.rawValue] else { return }
        _ = updateValue(data, for: char)
    }

    @discardableResult
    private func updateValue(_ data: Data, for char: CBMutableCharacteristic) -> Bool {
        guard let pManager, !subscribedCentrals.isEmpty else { return false }
        if !isReadyToSendNotification {
            pendingBroadcast = (data, char)
            return false
        }
        let accepted = pManager.updateValue(data, for: char, onSubscribedCentrals: nil)
        if !accepted {
            isReadyToSendNotification = false
            pendingBroadcast = (data, char)
        }
        return accepted
    }

    private func drainPendingBroadcast() {
        guard let (data, char) = pendingBroadcast, let pManager else { return }
        pendingBroadcast = nil
        let accepted = pManager.updateValue(data, for: char, onSubscribedCentrals: nil)
        if !accepted {
            isReadyToSendNotification = false
            pendingBroadcast = (data, char)
        }
    }

    private func reportID(forCharacteristic char: CBCharacteristic) -> UInt8? {
        for (id, c) in charsByReportID where c.uuid == char.uuid && c === char as AnyObject {
            return id
        }
        // Fallback for restored characteristics.
        if char.uuid == HIDProfile.report,
           let descriptor = (char as? CBMutableCharacteristic)?
           .descriptors?
           .first(where: { $0.uuid == HIDProfile.reportReference }),
           let value = descriptor.value as? Data,
           let id = value.first
        {
            return id
        }
        return nil
    }
}

extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        state = peripheral.state
        log.info("CB state -> \(peripheral.state.rawValue, privacy: .public)")
        if peripheral.state == .poweredOn, isHIDServiceAllowed, !isHIDServiceAdded {
            installServices()
        }
        if peripheral.state != .poweredOn {
            isAdvertising = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        log.info("willRestoreState: \(dict.keys.sorted(), privacy: .public)")
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services {
                if service.uuid == HIDProfile.hidService {
                    hidServiceObj = service
                    isHIDServiceAdded = true
                }
                if service.uuid == HIDProfile.batteryService {
                    batteryServiceObj = service
                }
                for case let mutable as CBMutableCharacteristic in service.characteristics ?? [] {
                    indexRestoredCharacteristic(mutable)
                }
            }
        }
    }

    private func indexRestoredCharacteristic(_ char: CBMutableCharacteristic) {
        switch char.uuid {
        case HIDProfile.bootMouseInputReport: bootMouseInputChar = char
        case HIDProfile.bootKeyboardInputReport: bootKeyboardInputChar = char
        case HIDProfile.bootKeyboardOutputReport: bootKeyboardOutputChar = char
        case HIDProfile.batteryLevel: batteryLevelChar = char
        case HIDProfile.report:
            if let descriptor = char.descriptors?.first(where: { $0.uuid == HIDProfile.reportReference }),
               let value = descriptor.value as? Data,
               let id = value.first
            {
                charsByReportID[id] = char
            }
        default: break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log.error("didAddService(\(service.uuid)) error: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        switch service.uuid {
        case HIDProfile.batteryService:
            let hid = buildHIDService(includingBattery: error == nil ? batteryServiceObj : nil)
            hidServiceObj = hid
            peripheral.add(hid)
        case HIDProfile.hidService:
            isHIDServiceAdded = true
            startAdvertisingNow()
        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            isAdvertising = false
            lastError = error.localizedDescription
            log.error("startAdvertising error: \(error.localizedDescription, privacy: .public)")
        } else {
            isAdvertising = true
            let localName = advertiseLocalName
            log.info("advertising as \(localName, privacy: .public)")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedCentrals.insert(central.identifier)
        log.info("subscribe: \(central.identifier, privacy: .public) -> \(characteristic.uuid)")
        if let id = reportID(forCharacteristic: characteristic),
           let cached = cachedReports[id],
           let char = charsByReportID[id]
        {
            _ = updateValue(cached, for: char)
        } else if characteristic.uuid == HIDProfile.bootMouseInputReport, let bootMouseInputChar {
            _ = updateValue(MouseReport.zero.data, for: bootMouseInputChar)
        } else if characteristic.uuid == HIDProfile.bootKeyboardInputReport, let bootKeyboardInputChar {
            _ = updateValue(KeyboardReport.zero.data, for: bootKeyboardInputChar)
        } else if characteristic.uuid == HIDProfile.batteryLevel, let batteryLevelChar {
            _ = updateValue(Data([batteryLevel]), for: batteryLevelChar)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        log.info("unsubscribe: \(central.identifier, privacy: .public) <- \(characteristic.uuid)")
        // Best-effort: CoreBluetooth does not give us per-central subscription state.
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        isReadyToSendNotification = true
        drainPendingBroadcast()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let value = readValue(forRequest: request)
        guard let value else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    private func readValue(forRequest request: CBATTRequest) -> Data? {
        switch request.characteristic.uuid {
        case HIDProfile.batteryLevel: return Data([batteryLevel])
        case HIDProfile.hidInformation: return HIDProfile.hidInformationValue
        case HIDProfile.reportMap: return HIDProfile.reportMapData
        case HIDProfile.protocolMode: return Data([0x01]) // Report Protocol
        case HIDProfile.report:
            if let id = reportID(forCharacteristic: request.characteristic) {
                return cachedReports[id] ?? Data()
            }
            return Data()
        case HIDProfile.bootMouseInputReport: return cachedReports[ReportID.mouse.rawValue]
        case HIDProfile.bootKeyboardInputReport: return cachedReports[ReportID.keyboard.rawValue]
        default: return Data()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            handleWriteRequest(request)
        }
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    private func handleWriteRequest(_ request: CBATTRequest) {
        guard let value = request.value else { return }
        switch request.characteristic.uuid {
        case HIDProfile.bootKeyboardOutputReport:
            if let byte = value.first { keyboardLEDs = KeyboardLEDs(byte: byte) }
        case HIDProfile.report:
            if reportID(forCharacteristic: request.characteristic) == ReportID.keyboardLEDs.rawValue,
               let byte = value.first
            {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.protocolMode, HIDProfile.hidControlPoint:
            break
        default:
            break
        }
    }
}
