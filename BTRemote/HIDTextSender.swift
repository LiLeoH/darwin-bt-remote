import SwiftUI

/// Shared "type text -> stream as HID keyboard reports" editor.
///
/// Used by both the Keyboard tab and the menu-bar popover so the two surfaces
/// behave identically: characters are mirrored into the local field and streamed to
/// the host as paced key reports. Mapping is US-layout ASCII only (see
/// `HIDInput.keyReports(for:adding:)`), so non-ASCII input is silently dropped —
/// matching the Keyboard tab. Does not require Accessibility permission (unlike
/// Direct Input's global event tap).
struct HIDTextSender: View {
    let hid: HIDInput
    @Binding var mods: KeyboardModifiers
    /// external focus binding (e.g. so a parent's toolbar can dismiss the keyboard)
    var focus: FocusState<Bool>.Binding?
    /// grab focus automatically once the view appears (used by the popover)
    var autoFocus: Bool = false

    @State private var text = ""
    @State private var sent = ""
    @State private var resetting = false
    @FocusState private var internalFocus: Bool
    @StateObject private var typist = KeyTypist()

    var body: some View {
        HStack(spacing: 8) {
            field
            Button(L10n.Keyboard.clear) { clear() }
                .buttonStyle(.bordered)
        }
        .task {
            guard autoFocus else { return }
            // let the popover animation settle before grabbing focus
            try? await Task.sleep(nanoseconds: 100_000_000)
            setFocus(true)
        }
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(L10n.Keyboard.prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
        #endif
            .onChange(of: text) { handleChange($0) }
            .onSubmit { press(.return) }
        if let focus {
            base.focused(focus)
        } else {
            base.focused($internalFocus)
        }
    }

    private func setFocus(_ value: Bool) {
        if let focus {
            focus.wrappedValue = value
        } else {
            internalFocus = value
        }
    }

    private func press(_ key: Keycode) {
        typist.send = hid.sendKeyboard
        typist.enqueue(HIDInput.keyReports(for: key, modifiers: mods))
    }

    /// live typing: diff the field against what was already sent
    private func handleChange(_ new: String) {
        if resetting {
            resetting = false
            sent = new
            return
        }
        typist.send = hid.sendKeyboard
        let prefix = new.commonPrefix(with: sent).count
        var reports: [KeyboardReport] = []
        for _ in 0 ..< (sent.count - prefix) {
            reports += HIDInput.keyReports(for: .backspace)
        }
        for character in new.dropFirst(prefix) {
            reports += HIDInput.keyReports(for: character, adding: mods)
        }
        typist.enqueue(reports)
        sent = new
    }

    private func clear() {
        resetting = true
        text = ""
        setFocus(true)
    }
}

/// paces keyboard reports so each down/up transition is delivered;
/// without spacing, rapid identical key presses get coalesced and lost.
@MainActor
final class KeyTypist: ObservableObject {
    var send: ((KeyboardReport) -> Void)?

    private var queue: [KeyboardReport] = []
    private var draining = false

    func enqueue(_ reports: [KeyboardReport]) {
        guard !reports.isEmpty else { return }
        queue.append(contentsOf: reports)
        guard !draining else { return }
        draining = true
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            send?(queue.removeFirst())
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        draining = false
    }
}
