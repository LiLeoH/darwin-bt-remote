import Combine
import CoreBluetooth
import os
import SwiftUI

/// Mirrors key diagnostics to a plain file (in addition to os_log) so they can be read
/// without Console.app / `log show`, which is blocked in some sessions. The file lives in
/// Application Support (sandbox-safe) and is a normal file, not the protected unified log.
private enum DiagnosticLog {
    static let fileURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("BTRemote", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("peripheral.log")
    }()

    static func append(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts)  \(message)\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

// swiftlint:disable file_length type_body_length
/// HID-over-GATT peripheral engine
@MainActor
final class HIDPeripheral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var isHIDServiceAdded = false
    /// central identifier: the set of characteristic UUIDs it is currently subscribed to
    @Published private(set) var subscribedCentrals: [UUID: Set<CBUUID>] = [:]
    /// broadcasts skip inactive hosts
    @Published private(set) var inactiveCentrals: Set<UUID> = []
    @Published private(set) var connectedCentrals: Set<UUID> = []
    @Published private(set) var keyboardLEDs: KeyboardLEDs = []
    @Published private(set) var lastError: String?
    @Published private(set) var batteryLevel: UInt8 = 100

    private var centralObjects: [UUID: CBCentral] = [:]

    var advertiseLocalName: String = L10n.Bluetooth.advertisedName

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDPeripheral")
    private var pManager: CBPeripheralManager?
    private var batteryServiceObj: CBMutableService?
    private var deviceInfoServiceObj: CBMutableService?
    private var hidServiceObj: CBMutableService?
    private var isHIDServiceAllowed = false
    private var isReadyToSendNotification = true
    /// Set when `isReadyToSendNotification` flips to false, so the watchdog can measure
    /// how long the notification flow has been stalled.
    private var readyStallStart: Date?
    /// If the notification flow stays stalled longer than this, the watchdog force
    /// re-arms `isReadyToSendNotification` and drains, preventing a permanent freeze
    /// (the "latency grows until it stops" failure mode seen over long sessions).
    private let readyStallTimeout: TimeInterval = 1.5
    private var readyWatchdog: DispatchSourceTimer?

    private var charsByReportID: [UInt8: CBMutableCharacteristic] = [:]
    private var bootMouseInputChar: CBMutableCharacteristic?
    private var bootKeyboardInputChar: CBMutableCharacteristic?
    private var bootKeyboardOutputChar: CBMutableCharacteristic?
    private var batteryLevelChar: CBMutableCharacteristic?
    private var serviceChangedObj: CBMutableService?
    #if os(macOS)
        private var clipboardServiceObj: CBMutableService?
        private var clipboardNotifyChar: CBMutableCharacteristic?
        var onClipboardWrite: ((UUID, Data) -> Void)?
        var onClipboardSubscriptionChange: (() -> Void)?
        var onClipboardReady: (() -> Void)?
    #endif
    private var serviceChangedArmed = false
    private static let serviceChangedGrace: UInt64 = 2_000_000_000

    /// last-sent payloads for reads and new subscriptions
    private var cachedReports: [UInt8: Data] = [
        ReportID.mouse.rawValue: MouseReport.zero.data,
        ReportID.keyboard.rawValue: KeyboardReport.zero.data,
        ReportID.systemControl.rawValue: SystemControlReport.zero.data,
        ReportID.consumerControl.rawValue: ConsumerReport.zero.data
    ]

    private var pendingBroadcast: (Data, CBMutableCharacteristic)?

    func start() {
        isHIDServiceAllowed = true
        _diag("diagnostics file: \(DiagnosticLog.fileURL.path)")
        if pManager == nil {
            pManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        } else if state == .poweredOn {
            if isHIDServiceAdded {
                startAdvertisingNow()
            } else {
                installServices()
            }
        }
        ensureReadyWatchdog()
    }

    func stop() {
        isHIDServiceAllowed = false
        pManager?.stopAdvertising()
        isAdvertising = false
    }

    func promptPowerAlert() {
        guard state != .poweredOn else { return }
        _resetForRestart()
        start()
    }

