#if os(macOS)
    import Foundation

    /// While Direct Input forwards keys, map Command to Ctrl so Mac muscle memory works on
    /// Windows (e.g. Cmd+C -> Ctrl+C). Control already maps to Ctrl and is left unchanged;
    /// Alt/Shift pass through. Command (GUI) is *replaced* by Ctrl rather than added alongside,
    /// so the report never carries the Windows key — otherwise Windows would intercept the
    /// Win+chord at the shell and the target app would never receive Ctrl+C/Ctrl+V.
    ///
    /// This only affects what is *forwarded* to the remote host. The Direct Input toggle
    /// hotkey keeps matching against the real (un-remapped) macOS modifiers, so enabling
    /// this remap never interferes with starting or stopping capture.
    func remapModifiersForWindows(_ m: KeyboardModifiers) -> KeyboardModifiers {
        guard UserDefaults.standard.bool(forKey: AppSettings.macToWindowsModifierRemapKey) else { return m }
        var out = m
        if out.contains(.leftGUI) {
            out.insert(.leftCtrl)
            out.remove(.leftGUI)
        }
        if out.contains(.rightGUI) {
            out.insert(.rightCtrl)
            out.remove(.rightGUI)
        }
        return out
    }
#endif
