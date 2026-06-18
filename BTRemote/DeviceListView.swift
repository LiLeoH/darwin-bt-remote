import CoreBluetooth
import SwiftUI

struct DeviceListView: View {
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
            Section {
                ForEach(_devices) { deviceRow($0) }
                if _devices.isEmpty, !central.isScanning {
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

    /// peripherals found by scanning (central role)
    private var _devices: [DeviceEntry] {
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

    private func deviceRow(_ entry: DeviceEntry) -> some View {
        DeviceRow(
            entry: entry,
            accessibilityLabel: entry.isLive
                ? L10n.Device.disconnectAccessibilityLabel(entry.displayName)
                : L10n.Device.connectAccessibilityLabel(entry.displayName),
            action: {
                if entry.isCentralConnected {
                    central.disconnect(entry.id)
                } else {
                    central.connect(entry.id)
                }
            },
            onInfo: { selectedInfo = entry }
        ) {
            if entry.rssi != 0 {
                Text(verbatim: L10n.Device.rssi(entry.rssi)).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        DeviceListView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
    }
#endif
