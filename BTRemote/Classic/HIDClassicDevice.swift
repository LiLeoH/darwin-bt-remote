#if os(macOS)
import Combine
import Foundation
@preconcurrency import IOBluetooth
@preconcurrency import IOBluetoothUI
import os
import SwiftUI

// classic (macOS): publish a classic HID Profile 1.1 SDP record then open L2CAP control/interrupt channels to the paired host and emit HID reports

// LE mode: macOS dual-mode controller advertises the public BD address with the BR/EDR-supported flag set, so the paired host can merge LE entry with BR/EDR record, but finds no HID profile as the host only looks for classic mode

@MainActor
final class HIDClassicDevice: NSObject, ObservableObject {
    @Published private(set) var state: ControllerState = .unknown
    @Published private(set) var pairedDevices: [PairedDevice] = []
    @Published private(set) var connectedAddress: String?
    @Published private(set) var keyboardLEDs: KeyboardLEDs = []
    @Published private(set) var lastError: String?
    @Published private(set) var batteryLevel: UInt8 = 100
    @Published private(set) var isSDPPublished = false
    @Published private(set) var isReady = false

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDClassicDevice")

    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var device: IOBluetoothDevice?
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    @Published private(set) var isConnecting = false

    /// PSM whose async open is in flight; used to route the delegate callback
    private var openingPSM: UInt16?
    private var connectTimeoutWork: DispatchWorkItem?

    // openL2CAPChannelSync's internal waitforChanneOpen spins when the remote never opens (no HID Host service)
    // openL2CAPChannelAsync returns immediately and delivers via l2capChannelOpenComplete; watchdog added so the open is bounded if delegate is never invoked
    private static let connectTimeout: TimeInterval = 5.0

    // to persist the curated device list
    private static let storedDevicesKey = "BTRemote.classic.devices.v1"
    private let defaults: UserDefaults = .standard

    enum ControllerState: Equatable {
        case unknown, poweredOff, poweredOn
    }

    struct PairedDevice: Identifiable, Equatable, Codable {
        let id: String
        let name: String
        var isConnected: Bool = false

        private enum CodingKeys: String, CodingKey { case id, name }
    }

    // lifecycle 
    func start() {}

    func stop() {
        disconnect()
        unpublishService()
    }

