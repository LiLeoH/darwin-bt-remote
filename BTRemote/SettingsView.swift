import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @Environment(\.macTransport) private var macTransport
    #endif
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    #if os(iOS)
        @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = true
    #endif

    private let sourceCodeURL = URL(string: "https://github.com/jqssun/darwin-bt-remote")!

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: macTransport == .classic)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
        #endif
    }

    var body: some View {
        #if os(macOS)
            NavigationStack {
                form
                    .formStyle(.grouped)
                    .navigationTitle(L10n.Tab.settings)
            }
        #else
            NavigationView {
                form.navigationTitle(L10n.Tab.settings)
            }
            .navigationViewStyle(.stack)
        #endif
    }

    private var form: some View {
        Form {
            Section(header: Text(L10n.Settings.trackpad)) {
                sensitivityRow(L10n.Settings.trackingSpeed, value: $touchpadSensitivity, range: AppSettings.pointerSensitivityRange)
                sensitivityRow(L10n.Settings.scrollSpeed, value: $scrollSensitivity, range: AppSettings.scrollSensitivityRange)
            }
            #if os(iOS)
                Section(header: Text(L10n.Settings.connection), footer: Text(L10n.Settings.autoAdvertiseHint)) {
                    Toggle(L10n.Settings.autoAdvertise, isOn: $autoAdvertise)
                }
            #endif
            Section(header: Text(L10n.Settings.advanced)) {
                Toggle(L10n.Settings.developerMode, isOn: $developerMode)
                Link(destination: sourceCodeURL) {
                    Label(L10n.Settings.sourceCode, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if developerMode, hid.isActive { batterySection }
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
            HStack {
                Text(L10n.Battery.level)
                Spacer()
                Text(Double(hid.batteryLevel) / 100, format: .percent.precision(.fractionLength(0)))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sensitivityRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .foregroundColor(.secondary)
                    + Text(verbatim: "×").foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }
}

#if DEBUG
    #Preview {
        #if os(iOS)
            SettingsView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
        #else
            SettingsView()
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
