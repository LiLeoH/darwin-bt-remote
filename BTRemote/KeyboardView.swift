import SwiftUI

private let keyHeight: CGFloat = 44

struct KeyboardView: View {
    let goToSetup: () -> Void

    @EnvironmentObject private var ble: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @Environment(\.macTransport) private var macTransport
    #endif

    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @State private var text = ""
    @State private var sent = ""
    @State private var resetting = false
    @State private var mods: KeyboardModifiers = []
    @FocusState private var focused: Bool
    @StateObject private var typist = KeyTypist()

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(ble: ble, central: central, classic: classic, classicMode: macTransport == .classic)
        #else
            return HIDInput.make(ble: ble, central: central)
        #endif
    }

    var body: some View {
        #if os(macOS)
            NavigationStack { titledScreen }
        #else
            NavigationView { titledScreen }
                .navigationViewStyle(.stack)
        #endif
    }

    private var titledScreen: some View {
        screen
            .navigationTitle(L10n.Tab.keyboard)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        if hid.isActive || developerMode {
            editor
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(L10n.Remote.notConnectedTitle)
                .font(.title2.weight(.semibold))
            Text(L10n.Remote.notConnectedMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.Remote.openSetup, action: goToSetup)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField(L10n.Keyboard.prompt, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                #endif
                    .onChange(of: text) { handleChange($0) }
                    .onSubmit { press(.return) }
                Button(L10n.Keyboard.clear) { clear() }
                    .buttonStyle(.bordered)
            }
            keyPanel
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.Keyboard.done) { focused = false }
                }
            }
        #endif
    }

    private var keyPanel: some View {
        VStack(spacing: 6) {
            keyRow(fRow)
            keyRow(row1)
            keyRow(row2)
            keyRow(row3)
        }
    }

    private func keyRow(_ keys: [KeyCap]) -> some View {
        GeometryReader { geo in
            let total = keys.reduce(0) { $0 + $1.weight }
            let gaps = 6 * CGFloat(max(keys.count - 1, 0))
            let unit = max(0, (geo.size.width - gaps) / total)
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    keyCapButton(key).frame(width: unit * key.weight)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: keyHeight)
    }

    private func keyCapButton(_ key: KeyCap) -> some View {
        let armed: Bool = {
            if case let .modifier(mod) = key.action { return mods.contains(mod) }
            return false
        }()
        return Button {
            Haptics.tap()
            switch key.action {
            case let .key(code): press(code)
            case let .modifier(mod): toggle(mod)
            }
        } label: {
            keyLabel(key.label)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(armed ? Color.accentColor : groupFill))
                .foregroundColor(armed ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibility)
    }

    @ViewBuilder
    private func keyLabel(_ label: KeyCap.Label) -> some View {
        switch label {
        case let .symbol(name): Image(systemName: name).font(.body)
        case let .text(value): Text(value).font(.footnote)
        case .blank: Color.clear
        }
    }

    // key rows

    private let fKeys: [(Keycode, String)] = [
        (.f1, "F1"), (.f2, "F2"), (.f3, "F3"), (.f4, "F4"), (.f5, "F5"), (.f6, "F6"),
        (.f7, "F7"), (.f8, "F8"), (.f9, "F9"), (.f10, "F10"), (.f11, "F11"), (.f12, "F12")
    ]

    private var fRow: [KeyCap] {
        fKeys.map { code, name in KeyCap(.text(LocalizedStringKey(name)), LocalizedStringKey(name), .key(code)) }
    }

    private var row1: [KeyCap] {
        [
            KeyCap(.symbol("escape"), L10n.Keyboard.esc, .key(.escape)),
            KeyCap(.symbol("arrow.right.to.line"), L10n.Keyboard.tab, .key(.tab)),
            KeyCap(.text(L10n.Keyboard.printScreen), L10n.Keyboard.printScreen, .key(.printScreen)),
            KeyCap(.symbol("arrow.up"), L10n.Keyboard.up, .key(.upArrow)),
            KeyCap(.symbol("delete.left"), weight: 1.5, L10n.Keyboard.backspace, .key(.backspace)),
            KeyCap(.symbol("return"), weight: 1.5, L10n.Keyboard.enter, .key(.return))
        ]
    }

    private var row2: [KeyCap] {
        [
            KeyCap(.symbol("shift"), L10n.Keyboard.shift, .modifier(.leftShift)),
            KeyCap(.symbol("command"), L10n.Keyboard.meta, .modifier(.leftGUI)),
            KeyCap(.symbol("arrow.left"), L10n.Keyboard.left, .key(.leftArrow)),
            KeyCap(.symbol("arrow.down"), L10n.Keyboard.down, .key(.downArrow)),
            KeyCap(.symbol("arrow.right"), L10n.Keyboard.right, .key(.rightArrow)),
            KeyCap(.symbol("command"), L10n.Keyboard.meta, .modifier(.rightGUI)),
            KeyCap(.symbol("shift"), L10n.Keyboard.shift, .modifier(.rightShift))
        ]
    }

    private var row3: [KeyCap] {
        [
            KeyCap(.symbol("control"), L10n.Keyboard.ctrl, .modifier(.leftCtrl)),
            KeyCap(.symbol("option"), L10n.Keyboard.alt, .modifier(.leftAlt)),
            KeyCap(.blank, weight: 3, L10n.Keyboard.space, .key(.space)),
            KeyCap(.text(L10n.Keyboard.altGr), L10n.Keyboard.altGr, .modifier(.rightAlt)),
            KeyCap(.symbol("control"), L10n.Keyboard.ctrl, .modifier(.rightCtrl))
        ]
    }

    // actions

    private func press(_ key: Keycode) {
        typist.send = hid.sendKeyboard
        typist.enqueue(HIDInput.keyReports(for: key, modifiers: mods))
    }

    private func toggle(_ mod: KeyboardModifiers) {
        if mods.contains(mod) { mods.subtract(mod) } else { mods.insert(mod) }
    }

    // live typing: diff the field against what was already sent

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
        focused = true
    }
}

private struct KeyCap {
    enum Label {
        case symbol(String)
        case text(LocalizedStringKey)
        case blank
    }

    enum Action {
        case key(Keycode)
        case modifier(KeyboardModifiers)
    }

    let label: Label
    let weight: CGFloat
    let accessibility: LocalizedStringKey
    let action: Action

    init(_ label: Label, weight: CGFloat = 1, _ accessibility: LocalizedStringKey, _ action: Action) {
        self.label = label
        self.weight = weight
        self.accessibility = accessibility
        self.action = action
    }
}

/// paces keyboard reports so each down/up transition is delivered;
/// without spacing, rapid identical key presses get coalesced and lost.
@MainActor
private final class KeyTypist: ObservableObject {
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

#if DEBUG
    #Preview {
        #if os(iOS)
            KeyboardView(goToSetup: {})
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
        #else
            KeyboardView(goToSetup: {})
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