    private func _resetForRestart() {
        pManager?.stopAdvertising()
        pManager?.removeAllServices()
        pManager = nil
        isAdvertising = false
        isHIDServiceAdded = false
        isReadyToSendNotification = true
        readyStallStart = nil
        readyWatchdog?.cancel()
        readyWatchdog = nil
        pendingBroadcast = nil
        batteryServiceObj = nil
        deviceInfoServiceObj = nil
        hidServiceObj = nil
        serviceChangedObj = nil
        #if os(macOS)
            clipboardServiceObj = nil
            clipboardNotifyChar = nil
        #endif
        serviceChangedArmed = false
        batteryLevelChar = nil
        bootMouseInputChar = nil
        bootKeyboardInputChar = nil
        bootKeyboardOutputChar = nil
        charsByReportID.removeAll()
        subscribedCentrals.removeAll()
        inactiveCentrals.removeAll()
        connectedCentrals.removeAll()
        centralObjects.removeAll()
    }

    func sendMouse(_ report: MouseReport, _ onSent: @escaping () -> Void) {
        broadcast(report.data, reportID: .mouse)
        // Low Energy flow-controls itself via CBPeripheralManager.updateValue (returns false when
        // the GATT queue is full), so no real backpressure is needed here; fire the completion
        // synchronously so the caller's in-flight counter stays balanced.
        onSent()
    }

    func sendKeyboard(_ report: KeyboardReport) {
        broadcast(report.data, reportID: .keyboard)
        // boot mode hosts read this characteristic instead
        bootKeyboardInputChar.map { _ = updateValue(report.data, for: $0) }
    }

    func sendConsumer(_ report: ConsumerReport) {
        broadcast(report.data, reportID: .consumerControl)
    }

    func sendSystemControl(_ report: SystemControlReport) {
        broadcast(report.data, reportID: .systemControl)
    }

    func toggleActive(_ uuid: UUID) {
        if inactiveCentrals.contains(uuid) {
            inactiveCentrals.remove(uuid)
        } else {
            inactiveCentrals.insert(uuid)
        }
    }

    func updateBatteryLevel(_ level: UInt8) {
        let clamped = min(level, 100)
        batteryLevel = clamped
        let asHIDReport = Data([clamped])
        cachedReports[ReportID.battery.rawValue] = asHIDReport
        if let batteryLevelChar {
            _ = updateValue(asHIDReport, for: batteryLevelChar)
        }
    }

