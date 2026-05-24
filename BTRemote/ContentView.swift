import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
    @EnvironmentObject private var classic: HIDClassicDevice
    @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.classic.rawValue
    #endif
    @State private var dragOffset: CGSize = .zero

    private var classicMode: Bool {
        #if os(macOS)
        return (TransportMode(rawValue: modeRaw) ?? .classic) == .classic
        #else
        return false
        #endif
    }

    var body: some View {
        #if os(macOS)
        NavigationStack {
            form
                .formStyle(.grouped)
                .navigationTitle(L10n.App.title)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 640, idealHeight: 800)
        #else
        NavigationView {
            form.navigationTitle(L10n.App.title)
        }
        .navigationViewStyle(.stack)
        #endif
    }

    private var form: some View {
        Form {
            #if os(macOS)
            transportModeSection
            #endif
            statusSection
            if classicMode {
                #if os(macOS)
                pairedDevicesSection
                #endif
            } else {
                bleControlSection
                bleDevicesSection
            }
            if _isHIDActive {
                keyboardSection
                mouseSection
                consumerSection
                batterySection
            }
            if let lastError = _activeError {
                Section(header: Text(L10n.Section.lastError)) {
                    Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                }
            }
        }
    }

    // transport mode picker (macOS)
    #if os(macOS)
    private var transportModeSection: some View {
        Section(header: Text(L10n.TransportMode.section)) {
            Picker(selection: $modeRaw) {
                Text(L10n.TransportMode.classic).tag(TransportMode.classic.rawValue)
                Text(L10n.TransportMode.ble).tag(TransportMode.ble.rawValue)
            } label: {
                Text(L10n.TransportMode.label)
            }
            .pickerStyle(.segmented)
            Text(classicMode ? L10n.TransportMode.classicHint : L10n.TransportMode.bleHint)
                .font(.caption).foregroundColor(.secondary)
        }
    }
    #endif

    // status
    private var statusSection: some View {
        Section(header: Text(L10n.Section.status)) {
            if classicMode {
                #if os(macOS)
                row(L10n.Status.bluetooth, Text(classic.state.localizedLabel))
                row(L10n.Classic.sdpPublished, Text(classic.isSDPPublished ? L10n.Value.yes : L10n.Value.no))
                row(L10n.Classic.ready, Text(classic.isReady ? L10n.Value.yes : L10n.Value.no))
                row(L10n.Status.hostLEDs, Text(verbatim: classic.keyboardLEDs.localizedLabel))
                #else
                EmptyView()
                #endif
            } else {
                row(L10n.Status.bluetooth, Text(ble.state.localizedLabel))
                row(L10n.Status.advertising, Text(ble.isAdvertising ? L10n.Value.yes : L10n.Value.no))
                row(L10n.Status.hidService, Text(ble.isHIDServiceAdded ? L10n.Status.hidServiceAdded : L10n.Value.none))
                row(L10n.Status.subscribedCentrals, Text(ble.subscribedCentrals.count, format: .number))
                row(L10n.Status.connectedPeripherals, Text(central.connected.count, format: .number))
                row(L10n.Status.hostLEDs, Text(verbatim: ble.keyboardLEDs.localizedLabel))
            }
        }
    }

    // BLE UI
    private var bleControlSection: some View {
        Section {
            if ble.isAdvertising {
                Button(role: .destructive) { ble.stop() } label: {
                    Label(L10n.Action.stopAdvertising, systemImage: "stop.circle")
                }
            } else {
                Button { ble.start() } label: {
                    Label(L10n.Action.startAdvertising, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
    }

    private var bleDevicesSection: some View {
        Section(header: Text(L10n.Section.devices)) {
            row(L10n.Status.central, Text(central.state.localizedLabel))
            if central.isScanning {
                Button(role: .destructive) { central.stopScan() } label: {
                    Label(L10n.Action.stopScanning, systemImage: "stop.circle")
                }
            } else {
                Button { central.startScan() } label: {
                    Label(L10n.Action.scanNearbyDevices, systemImage: "magnifyingglass")
                }
            }
            ForEach(_mergedDevices) { entry in
                deviceRow(entry)
            }
            if _mergedDevices.isEmpty, !central.isScanning {
                Text(L10n.Device.emptyState)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var _mergedDevices: [DeviceEntry] {
        var entries: [UUID: DeviceEntry] = [:]
        for uuid in ble.subscribedCentrals.keys {
            entries[uuid] = DeviceEntry(
                id: uuid,
                name: L10n.Device.unknownName,
                rssi: 0,
                isSubscribed: true,
                isCentralConnected: central.connected.contains(uuid),
                isBlocked: ble.blockedCentrals.contains(uuid)
            )
        }
        for peripheral in central.discovered {
            let isSubscribed = ble.subscribedCentrals[peripheral.id] != nil
            entries[peripheral.id] = DeviceEntry(
                id: peripheral.id,
                name: peripheral.name,
                rssi: peripheral.rssi,
                isSubscribed: isSubscribed,
                isCentralConnected: central.connected.contains(peripheral.id),
                isBlocked: ble.blockedCentrals.contains(peripheral.id)
            )
        }
        return entries.values.sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @ViewBuilder
    private func deviceRow(_ entry: DeviceEntry) -> some View {
        Button {
            if entry.isCentralConnected {
                central.disconnect(entry.id)
            } else if entry.isSubscribed {
                ble.toggleBlocked(entry.id)
            } else {
                central.connect(entry.id)
            }
        } label: {
            HStack {
                Image(systemName: entry.iconName)
                    .foregroundColor(entry.iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.name).foregroundColor(.primary)
                    Text(verbatim: entry.id.uuidString)
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if entry.rssi != 0 {
                    Text(verbatim: L10n.Device.rssi(entry.rssi))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .accessibilityLabel(
            Text(
                verbatim: entry.isLive
                    ? L10n.Device.disconnectAccessibilityLabel(entry.name)
                    : L10n.Device.connectAccessibilityLabel(entry.name)
            )
        )
    }

    // classic UI
    #if os(macOS)
    private var pairedDevicesSection: some View {
        Section(header: Text(L10n.Classic.pairedDevicesSection)) {
            Text(L10n.Classic.pairFromSystemSettings)
                .font(.caption).foregroundColor(.secondary)
            Button {
                _ = classic.presentPairingPicker()
            } label: {
                Label(L10n.Classic.pairNewDevice, systemImage: "plus.circle")
            }
            Button { classic.refreshPairedDevices() } label: {
                Label(L10n.Classic.refresh, systemImage: "arrow.clockwise")
            }
            ForEach(classic.pairedDevices) { peer in
                pairedDeviceRow(peer)
            }
            if classic.pairedDevices.isEmpty {
                Text(L10n.Classic.noPairedDevices)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .onAppear { classic.refreshPairedDevices() }
    }

    @ViewBuilder
    private func pairedDeviceRow(_ peer: HIDClassicDevice.PairedDevice) -> some View {
        let isLive = classic.connectedAddress == peer.id
        HStack {
            Button {
                if isLive {
                    classic.disconnect()
                } else {
                    classic.connect(to: peer)
                }
            } label: {
                HStack {
                    Image(systemName: isLive ? "link.circle.fill" : "link.circle")
                        .foregroundColor(isLive ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: peer.name).foregroundColor(.primary)
                        Text(verbatim: peer.id)
                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(isLive ? L10n.Classic.disconnect : L10n.Classic.connect)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            Button(role: .destructive) { classic.forgetDevice(id: peer.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
    #endif

    // input section (common)
    private var keyboardSection: some View {
        Section(header: Text(L10n.Section.keyboard)) {
            Button(L10n.Keyboard.typeHello) { Task { await typeWord("hello") } }
            Button(L10n.Keyboard.pressReturn) { tap(.return) }
            Button(L10n.Keyboard.pressEscape) { tap(.escape) }
        }
    }

    private var mouseSection: some View {
        Section(header: Text(L10n.Section.mouse)) {
            Color.secondary.opacity(0.15)
                .frame(height: 200)
                .overlay(Text(L10n.Mouse.dragToMovePointer).foregroundColor(.secondary))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dx = clampInt8(value.translation.width - dragOffset.width)
                            let dy = clampInt8(value.translation.height - dragOffset.height)
                            dragOffset = value.translation
                            _sendMouse(MouseReport(dX: dx, dY: dy))
                        }
                        .onEnded { _ in
                            dragOffset = .zero
                            _sendMouse(.zero)
                        }
                )
            HStack {
                Button(L10n.Mouse.leftButton) { click(.left) }
                Button(L10n.Mouse.middleButton) { click(.middle) }
                Button(L10n.Mouse.rightButton) { click(.right) }
            }
            .buttonStyle(.bordered)
            HStack {
                Button(L10n.Mouse.wheelUp) { _sendMouse(MouseReport(wheel: 4)); _sendMouse(.zero) }
                Button(L10n.Mouse.wheelDown) { _sendMouse(MouseReport(wheel: -4)); _sendMouse(.zero) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var consumerSection: some View {
        Section(header: Text(L10n.Section.media)) {
            HStack {
                Button { tap(consumer: .scanPrev) } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel(L10n.Media.previousTrack)
                Button { tap(consumer: .playPause) } label: { Image(systemName: "playpause.fill") }
                    .accessibilityLabel(L10n.Media.playPause)
                Button { tap(consumer: .scanNext) } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel(L10n.Media.nextTrack)
            }
            .buttonStyle(.bordered)
            HStack {
                Button { tap(consumer: .mute) } label: { Image(systemName: "speaker.slash.fill") }
                    .accessibilityLabel(L10n.Media.mute)
                Button { tap(consumer: .volumeDown) } label: { Image(systemName: "speaker.wave.1.fill") }
                    .accessibilityLabel(L10n.Media.volumeDown)
                Button { tap(consumer: .volumeUp) } label: { Image(systemName: "speaker.wave.3.fill") }
                    .accessibilityLabel(L10n.Media.volumeUp)
            }
            .buttonStyle(.bordered)
        }
    }

    private var batterySection: some View {
        Section(header: Text(L10n.Section.battery)) {
            Slider(
                value: Binding(
                    get: { Double(_batteryLevel) },
                    set: { _updateBatteryLevel(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            row(L10n.Battery.level, Text(Double(_batteryLevel) / 100, format: .percent.precision(.fractionLength(0))))
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
    }

    // active backend adaptors
    private var _isHIDActive: Bool {
        if classicMode {
            #if os(macOS)
            return classic.isSDPPublished
            #else
            return false
            #endif
        }
        return ble.isHIDServiceAdded
    }

    private var _activeError: String? {
        if classicMode {
            #if os(macOS)
            return classic.lastError
            #else
            return nil
            #endif
        }
        return ble.lastError ?? central.lastError
    }

    private var _batteryLevel: UInt8 {
        if classicMode {
            #if os(macOS)
            return classic.batteryLevel
            #else
            return 100
            #endif
        }
        return ble.batteryLevel
    }

    private func _sendMouse(_ report: MouseReport) {
        if classicMode {
            #if os(macOS)
            classic.sendMouse(report)
            #endif
        } else {
            ble.sendMouse(report)
        }
    }

    private func _sendKeyboard(_ report: KeyboardReport) {
        if classicMode {
            #if os(macOS)
            classic.sendKeyboard(report)
            #endif
        } else {
            ble.sendKeyboard(report)
        }
    }

    private func _sendConsumer(_ report: ConsumerReport) {
        if classicMode {
            #if os(macOS)
            classic.sendConsumer(report)
            #endif
        } else {
            ble.sendConsumer(report)
        }
    }

    private func _updateBatteryLevel(_ level: UInt8) {
        if classicMode {
            #if os(macOS)
            classic.updateBatteryLevel(level)
            #endif
        } else {
            ble.updateBatteryLevel(level)
        }
    }

    // input helpers
    private func tap(_ key: Keycode, modifiers: KeyboardModifiers = []) {
        _sendKeyboard(KeyboardReport(modifiers: modifiers, keys: [key]))
        _sendKeyboard(.zero)
    }

    private func tap(consumer: ConsumerKey) {
        _sendConsumer(ConsumerReport(key: consumer))
        _sendConsumer(.zero)
    }

    private func click(_ button: MouseButtons) {
        _sendMouse(MouseReport(buttons: button))
        _sendMouse(.zero)
    }

    private func typeWord(_ text: String) async {
        for character in text {
            if let (key, mods) = mapASCII(character) {
                _sendKeyboard(KeyboardReport(modifiers: mods, keys: [key]))
                try? await Task.sleep(nanoseconds: 20_000_000)
                _sendKeyboard(.zero)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    private func clampInt8(_ value: CGFloat) -> Int8 {
        Int8(max(-127, min(127, Int(value))))
    }
}

private struct DeviceEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isSubscribed: Bool
    let isCentralConnected: Bool
    let isBlocked: Bool

    var isLive: Bool { (isSubscribed && !isBlocked) || isCentralConnected }

    var iconName: String {
        if isBlocked { return "link.circle" }
        return isLive ? "link.circle.fill" : "link.circle"
    }

    var iconColor: Color {
        if isBlocked { return .secondary }
        return isLive ? .green : .accentColor
    }
}

// ASCII to keycode/modifier mapping
private func mapASCII(_ character: Character) -> (Keycode, KeyboardModifiers)? {
    let scalar = character.unicodeScalars.first?.value ?? 0
    switch scalar {
    case 0x61 ... 0x7A: // a..z
        let key = Keycode(rawValue: 0x04 + UInt8(scalar - 0x61))
        return key.map { ($0, []) }
    case 0x41 ... 0x5A: // A..Z
        let key = Keycode(rawValue: 0x04 + UInt8(scalar - 0x41))
        return key.map { ($0, .leftShift) }
    case 0x31 ... 0x39: // 1..9
        let key = Keycode(rawValue: 0x1E + UInt8(scalar - 0x31))
        return key.map { ($0, []) }
    case 0x30: return (.digit0, [])
    case 0x20: return (.space, [])
    case 0x0A: return (.return, [])
    case 0x2E: return (.period, [])
    case 0x2C: return (.comma, [])
    case 0x2D: return (.minus, [])
    case 0x3D: return (.equal, [])
    case 0x2F: return (.slash, [])
    default: return nil
    }
}

private extension CBManagerState {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .unknown: return L10n.BluetoothState.unknown
        case .resetting: return L10n.BluetoothState.resetting
        case .unsupported: return L10n.BluetoothState.unsupported
        case .unauthorized: return L10n.BluetoothState.unauthorized
        case .poweredOff: return L10n.BluetoothState.poweredOff
        case .poweredOn: return L10n.BluetoothState.poweredOn
        @unknown default: return L10n.BluetoothState.unavailable
        }
    }
}

#if os(macOS)
private extension HIDClassicDevice.ControllerState {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .unknown: return L10n.BluetoothState.unknown
        case .poweredOff: return L10n.BluetoothState.poweredOff
        case .poweredOn: return L10n.BluetoothState.poweredOn
        }
    }
}
#endif

private extension KeyboardLEDs {
    var localizedLabel: String {
        var parts: [String] = []
        if contains(.numLock) { parts.append(L10n.KeyboardLED.numLock) }
        if contains(.capsLock) { parts.append(L10n.KeyboardLED.capsLock) }
        if contains(.scrollLock) { parts.append(L10n.KeyboardLED.scrollLock) }
        return parts.isEmpty ? L10n.Value.noneString : ListFormatter.localizedString(byJoining: parts)
    }
}

#if DEBUG
#Preview {
    #if os(iOS)
    ContentView()
        .environmentObject(HIDPeripheral())
        .environmentObject(HIDCentral())
    #else
    ContentView()
        .environmentObject(HIDPeripheral())
        .environmentObject(HIDCentral())
        .environmentObject(HIDClassicDevice())
    #endif
}
#endif
