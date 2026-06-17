import CoreBluetooth
import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    @State private var selectedInfo: DeviceEntry?

    var body: some View {
        Form {
            Section {
                if central.isScanning {
                    Button(role: .destructive) { central.stopScan() } label: {
                        Label(L10n.Action.stopScanning, systemImage: "stop.circle")
                    }
                } else {
                    Button { central.startScan() } label: {
                        Label(L10n.Action.scanNearbyDevices, systemImage: "magnifyingglass")
                    }
                }
            }
            if !_connectedHosts.isEmpty {
                Section(header: Text(L10n.Section.connectedDevices)) {
                    ForEach(_connectedHosts) { hostRow($0) }
                }
            }
            Section(header: Text(L10n.Section.nearby)) {
                ForEach(_nearbyDevices) { nearbyRow($0) }
                if _nearbyDevices.isEmpty, !central.isScanning {
                    Text(L10n.Device.emptyState)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(L10n.Section.devices)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .sheet(item: $selectedInfo) { DeviceInfoView(entry: $0) }
            .onAppear { central.startScan() }
            .onDisappear { central.stopScan() }
    }

    /// hosts that connected to us (peripheral role)
    private var _connectedHosts: [DeviceEntry] {
        lowEnergy.connectedCentrals
            .map { uuid in
                DeviceEntry(
                    id: uuid,
                    name: L10n.Device.connectedHostName,
                    isNamed: true,
                    rssi: 0,
                    advertisedServices: [],
                    companyID: nil,
                    txPower: nil,
                    isConnectable: nil,
                    isHostConnected: true,
                    isCentralConnected: false,
                    isBlocked: lowEnergy.blockedCentrals.contains(uuid)
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// peripherals found by scanning (central role)
    private var _nearbyDevices: [DeviceEntry] {
        central.discovered
            .map { peripheral in
                DeviceEntry(
                    id: peripheral.id,
                    name: peripheral.name,
                    isNamed: peripheral.isNamed,
                    rssi: peripheral.rssi,
                    advertisedServices: peripheral.advertisedServices,
                    companyID: peripheral.companyID,
                    txPower: peripheral.txPower,
                    isConnectable: peripheral.isConnectable,
                    isHostConnected: false,
                    isCentralConnected: central.connected.contains(peripheral.id),
                    isBlocked: false
                )
            }
            .sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func hostRow(_ entry: DeviceEntry) -> some View {
        HStack {
            Button { lowEnergy.toggleBlocked(entry.id) } label: {
                row(entry) {
                    if entry.isBlocked {
                        Text(L10n.Device.muted).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            infoButton(entry)
        }
    }

    private func nearbyRow(_ entry: DeviceEntry) -> some View {
        HStack {
            Button {
                if entry.isCentralConnected {
                    central.disconnect(entry.id)
                } else {
                    central.connect(entry.id)
                }
            } label: {
                row(entry) {
                    if entry.rssi != 0 {
                        Text(verbatim: L10n.Device.rssi(entry.rssi)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                Text(
                    verbatim: entry.isLive
                        ? L10n.Device.disconnectAccessibilityLabel(entry.displayName)
                        : L10n.Device.connectAccessibilityLabel(entry.displayName)
                )
            )
            infoButton(entry)
        }
    }

    private func infoButton(_ entry: DeviceEntry) -> some View {
        Button { selectedInfo = entry } label: {
            Image(systemName: "info.circle").foregroundColor(.accentColor)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L10n.DeviceInfo.info)
    }

    private func row(_ entry: DeviceEntry, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Image(systemName: entry.iconName)
                .foregroundColor(entry.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.displayName).foregroundColor(.primary)
                Text(verbatim: entry.id.uuidString)
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            trailing()
        }
        .contentShape(Rectangle())
    }
}

struct DeviceEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isNamed: Bool
    let rssi: Int
    let advertisedServices: [CBUUID]
    let companyID: UInt16?
    let txPower: Int?
    let isConnectable: Bool?
    let isHostConnected: Bool
    let isCentralConnected: Bool
    let isBlocked: Bool

    var isLive: Bool {
        isCentralConnected || (isHostConnected && !isBlocked)
    }

    var manufacturer: String? {
        companyID.flatMap { BluetoothNumbers.company($0) }
    }

    var displayName: String {
        if isNamed { return name }
        if let manufacturer { return "[\(manufacturer)]" }
        return name
    }

    var iconName: String {
        if isBlocked { return "link.circle" }
        return isLive ? "link.circle.fill" : "link.circle"
    }

    var iconColor: Color {
        if isBlocked { return .secondary }
        return isLive ? .green : .accentColor
    }
}

#if DEBUG
    #Preview {
        DeviceListView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
    }
#endif
