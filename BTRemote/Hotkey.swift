#if os(macOS)
    import AppKit
    import Foundation

    /// A user-configurable keyboard shortcut (a set of modifiers plus a non-modifier key)
    /// used to toggle the Direct Input feature on and off.
    struct Hotkey: Codable, Equatable, Hashable {
        var modifiers: KeyboardModifiers
        var key: Keycode?

        /// A shortcut is only valid when it includes a real key — a modifiers-only
        /// binding would be ambiguous to detect while capturing.
        var isValid: Bool {
            key != nil
        }

        /// Human-readable representation, e.g. "⌘⇧D".
        var displayString: String {
            var parts: [String] = []
            if modifiers.contains(.leftCtrl) || modifiers.contains(.rightCtrl) {
                parts.append("⌃")
            }
            if modifiers.contains(.leftAlt) || modifiers.contains(.rightAlt) {
                parts.append("⌥")
            }
            if modifiers.contains(.leftShift) || modifiers.contains(.rightShift) {
                parts.append("⇧")
            }
            if modifiers.contains(.leftGUI) || modifiers.contains(.rightGUI) {
                parts.append("⌘")
            }
            if let key {
                parts.append(key.displayName)
            }
            return parts.joined()
        }

        /// Build a Hotkey from an NSEvent (used by the recorder and the monitor).
        static func from(event: NSEvent) -> Hotkey? {
            guard let key = Keycode(macVirtualKey: event.keyCode) else { return nil }
            return Hotkey(modifiers: KeyboardModifiers(event.modifierFlags), key: key)
        }

        /// Does this NSEvent match the shortcut? Left/right modifier variants are treated as equal.
        func matches(event: NSEvent) -> Bool {
            guard let eventKey = Keycode(macVirtualKey: event.keyCode) else { return false }
            guard eventKey == key else { return false }
            return KeyboardModifiers(event.modifierFlags).collapsed == modifiers.collapsed
        }

        /// Description of a conflict with a reserved shortcut, or nil when the binding is free.
        func conflictDescription() -> String? {
            HotkeyConflicts.description(for: self)
        }

        func collapsedEquals(_ other: Hotkey) -> Bool {
            key == other.key && modifiers.collapsed == other.modifiers.collapsed
        }
    }

    extension KeyboardModifiers {
        /// Build from AppKit modifier flags (only the four standard modifiers are kept).
        init(_ ns: NSEvent.ModifierFlags) {
            self.init()
            if ns.contains(.control) {
                insert(.leftCtrl)
            }
            if ns.contains(.shift) {
                insert(.leftShift)
            }
            if ns.contains(.option) {
                insert(.leftAlt)
            }
            if ns.contains(.command) {
                insert(.leftGUI)
            }
        }

        /// Collapse left/right modifier variants so comparisons ignore which side was pressed.
        var collapsed: KeyboardModifiers {
            var m = self
            if m.contains(.rightCtrl) {
                m.insert(.leftCtrl); m.remove(.rightCtrl)
            }
            if m.contains(.rightShift) {
                m.insert(.leftShift); m.remove(.rightShift)
            }
            if m.contains(.rightAlt) {
                m.insert(.leftAlt); m.remove(.rightAlt)
            }
            if m.contains(.rightGUI) {
                m.insert(.leftGUI); m.remove(.rightGUI)
            }
            return m
        }
    }

    /// Reserved shortcuts that a user binding must not collide with.
    struct ReservedHotkey {
        let hotkey: Hotkey
        let label: String
    }

    enum HotkeyConflicts {
        /// A toggle binding is rejected only when it duplicates a genuine system shortcut.
        ///
        /// On macOS the user-configured toggle shortcut is the *sole* hardware control for
        /// Direct Input: the same combination flips capture on (via the global hotkey monitor
        /// when idle) and off (detected inside the capture tap). There is no separate keyless
        /// "release" combination, so any ⌃⌥+<key> toggle is treated as a normal, conflict-free
        /// binding unless it collides with a reserved system shortcut below.
        static func description(for proposed: Hotkey) -> String? {
            for reserved in systemShortcuts where reserved.hotkey.collapsedEquals(proposed) {
                return String(format: L10n.Shortcut.conflictSystemString, reserved.label)
            }
            return nil
        }

        private static let systemShortcuts: [ReservedHotkey] = [
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .space), label: "⌘Space (Spotlight)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI, .leftShift], key: .digit3), label: "⌘⇧3 (Screenshot)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI, .leftShift], key: .digit4), label: "⌘⇧4 (Screenshot)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI, .leftShift], key: .digit5), label: "⌘⇧5 (Screenshot)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .tab), label: "⌘Tab (App Switcher)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .grave), label: "⌘` (Cycle Windows)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .q), label: "⌘Q (Quit)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .w), label: "⌘W (Close)"),
            .init(hotkey: Hotkey(modifiers: [.leftGUI], key: .h), label: "⌘H (Hide)"),
            .init(hotkey: Hotkey(modifiers: [.leftCtrl], key: .leftArrow), label: "⌃← (Mission Control)"),
            .init(hotkey: Hotkey(modifiers: [.leftCtrl], key: .upArrow), label: "⌃↑ (Mission Control)")
        ]
    }
#endif
