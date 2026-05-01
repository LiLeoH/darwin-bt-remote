import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        NavigationView {
            Form {
                statusSection
                controlSection
                devicesSection
                if ble.isHIDServiceAdded {
                    keyboardSection
                    mouseSection
                    consumerSection
                    batterySection
                }
                if let lastError = ble.lastError ?? central.lastError {
                    Section(header: Text(L10n.Section.lastError)) {
                        Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(L10n.App.title)
        }
        .navigationViewStyle(.stack)
    }

    private var statusSection: some View {
        Section(header: Text(L10n.Section.status)) {
            row(L10n.Status.bluetooth, Text(ble.state.localizedLabel))
            row(L10n.Status.advertising, Text(ble.isAdvertising ? L10n.Value.yes : L10n.Value.no))
            row(L10n.Status.hidService, Text(ble.isHIDServiceAdded ? L10n.Status.hidServiceAdded : L10n.Value.none))
            row(L10n.Status.subscribedCentrals, Text(ble.subscribedCentrals.count, format: .number))
            row(L10n.Status.connectedPeripherals, Text(central.connected.count, format: .number))
            row(L10n.Status.hostLEDs, Text(verbatim: ble.keyboardLEDs.localizedLabel))
        }
    }

    private var controlSection: some View {
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

    private var devicesSection: some View {
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
            ForEach(central.discovered) { peripheral in
                deviceRow(peripheral)
            }
            if central.discovered.isEmpty, !central.isScanning {
                Text(L10n.Device.emptyState)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ peripheral: DiscoveredPeripheral) -> some View {
        let isConnected = central.connected.contains(peripheral.id)
        Button {
            if isConnected {
                central.disconnect(peripheral.id)
            } else {
                central.connect(peripheral.id)
            }
        } label: {
            HStack {
                Image(systemName: isConnected ? "link.circle.fill" : "link.circle")
                    .foregroundColor(isConnected ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: peripheral.name).foregroundColor(.primary)
                    Text(verbatim: peripheral.id.uuidString)
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if peripheral.rssi != 0 {
                    Text(verbatim: L10n.Device.rssi(peripheral.rssi))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .accessibilityLabel(
            Text(
                verbatim: isConnected
                    ? L10n.Device.disconnectAccessibilityLabel(peripheral.name)
                    : L10n.Device.connectAccessibilityLabel(peripheral.name)
            )
        )
    }

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
                            ble.sendMouse(MouseReport(dX: dx, dY: dy))
                        }
                        .onEnded { _ in
                            dragOffset = .zero
                            ble.sendMouse(.zero)
                        }
                )
            HStack {
                Button(L10n.Mouse.leftButton) { click(.left) }
                Button(L10n.Mouse.middleButton) { click(.middle) }
                Button(L10n.Mouse.rightButton) { click(.right) }
            }
            .buttonStyle(.bordered)
            HStack {
                Button(L10n.Mouse.wheelUp) { ble.sendMouse(MouseReport(wheel: 4)); ble.sendMouse(.zero) }
                Button(L10n.Mouse.wheelDown) { ble.sendMouse(MouseReport(wheel: -4)); ble.sendMouse(.zero) }
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
                    get: { Double(ble.batteryLevel) },
                    set: { ble.updateBatteryLevel(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            row(L10n.Battery.level, Text(Double(ble.batteryLevel) / 100, format: .percent.precision(.fractionLength(0))))
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
    }

    // input helpers

    private func tap(_ key: Keycode, modifiers: KeyboardModifiers = []) {
        ble.sendKeyboard(KeyboardReport(modifiers: modifiers, keys: [key]))
        ble.sendKeyboard(.zero)
    }

    private func tap(consumer: ConsumerKey) {
        ble.sendConsumer(ConsumerReport(key: consumer))
        ble.sendConsumer(.zero)
    }

    private func click(_ button: MouseButtons) {
        ble.sendMouse(MouseReport(buttons: button))
        ble.sendMouse(.zero)
    }

    private func typeWord(_ text: String) async {
        for character in text {
            if let (key, mods) = mapASCII(character) {
                ble.sendKeyboard(KeyboardReport(modifiers: mods, keys: [key]))
                try? await Task.sleep(nanoseconds: 20_000_000)
                ble.sendKeyboard(.zero)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    private func clampInt8(_ value: CGFloat) -> Int8 {
        Int8(max(-127, min(127, Int(value))))
    }
}

/// ASCII to Keycode/Modifier mapping
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

private extension KeyboardLEDs {
    var localizedLabel: String {
        var parts: [String] = []
        if contains(.numLock) { parts.append(L10n.KeyboardLED.numLock) }
        if contains(.capsLock) { parts.append(L10n.KeyboardLED.capsLock) }
        if contains(.scrollLock) { parts.append(L10n.KeyboardLED.scrollLock) }
        return parts.isEmpty ? L10n.Value.noneString : ListFormatter.localizedString(byJoining: parts)
    }
}

#Preview {
    ContentView()
        .environmentObject(HIDPeripheral())
        .environmentObject(HIDCentral())
}