    /// if host connects but never subscribes (stale GATT cache), cycle a temp service to fire Service Changed so it re-discovers
    func scheduleServiceChanged() {
        guard UserDefaults.standard.bool(forKey: AppSettings.useServiceChangedKey), !serviceChangedArmed else { return }
        serviceChangedArmed = true
        let probeSeconds = Double(Self.serviceChangedGrace) / 1_000_000_000
        _diag("Service Changed armed: host interacted but not subscribed; will probe in \(probeSeconds)s")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.serviceChangedGrace)
            self?._cycleServiceChangedIfUnsubscribed()
        }
    }

    private func _cycleServiceChangedIfUnsubscribed() {
        guard subscribedCentrals.isEmpty else {
            let subCount = subscribedCentrals.count
            _diag("Service Changed skipped: subscription present (count=\(subCount))")
            return
        }
        let connCount = connectedCentrals.count
        _diag("Service Changed fired with no subscribers (connected=\(connCount)); Windows stale cache/bond likely")
        _cycleServiceChanged()
    }

    private func _cycleServiceChanged() {
        guard let pManager else { return }
        if let svc = serviceChangedObj {
            pManager.remove(svc)
            pManager.add(svc)
        } else {
            let svc = buildServiceChangedTrigger()
            serviceChangedObj = svc
            pManager.add(svc)
        }
        _diag("Service Changed cycled (GATT perturbed to force host re-discovery)")
    }

    /// temp service used to perturb the GATT to trigger Service Changed
    private func buildServiceChangedTrigger() -> CBMutableService {
        let service = CBMutableService(type: CBUUID(nsuuid: UUID()), primary: true)
        service.characteristics = [
            CBMutableCharacteristic(
                type: CBUUID(nsuuid: UUID()),
                properties: [.read, .notifyEncryptionRequired],
                value: nil,
                permissions: .readEncryptionRequired
            )
        ]
        return service
    }

    #if os(macOS)
        private func buildClipboardService() -> CBMutableService {
            let service = CBMutableService(type: ClipboardSyncProfile.service, primary: true)
            let notify = CBMutableCharacteristic(
                type: ClipboardSyncProfile.notifyChar,
                properties: [.read, .notifyEncryptionRequired],
                value: nil,
                permissions: .readEncryptionRequired
            )
            let write = CBMutableCharacteristic(
                type: ClipboardSyncProfile.writeChar,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeEncryptionRequired
            )
            service.characteristics = [notify, write]
            clipboardNotifyChar = notify
            return service
        }
    #endif

    private func installServices() {
        guard let pManager, !isHIDServiceAdded, batteryServiceObj == nil else { return }
        let battery = buildBatteryService()
        batteryServiceObj = battery
        pManager.add(battery)
    }

    private func buildDeviceInfoService() -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.deviceInformationService, primary: true)
        service.characteristics = [
            CBMutableCharacteristic(
                type: HIDProfile.manufacturerName,
                properties: .read,
                value: HIDProfile.manufacturerNameValue,
                permissions: .readable
            ),
            CBMutableCharacteristic(
                type: HIDProfile.modelNumber,
                properties: .read,
                value: HIDProfile.modelNumberValue,
                permissions: .readable
            ),
            CBMutableCharacteristic(
                type: HIDProfile.pnpID,
                properties: .read,
                value: HIDProfile.pnpIDValue,
                permissions: .readable
            )
        ]
        return service
    }

    private func buildBatteryService() -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.batteryService, primary: true)
        let level = CBMutableCharacteristic(
            type: HIDProfile.batteryLevel,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: .readEncryptionRequired
        )
        // expose battery as HID Report ID 4 too
        let reportRef = CBMutableDescriptor(
            type: HIDProfile.reportReference,
            value: NSData(data: ReportID.battery.descriptor(.input))
        )
        level.descriptors = [reportRef]
        service.characteristics = [level]
        batteryLevelChar = level
        return service
    }

    private func buildHIDService(includingBattery battery: CBMutableService?) -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.hidService, primary: true)
        if let battery {
            service.includedServices = [battery]
        }

        let controlPoint = CBMutableCharacteristic(
            type: HIDProfile.hidControlPoint,
            properties: .read,
            value: nil,
            permissions: .readEncryptionRequired
        )

        let protocolMode = CBMutableCharacteristic(
            type: HIDProfile.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        let hidInfo = CBMutableCharacteristic(
            type: HIDProfile.hidInformation,
            properties: .read,
            value: HIDProfile.hidInformationValue,
            permissions: .readEncryptionRequired
        )

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
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        // links the HID report map to battery level
        let reportMap = CBMutableCharacteristic(
            type: HIDProfile.reportMap,
            properties: .read,
            value: HIDProfile.reportMapData,
            permissions: .readEncryptionRequired
        )
        reportMap.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.externalReportReference,
                value: NSData(data: HIDProfile.externalReportReferenceValue)
            )
        ]

        // report characteristic order matters
        let systemReportChar = makeReportChar(.systemControl, type: .input)
        let consumerReportChar = makeReportChar(.consumerControl, type: .input)
        let mouseReportChar = makeReportChar(.mouse, type: .input)
        let keyboardReportChar = makeReportChar(.keyboard, type: .input)
        let outputReportChar = CBMutableCharacteristic(
            type: HIDProfile.report,
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        outputReportChar.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.reportReference,
                value: NSData(data: ReportID.keyboardLEDs.descriptor(.output))
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
            CBMutableDescriptor(type: HIDProfile.reportReference, value: NSData(data: id.descriptor(type)))
        ]
        return char
    }

    private func startAdvertisingNow() {
        guard let pManager, !isAdvertising else { return }
        pManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertiseLocalName,
            // hidService must stay first if more than one service is being advertised
            CBAdvertisementDataServiceUUIDsKey: [HIDProfile.hidService]
        ])
    }

    private func broadcast(_ data: Data, reportID: ReportID) {
        cachedReports[reportID.rawValue] = data
        guard let char = charsByReportID[reportID.rawValue] else { return }
        _ = updateValue(data, for: char)
    }

    @discardableResult
    private func updateValue(_ data: Data, for char: CBMutableCharacteristic) -> Bool {
        attemptSend(data, for: char)
    }

    /// Sends a HID notification. Prefers a targeted batch send to known-active centrals so the
    /// `inactiveCentrals` pause feature is honored. If the batch send is rejected while we believed
    /// the link was ready — the signature of a dead central (dirty disconnect, never cleanly
    /// unsubscribed) still sitting in `activeRecipients()` and wedging the whole batch at the OS
    /// layer — it falls back to sending to each recipient individually so live centrals still
    /// receive. `updateValue` returning `false` only means the transmit buffer was full (flow
    /// control); it does NOT indicate a central is unreachable, so we never prune on it — pruning
    /// on `false` would delete live centrals during normal flow control and kill Direct Input.
    private func attemptSend(_ data: Data, for char: CBMutableCharacteristic) -> Bool {
        guard let pManager else { return false }
        let recipients = activeRecipients()
        guard !recipients.isEmpty else {
            if !connectedCentrals.isEmpty {
                let connCount = connectedCentrals.count
                _diag("broadcast dropped: \(connCount) connected but none subscribed — stale host cache/bond likely")
            }
            return false
        }
        if !isReadyToSendNotification {
            stashPending(data, for: char)
            return false
        }
        if pManager.updateValue(data, for: char, onSubscribedCentrals: recipients) {
            pendingBroadcast = nil
            return true
        }
        // Batch rejected: a dead central without a clean unsubscribe is still in activeRecipients()
        // and wedges the batch at the OS layer. Send to each central individually; live ones still
        // receive their data. We do NOT prune on a `false` per-central result — that is flow control,
        // not central death, and pruning on it would remove live centrals (the prior failure mode).
        var anyAccepted = false
        for central in recipients where pManager.updateValue(data, for: char, onSubscribedCentrals: [central]) {
            anyAccepted = true
        }
        if anyAccepted {
            _trace("send recovered via per-central fallback (stale central suspected)")
            pendingBroadcast = nil
            return true
        }
        isReadyToSendNotification = false
        stashPending(data, for: char)
        return false
    }

    /// Stashes a report that could not be queued. Mouse reports carry relative deltas, so when a
    /// stalled mouse report would be overwritten by the next one we merge the deltas instead of
    /// dropping them: buttons come from the newest snapshot (same semantics as the prior overwrite),
    /// dX/dY/wheel are summed with Int8 clamping. Overwriting would silently lose accumulated motion
    /// on links that drain slower than the flush cadence (e.g. Windows-negotiated LE connection
    /// intervals), which shows up as choppy, jumpy cursor movement.
    private func stashPending(_ data: Data, for char: CBMutableCharacteristic) {
        if let (pendingData, pendingChar) = pendingBroadcast,
           pendingChar === char,
           char === charsByReportID[ReportID.mouse.rawValue],
           let merged = Self.mergeMouseReports(pendingData, data)
        {
            pendingBroadcast = (merged, char)
        } else {
            pendingBroadcast = (data, char)
        }
    }

    /// Sums the relative deltas of two 4-byte mouse reports; nil if either is not a mouse report body.
    private static func mergeMouseReports(_ older: Data, _ newer: Data) -> Data? {
        guard older.count == 4, newer.count == 4 else { return nil }
        func clampedSum(_ a: UInt8, _ b: UInt8) -> UInt8 {
            let sum = Int(Int8(bitPattern: a)) + Int(Int8(bitPattern: b))
            return UInt8(bitPattern: Int8(max(-127, min(127, sum))))
        }
        return Data([
            newer[0], // buttons: newest full-state snapshot
            clampedSum(older[1], newer[1]),
            clampedSum(older[2], newer[2]),
            clampedSum(older[3], newer[3])
        ])
    }

    private func drainPendingBroadcast() {
        guard let (data, char) = pendingBroadcast else { return }
        pendingBroadcast = nil
        _ = attemptSend(data, for: char)
    }

    /// Starts a low-frequency timer that detects a permanently stuck notification flow
    /// (see `readyStallTimeout`) and force re-arms it so mouse/keyboard input self-heals
    /// instead of freezing after a long session.
    private func ensureReadyWatchdog() {
        guard readyWatchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + readyStallTimeout, repeating: 0.5, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.tickReadyWatchdog() }
        }
        timer.resume()
        readyWatchdog = timer
    }

    private func tickReadyWatchdog() {
        guard !isReadyToSendNotification else {
            readyStallStart = nil
            return
        }
        let now = Date()
        if let start = readyStallStart, now.timeIntervalSince(start) >= readyStallTimeout {
            let timeout = readyStallTimeout
            log.warning("HIDPeripheral: notification flow stalled >\(timeout)s; force re-arming")
            isReadyToSendNotification = true
            readyStallStart = nil
            drainPendingBroadcast()
        } else if readyStallStart == nil {
            readyStallStart = now
        }
    }

    private func _trace(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppSettings.developerModeKey) else { return }
        let text = message()
        log.info("\(text, privacy: .public)")
    }

    /// Diagnostic line that goes to both os_log and the readable file log
    /// (`DiagnosticLog`). Takes a plain String (evaluated in the caller) so property
    /// references inside the message don't trip the `@autoclosure` `self` requirement.
    private func _diag(_ message: String) {
        log.info("\(message, privacy: .public)")
        DiagnosticLog.append(message)
    }

    /// One-line snapshot of the connection/subscription state, logged on every transition
    /// so the "connected but never subscribed" (stale GATT cache / stale bond) failure mode
    /// is visible as a single line in Console.app.
    private func _snapshot(_ reason: String) {
        let connCount = connectedCentrals.count
        let subCount = subscribedCentrals.count
        let inactCount = inactiveCentrals.count
        let ready = isReadyToSendNotification
        _diag("[state] \(reason): connected=\(connCount) subscribed=\(subCount)")
        _diag("[state] \(reason): inactive=\(inactCount) ready=\(ready)")
    }

    private func _trackInteraction(from central: CBCentral) {
        centralObjects[central.identifier] = central
        guard !connectedCentrals.contains(central.identifier) else { return }
        connectedCentrals.insert(central.identifier)
        _diag("central connected: \(central.identifier.uuidString) (MTU \(central.maximumUpdateValueLength))")
        _snapshot("central connected")
    }

    private func activeRecipients() -> [CBCentral] {
        subscribedCentrals.keys
            .filter { !inactiveCentrals.contains($0) }
            .compactMap { centralObjects[$0] }
    }

    private func reportID(forCharacteristic char: CBCharacteristic) -> UInt8? {
        for (id, c) in charsByReportID where c.uuid == char.uuid && c === char as AnyObject {
            return id
        }
        // fallback for restored characteristics
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

    #if os(macOS)
        /// Subscribed centrals for the clipboard notify characteristic (filtered by notify UUID).
        func clipboardRecipients() -> [CBCentral] {
            guard let notifyUUID = clipboardNotifyChar?.uuid else { return [] }
            return subscribedCentrals
                .filter { $0.value.contains(notifyUUID) }
                .keys
                .filter { !inactiveCentrals.contains($0) }
                .compactMap { centralObjects[$0] }
        }

        /// Sends a clipboard chunk to all subscribed clipboard centrals.
        /// Returns false if the GATT transmit buffer is full (wait for `onClipboardReady`).
        @discardableResult
        func sendClipboardChunk(_ chunk: Data) -> Bool {
            guard let pManager,
                  let char = clipboardNotifyChar
            else { return false }
            let recipients = clipboardRecipients()
            guard !recipients.isEmpty else { return false }
            return pManager.updateValue(chunk, for: char, onSubscribedCentrals: recipients)
        }

        /// Max clipboard chunk payload size (min of recipients' `maximumUpdateValueLength - 4`).
        func clipboardMaxChunkPayload() -> Int {
            let recipients = clipboardRecipients()
            guard !recipients.isEmpty else { return 16 }
            let minMTU = recipients.map(\.maximumUpdateValueLength).min() ?? 20
            return max(minMTU - ClipboardSyncProfile.chunkHeaderLen, 16)
        }
    #endif
}

extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        state = peripheral.state
        _diag("CB state -> \(peripheral.state.rawValue)")
        _trace("CB state -> \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn, isHIDServiceAllowed, !isHIDServiceAdded {
            installServices()
        }
        if peripheral.state != .poweredOn {
            isAdvertising = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log.error("didAddService(\(service.uuid)) error: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        switch service.uuid {
        case HIDProfile.batteryService:
            let dis = buildDeviceInfoService()
            deviceInfoServiceObj = dis
            peripheral.add(dis)
        case HIDProfile.deviceInformationService:
            let hid = buildHIDService(includingBattery: batteryServiceObj)
            hidServiceObj = hid
            peripheral.add(hid)
        case HIDProfile.hidService:
            #if os(macOS)
                let cs = buildClipboardService()
                clipboardServiceObj = cs
                peripheral.add(cs)
            #else
                isHIDServiceAdded = true
                startAdvertisingNow()
            #endif
        #if os(macOS)
            case ClipboardSyncProfile.service:
                isHIDServiceAdded = true
                startAdvertisingNow()
        #endif
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
            _trace("advertising as \(advertiseLocalName)")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        _trackInteraction(from: central)
        subscribedCentrals[central.identifier, default: []].insert(characteristic.uuid)
        _diag("subscribe: \(central.identifier.uuidString) -> \(characteristic.uuid.uuidString)")
        _snapshot("subscribe")
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
        #if os(macOS)
            if characteristic.uuid == ClipboardSyncProfile.notifyChar {
                onClipboardSubscriptionChange?()
            }
        #endif
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        _diag("unsubscribe: \(central.identifier.uuidString) <- \(characteristic.uuid.uuidString)")
        _snapshot("unsubscribe")
        guard var chars = subscribedCentrals[central.identifier] else { return }
        chars.remove(characteristic.uuid)
        #if os(macOS)
            if characteristic.uuid == ClipboardSyncProfile.notifyChar {
                onClipboardSubscriptionChange?()
            }
        #endif
        if chars.isEmpty {
            subscribedCentrals.removeValue(forKey: central.identifier)
            centralObjects.removeValue(forKey: central.identifier)
            inactiveCentrals.remove(central.identifier)
            connectedCentrals.remove(central.identifier)
            serviceChangedArmed = false
        } else {
            subscribedCentrals[central.identifier] = chars
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        isReadyToSendNotification = true
        drainPendingBroadcast()
        #if os(macOS)
            onClipboardReady?()
        #endif
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        _trace("read: \(request.central.identifier) -> \(request.characteristic.uuid)")
        _trackInteraction(from: request.central)
        scheduleServiceChanged()
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
        case HIDProfile.protocolMode: return Data([0x01]) // report protocol
        case HIDProfile.manufacturerName: return HIDProfile.manufacturerNameValue
        case HIDProfile.modelNumber: return HIDProfile.modelNumberValue
        case HIDProfile.pnpID: return HIDProfile.pnpIDValue
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
        autoreleasepool {
            for request in requests {
                _trace("write: \(request.central.identifier) -> \(request.characteristic.uuid)")
                _trackInteraction(from: request.central)
                handleWriteRequest(request)
            }
            if let first = requests.first {
                peripheral.respond(to: first, withResult: .success)
            }
        }
    }

    private func handleWriteRequest(_ request: CBATTRequest) {
        guard let value = request.value else { return }
        switch request.characteristic.uuid {
        case HIDProfile.bootKeyboardOutputReport:
            if let byte = value.first {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.report:
            if reportID(forCharacteristic: request.characteristic) == ReportID.keyboardLEDs.rawValue,
               let byte = value.first
            {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.protocolMode, HIDProfile.hidControlPoint:
            break
        #if os(macOS)
            case ClipboardSyncProfile.writeChar:
                onClipboardWrite?(request.central.identifier, value)
        #endif
        default:
            break
        }
    }
}
