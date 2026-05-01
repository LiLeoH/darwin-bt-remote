import Combine
import CoreBluetooth
import Foundation
import os

/// Central-side scanner and connection-event registrar.
@MainActor
final class HIDCentral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connected: Set<UUID> = []
    @Published private(set) var lastError: String?

    static let restoreIdentifier = "BTRemote.central.v1"

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDCentral")
    private var centralManager: CBCentralManager?
    private var peripheralCache: [UUID: CBPeripheral] = [:]

    func start() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: HIDCentral.restoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    func startScan() {
        guard let centralManager, centralManager.state == .poweredOn else {
            start()
            return
        }
        discovered.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        log.info("scan started")
    }

    func stopScan() {
        centralManager?.stopScan()
        isScanning = false
        log.info("scan stopped")
    }

    func connect(_ identifier: UUID) {
        guard let centralManager else { return }
        let peripheral = peripheralCache[identifier]
            ?? centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        guard let peripheral else {
            lastError = L10n.ErrorMessage.peripheralNotRetained(identifier)
            return
        }
        peripheralCache[identifier] = peripheral
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        log.info("connect requested: \(peripheral.identifier, privacy: .public)")
    }

    func disconnect(_ identifier: UUID) {
        guard let centralManager, let peripheral = peripheralCache[identifier] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func refreshKnownPeripherals(servicesFilter: [CBUUID] = [HIDProfile.hidService]) {
        guard let centralManager else { return }
        let known = centralManager.retrieveConnectedPeripherals(withServices: servicesFilter)
        for peripheral in known {
            peripheralCache[peripheral.identifier] = peripheral
            upsertDiscovered(
                peripheral: peripheral,
                advertisementData: [:],
                rssi: 0,
                fromKnown: true
            )
        }
    }

    private func upsertDiscovered(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: Int,
        fromKnown: Bool = false
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let entry = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name ?? L10n.Device.unknownName,
            rssi: rssi,
            advertisedServices: services,
            knownByOS: fromKnown || peripheral.name != nil
        )
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            let existing = discovered[index]
            discovered[index] = DiscoveredPeripheral(
                id: entry.id,
                name: entry.name == L10n.Device.unknownName ? existing.name : entry.name,
                rssi: rssi == 0 ? existing.rssi : rssi,
                advertisedServices: services.isEmpty ? existing.advertisedServices : services,
                knownByOS: existing.knownByOS || entry.knownByOS
            )
        } else {
            discovered.append(entry)
        }
    }
}

struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisedServices: [CBUUID]
    var knownByOS: Bool
}

extension HIDCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        log.info("central state -> \(central.state.rawValue, privacy: .public)")
        if central.state == .poweredOn {
            // Must happen before HID services are added.
            central.registerForConnectionEvents(options: nil)
            refreshKnownPeripherals()
        }
        if central.state != .poweredOn {
            isScanning = false
            connected.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        log.info("central willRestoreState: \(dict.keys.sorted(), privacy: .public)")
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restored {
                peripheralCache[peripheral.identifier] = peripheral
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripheralCache[peripheral.identifier] = peripheral
        upsertDiscovered(
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI.intValue
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected.insert(peripheral.identifier)
        log.info("connected: \(peripheral.identifier, privacy: .public)")
        peripheralCache[peripheral.identifier] = peripheral
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connected.remove(peripheral.identifier)
        if let error {
            log.error("disconnected with error: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        } else {
            log.info("disconnected: \(peripheral.identifier, privacy: .public)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error {
            lastError = L10n.ErrorMessage.failedToConnect(error.localizedDescription)
            log.error("failed to connect: \(error.localizedDescription, privacy: .public)")
        }
    }
}
