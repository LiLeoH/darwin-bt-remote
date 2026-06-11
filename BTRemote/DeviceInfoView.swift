import CoreBluetooth
import SwiftUI

struct DeviceInfoView: View {
    let entry: DeviceEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
            NavigationStack { content.formStyle(.grouped) }
        #else
            NavigationView { content }
                .navigationViewStyle(.stack)
        #endif
    }

    private var content: some View {
        Form {
            Section(header: Text(L10n.DeviceInfo.device)) {
                infoRow(L10n.DeviceInfo.name, Text(verbatim: entry.displayName))
                infoRow(L10n.DeviceInfo.identifier, Text(verbatim: entry.id.uuidString))
            }
            Section(header: Text(L10n.DeviceInfo.manufacturer)) {
                if let manufacturer = entry.manufacturer {
                    Text(verbatim: manufacturer)
                } else {
                    Text(L10n.Value.none).foregroundColor(.secondary)
                }
            }
            if hasAdvertisement {
                Section(header: Text(L10n.DeviceInfo.advertisement)) {
                    if entry.rssi != 0 {
                        infoRow(L10n.DeviceInfo.signal, Text(verbatim: L10n.Device.rssi(entry.rssi)))
                    }
                    if let isConnectable = entry.isConnectable {
                        infoRow(L10n.DeviceInfo.connectable, Text(isConnectable ? L10n.Value.yes : L10n.Value.no))
                    }
                    if let txPower = entry.txPower {
                        infoRow(L10n.DeviceInfo.txPower, Text(verbatim: "\(txPower) dBm"))
                    }
                }
            }
            if !entry.advertisedServices.isEmpty {
                Section(header: Text(L10n.DeviceInfo.services)) {
                    ForEach(entry.advertisedServices, id: \.self) { serviceRow($0) }
                }
            }
        }
        .navigationTitle(L10n.DeviceInfo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.DeviceInfo.done) { dismiss() }
                }
            }
    }

    private var hasAdvertisement: Bool {
        entry.rssi != 0 || entry.isConnectable != nil || entry.txPower != nil
    }

    @ViewBuilder
    private func serviceRow(_ uuid: CBUUID) -> some View {
        if let name = BluetoothNumbers.service(uuid) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                Text(verbatim: uuid.uuidString).font(.caption2).foregroundColor(.secondary)
            }
        } else {
            Text(verbatim: uuid.uuidString)
        }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(label)
            Spacer()
            value.foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