    func publishService() {
        guard serviceRecord == nil else { return }
        let dict = SDPRecord.buildHID(
            reportDescriptor: HIDProfile.reportMapData,
            name: L10n.Bluetooth.advertisedName,
            serviceDescription: L10n.Bluetooth.serviceDescription,
            providerName: L10n.Bluetooth.providerName
        )
        guard let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: dict) else {
            lastError = L10n.ErrorMessage.sdpPublishFailed
            log.error("publishedServiceRecord returned nil")
            return
        }
        serviceRecord = record
        isSDPPublished = true
        var handle: BluetoothSDPServiceRecordHandle = 0
        _ = record.getHandle(&handle)
        log.info("SDP service published; handle=\(handle, privacy: .public)")
    }

    func unpublishService() {
        if let serviceRecord {
            serviceRecord.remove()
            self.serviceRecord = nil
        }
        isSDPPublished = false
    }

    // paired-device picker support

    // the device list comes from JSON array persisted in NSUserDefaults
    // only show peers explicitly added through the pair modal
    func refreshPairedDevices() {
        var collected = _loadStoredDevices()
        for i in collected.indices {
            collected[i].isConnected = _isClassicAclUp(addressID: collected[i].id)
        }
        pairedDevices = collected
    }

    // calls a private BOOL getter on IOBluetoothDevice via KVC
    // returns false if selector missing
    nonisolated fileprivate static func _privateBool(_ object: AnyObject, key: String) -> Bool {
        guard let ns = object as? NSObject else { return false }
        let value = ns.value(forKey: key)
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    private func _loadStoredDevices() -> [PairedDevice] {
        guard let data = defaults.data(forKey: Self.storedDevicesKey) else { return [] }
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }

    private func _saveStoredDevices(_ list: [PairedDevice]) {
        let data = try? JSONEncoder().encode(list)
        defaults.set(data, forKey: Self.storedDevicesKey)
    }

    private func _isClassicAclUp(addressID: String) -> Bool {
        guard let dev = _lookup(addressID: addressID) else { return false }
        return dev.isConnected()
    }

    // append a device the user just paired via the modal; no-op if already present
    private func _rememberDevice(_ entry: PairedDevice) {
        var list = _loadStoredDevices()
        if list.contains(where: { $0.id == entry.id }) { return }
        list.append(entry)
        _saveStoredDevices(list)
    }

    // user-initiated removal of a stored entry; does not unpair at OS level
    func forgetDevice(id: String) {
        var list = _loadStoredDevices()
        list.removeAll { $0.id == id }
        _saveStoredDevices(list)
        refreshPairedDevices()
    }

    // system device selector + pair UI (IOBluetoothDeviceSelectorController)
    // temporarily flips Class of Device so remote scanners recognize it as a HID device during handshake
    // returns the IOBluetoothDevice the user selected, if any
    @discardableResult
    func presentPairingPicker() -> PairedDevice? {
        // get selector first, then publishService, then setCoD
        guard let selector = IOBluetoothDeviceSelectorController.deviceSelector() else {
            lastError = L10n.ErrorMessage.sdpPublishFailed
            return nil
        }
        publishService()

        if let host = IOBluetoothHostController.default() {
            host.setClassOfDevice(0x2540, forTimeInterval: 120.0)
        }
        selector.setTitle(L10n.Classic.pairWindowTitle)
        selector.setHeader(L10n.Classic.pairWindowHeader)
        selector.setDescriptionText(L10n.Classic.pairWindowDescription)
        let response = selector.runModal()
        guard response == kIOBluetoothUISuccess else {
            return nil
        }
        let results = selector.getResults() as? [IOBluetoothDevice] ?? []

        guard let picked = results.first else {
            return nil
        }
        let entry = PairedDevice(
            id: _canonicalAddress(picked.addressString ?? ""),
            name: picked.name ?? picked.addressString ?? L10n.Device.unknownName,
            isConnected: picked.isConnected()
        )
        _rememberDevice(entry)
        refreshPairedDevices()
        return entry
    }

    func connect(to peer: PairedDevice) {
        guard !isConnecting else { return }
        publishService()
        guard let target = _lookup(addressID: peer.id) else {
            lastError = L10n.ErrorMessage.deviceNotPaired(peer.name)
            return
        }
        disconnect()
        device = target
        isConnecting = true
        let addressStr = target.addressString ?? "?"
        log.info("opening ACL to \(addressStr, privacy: .public)")

        if !target.isConnected() {
            let aclResult = target.openConnection()
            if aclResult != kIOReturnSuccess {
                lastError = L10n.ErrorMessage.openConnectionFailed(Self._ioReturnCode(aclResult))
                log.error("openConnection failed \(Self._ioReturnCode(aclResult), privacy: .public)")
                isConnecting = false
                device = nil
                return
            }
        }

        var control: IOBluetoothL2CAPChannel?
        let controlResult = target.openL2CAPChannelSync(&control, withPSM: BluetoothL2CAPPSM(0x0011), delegate: self)
        if controlResult != kIOReturnSuccess || control == nil {
            lastError = L10n.ErrorMessage.openL2CAPFailed(0x0011, Self._ioReturnCode(controlResult))
            log.error("L2CAP PSM 0x0011 open failed \(Self._ioReturnCode(controlResult), privacy: .public)")
            target.closeConnection()
            device = nil
            isConnecting = false
            return
        }
        log.info("control L2CAP open")

        var interrupt: IOBluetoothL2CAPChannel?
        let interruptResult = target.openL2CAPChannelSync(&interrupt, withPSM: BluetoothL2CAPPSM(0x0013), delegate: self)
        if interruptResult != kIOReturnSuccess || interrupt == nil {
            lastError = L10n.ErrorMessage.openL2CAPFailed(0x0013, Self._ioReturnCode(interruptResult))
            log.error("L2CAP PSM 0x0013 open failed \(Self._ioReturnCode(interruptResult), privacy: .public)")
            control?.close()
            target.closeConnection()
            device = nil
            isConnecting = false
            return
        }
        log.info("interrupt L2CAP open")

        controlChannel = control
        interruptChannel = interrupt
        connectedAddress = Self._canonicalAddress(addressStr)
        isReady = true
        isConnecting = false
        refreshPairedDevices()
    }

    func disconnect() {
        controlChannel?.close()
        interruptChannel?.close()
        controlChannel = nil
        interruptChannel = nil
        device?.closeConnection()
        device = nil
        connectedAddress = nil
        isReady = false
    }

    // report emission (same surface as HIDPeripheral)
    func sendMouse(_ report: MouseReport) {
        _sendInputReport(.mouse, payload: report.data)
    }

    func sendKeyboard(_ report: KeyboardReport) {
        _sendInputReport(.keyboard, payload: report.data)
    }

    func sendConsumer(_ report: ConsumerReport) {
        _sendInputReport(.consumerControl, payload: report.data)
    }

    func sendSystemControl(_ report: SystemControlReport) {
        _sendInputReport(.systemControl, payload: report.data)
    }

    func updateBatteryLevel(_ level: UInt8) {
        // classic HID has no separate battery service; report ID 4 sends battery via HID input
        let clamped = min(level, 100)
        batteryLevel = clamped
        _sendInputReport(.battery, payload: Data([clamped]))
    }

    // internals
    private func _refreshState() {
        let host = IOBluetoothHostController.default()
        guard let power = host?.powerState else { state = .unknown; return }
        if power == kBluetoothHCIPowerStateON {
            state = .poweredOn
        } else if power == kBluetoothHCIPowerStateOFF {
            state = .poweredOff
        } else {
            state = .unknown
        }
    }

    nonisolated private static func _canonicalAddress(_ raw: String) -> String {
        raw.lowercased().filter { $0.isHexDigit }
    }

    private func _canonicalAddress(_ raw: String) -> String {
        Self._canonicalAddress(raw)
    }

    private func _lookup(addressID: String) -> IOBluetoothDevice? {
        // pairedDevices() can return a stale reference whose internal state is out-of-date
        let formatted = _formatAddressForLookup(addressID)
        return IOBluetoothDevice(addressString: formatted)
    }

    private func _formatAddressForLookup(_ canonical: String) -> String {
        var result = ""
        for (i, ch) in canonical.enumerated() {
            if i > 0, i % 2 == 0 { result.append("-") }
            result.append(ch)
        }
        return result
    }

    // HID Interrupt PDU: header 0xA1 (DATA / INPUT) + reportID + payload
    private func _sendInputReport(_ reportID: ReportID, payload: Data) {
        guard let interruptChannel else { return }
        var buffer = Data(capacity: 2 + payload.count)
        buffer.append(0xA1)
        buffer.append(reportID.rawValue)
        buffer.append(payload)
        let length = UInt16(buffer.count)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let status = interruptChannel.writeAsync(base, length: length, refcon: nil)
            if status != kIOReturnSuccess {
                lastError = L10n.ErrorMessage.writeFailed(Self._ioReturnCode(status))
                log.error("writeAsync interrupt failed \(Self._ioReturnCode(status), privacy: .public)")
            }
        }
    }

    nonisolated fileprivate static func _ioReturnCode(_ code: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}

