import CoreBluetooth
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var ble: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.classic.rawValue
        @StateObject private var directInput = DirectInputController()
    #endif
    @State private var dragOffset: CGSize = .zero

    private var classicMode: Bool {
        #if os(macOS)
            return (TransportMode(rawValue: modeRaw) ?? .classic) == .classic
        #else
            return false
        #endif
    }

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(ble: ble, central: central, classic: classic, classicMode: classicMode)
        #else
            return HIDInput.make(ble: ble, central: central)
        #endif
    }

    var body: some View {
        #if os(macOS)
            NavigationStack {
                form
                    .formStyle(.grouped)
                    .navigationTitle(L10n.App.title)
            }
            .onDisappear { directInput.stop() }
            .onChange(of: hid.isActive) { isActive in
                if !isActive { directInput.stop() }
            }
        #else
            NavigationView {
                form.navigationTitle(L10n.App.title)
            }
            .navigationViewStyle(.stack)
        #endif
    }

    private var form: some View {
        Form {
            guidanceSection
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
            if hid.isActive {
                #if os(macOS)
                    directInputSection
                #endif
                keyboardSection
                mouseSection
                consumerSection
                batterySection
            }
            if let lastError = hid.activeError {
                Section(header: Text(L10n.Section.lastError)) {
                    Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                }
            }
        }
    }

    private var guidanceSection: some View {
        Section(header: Text(L10n.Setup.howTo)) {
            guidanceStep("1.circle", L10n.Setup.step1)
            guidanceStep("2.circle", L10n.Setup.step2)
            guidanceStep("3.circle", L10n.Setup.step3)
        }
    }

    private func guidanceStep(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon) }
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

    /// status
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

    /// BLE UI
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

    #if os(macOS)
        private var directInputSection: some View {
            Section(header: Text(L10n.DirectInput.section)) {
                Toggle(isOn: directInputBinding) {
                    Label(L10n.DirectInput.toggle, systemImage: "rectangle.and.hand.point.up.left")
                }
                Text(L10n.DirectInput.releaseHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let lastError = directInput.lastError {
                    Text(verbatim: lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }

        private var directInputBinding: Binding<Bool> {
            Binding(
                get: { directInput.isCapturing },
                set: { shouldCapture in
                    if shouldCapture {
                        let input = hid
                        directInput.start(
                            sendKeyboard: input.sendKeyboard,
                            sendMouse: input.sendMouse,
                            onRelease: {}
                        )
                    } else {
                        directInput.stop()
                    }
                }
            )
        }
    #endif

    /// input section (common)
    private var keyboardSection: some View {
        Section(header: Text(L10n.Section.keyboard)) {
            Button(L10n.Keyboard.typeHello) { Task { await hid.typeWord("hello") } }
            Button(L10n.Keyboard.pressReturn) { hid.tap(.return) }
            Button(L10n.Keyboard.pressEscape) { hid.tap(.escape) }
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
                            let dx = HIDInput.clamp(value.translation.width - dragOffset.width)
                            let dy = HIDInput.clamp(value.translation.height - dragOffset.height)
                            dragOffset = value.translation
                            hid.move(dx: dx, dy: dy)
                        }
                        .onEnded { _ in
                            dragOffset = .zero
                            hid.sendMouse(.zero)
                        }
                )
            HStack {
                Button(L10n.Mouse.leftButton) { hid.click(.left) }
                Button(L10n.Mouse.middleButton) { hid.click(.middle) }
                Button(L10n.Mouse.rightButton) { hid.click(.right) }
            }
            .buttonStyle(.bordered)
            HStack {
                Button(L10n.Mouse.wheelUp) { hid.scroll(4) }
                Button(L10n.Mouse.wheelDown) { hid.scroll(-4) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var consumerSection: some View {
        Section(header: Text(L10n.Section.media)) {
            HStack {
                Button { hid.tap(consumer: .scanPrev) } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel(L10n.Media.previousTrack)
                Button { hid.tap(consumer: .playPause) } label: { Image(systemName: "playpause.fill") }
                    .accessibilityLabel(L10n.Media.playPause)
                Button { hid.tap(consumer: .scanNext) } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel(L10n.Media.nextTrack)
            }
            .buttonStyle(.bordered)
            HStack {
                Button { hid.tap(consumer: .mute) } label: { Image(systemName: "speaker.slash.fill") }
                    .accessibilityLabel(L10n.Media.mute)
                Button { hid.tap(consumer: .volumeDown) } label: { Image(systemName: "speaker.wave.1.fill") }
                    .accessibilityLabel(L10n.Media.volumeDown)
                Button { hid.tap(consumer: .volumeUp) } label: { Image(systemName: "speaker.wave.3.fill") }
                    .accessibilityLabel(L10n.Media.volumeUp)
            }
            .buttonStyle(.bordered)
        }
    }

    private var batterySection: some View {
        Section(header: Text(L10n.Section.battery)) {
            Slider(
                value: Binding(
                    get: { Double(hid.batteryLevel) },
                    set: { hid.updateBattery(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            row(L10n.Battery.level, Text(Double(hid.batteryLevel) / 100, format: .percent.precision(.fractionLength(0))))
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
    }
}

private struct DeviceEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isSubscribed: Bool
    let isCentralConnected: Bool
    let isBlocked: Bool

    var isLive: Bool {
        (isSubscribed && !isBlocked) || isCentralConnected
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
            case .unknown: L10n.BluetoothState.unknown
            case .poweredOff: L10n.BluetoothState.poweredOff
            case .poweredOn: L10n.BluetoothState.poweredOn
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
            SetupView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
        #else
            SetupView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
