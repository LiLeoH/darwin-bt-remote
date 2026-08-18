import SwiftUI

private let keyHeight: CGFloat = 44

struct KeyboardView: View {
    let goToSetup: () -> Void

    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @Environment(\.macTransport) private var macTransport
    #endif

    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @State private var mods: KeyboardModifiers = []
    @FocusState private var focused: Bool
    @StateObject private var typist = KeyTypist()

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: macTransport == .classic)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
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
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                HStack(spacing: 12) {
                    VStack(spacing: 12) {
                        inputField
                        keyPanel
                        shortcutsPanel
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    TrackpadPanel(hid: hid).frame(width: geo.size.width * 0.42)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    inputField
                    keyPanel
                    shortcutsPanel
                    TrackpadPanel(hid: hid).frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding()
        #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.Keyboard.done) { focused = false }
                }
            }
        #endif
    }

    private var inputField: some View {
        HIDTextSender(hid: hid, mods: $mods, focus: $focused)
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
            if case let .modifier(mod) = key.action {
                return mods.contains(mod)
            }
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
            KeyCap(.symbol("arrow.left"), L10n.Keyboard.left, .key(.leftArrow)),
            KeyCap(.symbol("arrow.down"), L10n.Keyboard.down, .key(.downArrow)),
            KeyCap(.symbol("arrow.right"), L10n.Keyboard.right, .key(.rightArrow)),
            KeyCap(.symbol("shift"), L10n.Keyboard.shift, .modifier(.rightShift))
        ]
    }

    private var row3: [KeyCap] {
        [
            KeyCap(.symbol("control"), L10n.Keyboard.ctrl, .modifier(.leftCtrl)),
            KeyCap(.text(L10n.Keyboard.win), L10n.Keyboard.win, .modifier(.leftGUI)),
            KeyCap(.text(L10n.Keyboard.alt), L10n.Keyboard.alt, .modifier(.leftAlt)),
            KeyCap(.blank, weight: 3, L10n.Keyboard.space, .key(.space)),
            KeyCap(.text(L10n.Keyboard.altGr), L10n.Keyboard.altGr, .modifier(.rightAlt)),
            KeyCap(.symbol("control"), L10n.Keyboard.ctrl, .modifier(.rightCtrl))
        ]
    }

    private func press(_ key: Keycode) {
        typist.send = hid.sendKeyboard
        typist.enqueue(HIDInput.keyReports(for: key, modifiers: mods))
    }

    private func toggle(_ mod: KeyboardModifiers) {
        if mods.contains(mod) {
            mods.subtract(mod)
        } else {
            mods.insert(mod)
        }
    }

    /// sends a multi-key chord (modifiers held while the keys go down, then everything released)
    private func sendShortcut(_ shortcut: WindowsShortcut) {
        typist.send = hid.sendKeyboard
        let down = KeyboardReport(modifiers: shortcut.modifiers, keys: shortcut.keys)
        typist.enqueue([down, .zero])
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

private let shortcutColumns = Array(
    repeating: GridItem(.flexible(minimum: 0), spacing: 8),
    count: 4
)

private extension KeyboardView {
    var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Keyboard.shortcutsSection)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            LazyVGrid(columns: shortcutColumns, spacing: 8) {
                ForEach(windowsShortcuts) { shortcut in
                    shortcutChip(shortcut)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    func shortcutChip(_ shortcut: WindowsShortcut) -> some View {
        Button {
            Haptics.tap()
            sendShortcut(shortcut)
        } label: {
            VStack(spacing: 2) {
                Text(shortcut.combo)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(shortcut.caption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(groupFill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(shortcut.caption), \(shortcut.accessibility)")
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