// IOBluetoothL2CAPChannelDelegate
extension HIDClassicDevice: @preconcurrency IOBluetoothL2CAPChannelDelegate {
    func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        if error != kIOReturnSuccess {
            lastError = L10n.ErrorMessage.openL2CAPFailed(UInt16(channel?.psm ?? 0), Self._ioReturnCode(error))
        }
    }

    func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        if channel === controlChannel { controlChannel = nil }
        if channel === interruptChannel { interruptChannel = nil }
        if controlChannel == nil, interruptChannel == nil {
            isReady = false
            connectedAddress = nil
        }
    }

    func l2capChannelReconfigured(_ channel: IOBluetoothL2CAPChannel!) {}

    func l2capChannelData(
        _ channel: IOBluetoothL2CAPChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let bytes = Data(bytes: dataPointer, count: dataLength)
        _handleHostMessage(on: channel, bytes: bytes)
    }

    func l2capChannelWriteComplete(
        _ channel: IOBluetoothL2CAPChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        if error != kIOReturnSuccess {
            log.error("writeComplete error: \(Self._ioReturnCode(error), privacy: .public)")
        }
    }

    // host writes flow over PSM 0x11 (Control)
    // spec mandates responding with HID HANDSHAKE byte for every well-formed message on control channel
    // for any recognized transaction it passes status 0
    private func _handleHostMessage(on channel: IOBluetoothL2CAPChannel, bytes: Data) {
        guard let header = bytes.first else { return }
        let transaction = header >> 4
        let reportTypeParam = header & 0x03

        // extract LED state from SET_REPORT/output before responding
        if transaction == 0x5 || transaction == 0xA {
            if reportTypeParam == 0x02, bytes.count >= 3 {
                let reportID = bytes[1]
                if reportID == ReportID.keyboardLEDs.rawValue {
                    keyboardLEDs = KeyboardLEDs(byte: bytes[2])
                }
            }
        }

        // send HANDSHAKE response on control channel only
        if channel.psm == 0x0011 {
            _sendControlHandshake(status: .successful)
        }
    }

    // HID HANDSHAKE response codes per BT HID profile spec
    private enum HandshakeStatus: UInt8 {
        case successful = 0x00
        case notReady = 0x01
        case errInvalidReportID = 0x02
        case errUnsupportedRequest = 0x03
        case errInvalidParameter = 0x04
        case errUnknown = 0x0E
        case errFatal = 0x0F
    }

    // HID HANDSHAKE message
    private func _sendControlHandshake(status: HandshakeStatus) {
        guard let controlChannel else { return }
        var byte: UInt8 = status.rawValue
        withUnsafeMutablePointer(to: &byte) { ptr in
            _ = controlChannel.writeAsync(UnsafeMutableRawPointer(ptr), length: 1, refcon: nil)
        }
    }
}
#endif
