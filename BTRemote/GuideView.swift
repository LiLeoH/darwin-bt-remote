import SwiftUI

struct GuideView: View {
    var body: some View {
        Form {
            Section(header: Text(L10n.Setup.fromApp)) {
                step("1.circle", L10n.Setup.fromAppStep1)
                step("2.circle", L10n.Setup.fromAppStep2)
            }
            Section(header: Text(L10n.Setup.fromDevice), footer: Text(L10n.Setup.troubleshooting)) {
                step("1.circle", L10n.Setup.fromDeviceStep1)
                step("2.circle", L10n.Setup.fromDeviceStep2)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(L10n.Setup.howToConnect)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func step(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon) }
    }
}
