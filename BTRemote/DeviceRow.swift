import CoreBluetooth
import SwiftUI

/// one device line shared by the connected-hosts list (peripheral role) and the scan list (central role)
struct DeviceRow<Trailing: View>: View {
    let entry: DeviceEntry
    var accessibilityLabel: String? = nil
    let action: () -> Void
    let onInfo: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Button(action: action) {
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
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(verbatim: accessibilityLabel ?? entry.displayName))

            Button(action: onInfo) {
                Image(systemName: "info.circle").foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.DeviceInfo.info)
        }
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
