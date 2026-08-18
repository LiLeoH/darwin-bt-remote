import Foundation

/// A Windows keyboard shortcut chord (e.g. Ctrl + Alt + Del) that can be sent to the
/// connected host. Shared by the keyboard view and the menu-bar status item.
struct WindowsShortcut: Identifiable {
    let id = UUID()
    let combo: String // display string, e.g. "Ctrl + Alt + Del"
    let caption: String
    let modifiers: KeyboardModifiers
    let keys: [Keycode]
    let accessibility: String

    init(_ combo: String, _ caption: String, modifiers: KeyboardModifiers, keys: Keycode..., accessibility: String) {
        self.combo = combo
        self.caption = caption
        self.modifiers = modifiers
        self.keys = keys
        self.accessibility = accessibility
    }
}

let windowsShortcuts: [WindowsShortcut] = [
    WindowsShortcut(
        "Ctrl + Alt + Del",
        "Security",
        modifiers: [.leftCtrl, .leftAlt],
        keys: .deleteForward,
        accessibility: "Control Alt Delete"
    ),
    WindowsShortcut("Win + L", "Lock", modifiers: [.leftGUI], keys: .l, accessibility: "Windows Lock"),
    WindowsShortcut("Win + D", "Show Desktop", modifiers: [.leftGUI], keys: .d, accessibility: "Windows Show Desktop"),
    WindowsShortcut("Win + E", "File Explorer", modifiers: [.leftGUI], keys: .e, accessibility: "Windows File Explorer"),
    WindowsShortcut("Win + R", "Run", modifiers: [.leftGUI], keys: .r, accessibility: "Windows Run"),
    WindowsShortcut("Alt + Tab", "Switch App", modifiers: [.leftAlt], keys: .tab, accessibility: "Alt Tab Switch App"),
    WindowsShortcut(
        "Ctrl + Shift + Esc",
        "Task Manager",
        modifiers: [.leftCtrl, .leftShift],
        keys: .escape,
        accessibility: "Control Shift Escape Task Manager"
    ),
    WindowsShortcut("Win + V", "Clipboard", modifiers: [.leftGUI], keys: .v, accessibility: "Windows Clipboard")
]
