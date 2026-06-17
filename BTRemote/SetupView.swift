import CoreBluetooth
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.defaultMode.rawValue
        @StateObject private var directInput = DirectInputController()
    #endif

    private var classicMode: Bool {
        #if os(macOS)
            return (TransportMode(rawValue: modeRaw) ?? .defaultMode) == .classic
        #else
            return false
        #endif
    }

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: classicMode)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
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
            guideSection
            #if os(macOS)
                transportModeSection
            #endif
            if classicMode {
                #if os(macOS)
                    pairedDevicesSection
                #endif
            } else {
                connectionSection
            }
            statusSection
            #if os(macOS)
                if hid.isActive { directInputSection }
            #endif
            if let lastError = hid.activeError {
                Section(header: Text(L10n.Section.lastError)) {
                    Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                }
            }
        }
    }

    private var guideSection: some View {
        Section(header: Text(L10n.Setup.guide)) {
            NavigationLink { GuideView(transport: .lowEnergy) } label: {
                Label(L10n.Setup.lowEnergyGuide, systemImage: "questionmark.circle")
            }
            #if os(macOS)
                NavigationLink { GuideView(transport: .classic) } label: {
                    Label(L10n.Setup.classicGuide, systemImage: "questionmark.circle")
                }
            #endif
        }
    }

    #if os(macOS)
        private var transportModeSection: some View {
            Section {
                Picker(selection: $modeRaw) {
                    Text(L10n.TransportMode.lowEnergy).tag(TransportMode.lowEnergy.rawValue)
                    Text(L10n.TransportMode.classic).tag(TransportMode.classic.rawValue)
                } label: {
                    Text(L10n.TransportMode.label)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.TransportMode.section)
            } footer: {
                Text(classicMode ? L10n.TransportMode.classicCompatibility : L10n.TransportMode.lowEnergyCompatibility)
            }
        }
    #endif

    private var statusSection: some View {
        Section(header: Text(L10n.Section.status)) {
            if classicMode {
                #if os(macOS)
                    row(L10n.Status.bluetooth, Text(classic.state.localizedLabel))
                    row(L10n.Classic.ready, Text(classic.isReady ? L10n.Value.yes : L10n.Value.no))
                    if developerMode {
                        row(L10n.Classic.sdpPublished, Text(classic.isSDPPublished ? L10n.Value.yes : L10n.Value.no))
                        row(L10n.Status.hostLEDs, Text(verbatim: classic.keyboardLEDs.localizedLabel))
                    }
                #else
                    EmptyView()
                #endif
            } else {
                row(L10n.Status.bluetooth, Text(lowEnergy.state.localizedLabel))
                row(L10n.Status.advertising, Text(lowEnergy.isAdvertising ? L10n.Value.yes : L10n.Value.no))
                if developerMode {
                    row(L10n.Status.hidService, Text(lowEnergy.isHIDServiceAdded ? L10n.Status.hidServiceAdded : L10n.Value.none))
                    row(L10n.Status.subscribedCentrals, Text(lowEnergy.subscribedCentrals.count, format: .number))
                    row(L10n.Status.connectedPeripherals, Text(central.connected.count, format: .number))
                    row(L10n.Status.hostLEDs, Text(verbatim: lowEnergy.keyboardLEDs.localizedLabel))
                }
            }
        }
    }

    private var connectionSection: some View {
        Section(header: Text(L10n.Section.connection)) {
            if lowEnergy.isAdvertising {
                Button(role: .destructive) { lowEnergy.stop() } label: {
                    Label(L10n.Action.stopAdvertising, systemImage: "stop.circle")
                }
            } else {
                Button { lowEnergy.start() } label: {
                    Label(L10n.Action.startAdvertising, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            NavigationLink {
                DeviceListView()
            } label: {
                Label(L10n.Section.devices, systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

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

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
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
