import SwiftUI

struct GuideView: View {
    enum Transport {
        case lowEnergy
        case classic
    }

    let transport: Transport

    var body: some View {
        Form {
            switch transport {
            case .lowEnergy:
                Section(header: Text(L10n.Setup.fromDevice), footer: Text(troubleshooting)) {
                    step("1.circle", L10n.Setup.fromDeviceStep1)
                    step("2.circle", L10n.Setup.fromDeviceStep2)
                    step("3.circle", L10n.Setup.fromDeviceStep3)
                }
                Section(header: Text(L10n.Setup.fromApp), footer: fromAppFooter) {
                    step("1.circle", L10n.Setup.fromAppStep1)
                    step("2.circle", L10n.Setup.fromAppStep2)
                }
            case .classic:
                Section(footer: footer) {
                    step("1.circle", L10n.Setup.classicStep1)
                    step("2.circle", L10n.Setup.classicStep2)
                    step("3.circle", L10n.Setup.classicStep3)
                }
            }
        }
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
                transportInfo
            #endif
            Text(troubleshooting)
        }
    }

    @ViewBuilder private var fromAppFooter: some View {
        #if os(macOS)
            transportInfo
        #endif
    }

    private var title: LocalizedStringKey {
        switch transport {
        case .lowEnergy: L10n.Setup.lowEnergyGuide
        case .classic: L10n.Setup.classicGuide
        }
    }

    #if os(macOS)
        private var about: LocalizedStringKey {
            switch transport {
            case .lowEnergy: L10n.TransportMode.lowEnergyAbout
            case .classic: L10n.TransportMode.classicAbout
            }
        }

        private var compatibility: LocalizedStringKey {
            switch transport {
            case .lowEnergy: L10n.TransportMode.lowEnergyCompatibility
            case .classic: L10n.TransportMode.classicCompatibility
            }
        }

        private var transportInfo: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(about)
                Text(compatibility)
            }
        }
    #endif

    private var troubleshooting: LocalizedStringKey {
        switch transport {
        case .lowEnergy: L10n.Setup.troubleshooting
        case .classic: L10n.Setup.classicTroubleshooting
        }
    }

    private func step(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon) }
    }
}
