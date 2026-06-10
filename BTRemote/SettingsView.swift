import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    #if os(iOS)
        @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = true
    #endif

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
        SettingsView()
    }
#endif
