import Foundation

enum AppSettings {
    static let touchpadSensitivityKey = "BTRemote.touchpadSensitivity"
    static let scrollSensitivityKey = "BTRemote.scrollSensitivity"
    static let autoAdvertiseKey = "BTRemote.autoAdvertise"
    static let directInputToggleHotkeyKey = "BTRemote.directInputToggleHotkey"
    static let developerModeKey = "BTRemote.developerMode"
    static let directInputOutputHzKey = "BTRemote.directInputOutputHz"
    /// macOS: max mouse reports allowed in flight on the Bluetooth link while Direct Input
    /// forwards local input. Bounding this (instead of queueing every flush) caps end-to-end
    /// latency; lower = lower latency but coarser movement, higher = smoother but more backlog.
    static let directInputMaxOutstandingWritesKey = "BTRemote.directInputMaxOutstandingWrites"
    /// macOS: whether a persistent red screen-edge border is shown while Direct Input is capturing.
    static let directInputIndicatorEnabledKey = "BTRemote.directInputIndicatorEnabled"
    /// macOS: remap local modifiers to Windows convention while Direct Input forwards keys
    /// (Command -> Ctrl, Control -> Win). Lets Mac muscle memory (Cmd+C) drive Windows (Ctrl+C).
    static let macToWindowsModifierRemapKey = "BTRemote.macToWindowsModifierRemap"
    static let useServiceChangedKey = "BTRemote.useServiceChanged"
    static let deviceNamesKey = "BTRemote.deviceNames"
    static let hasSeenWelcomeKey = "BTRemote.hasSeenWelcome"
    /// macOS clipboard sync over LE (requires companion app on Windows target).
    static let clipboardSyncEnabledKey = "BTRemote.clipboardSyncEnabled"
    /// Whether clipboard sync also includes images (PNG). Requires clipboard sync to be enabled.
    static let clipboardSyncImagesEnabledKey = "BTRemote.clipboardSyncImagesEnabled"

    static let repoURL = URL(string: "https://github.com/jqssun/darwin-bt-remote")!
    static let instructionsURL = URL(string: "https://github.com/jqssun/darwin-bt-remote/blob/main/README.md")!

    static let defaultPointerSensitivity = 5.0
    static let pointerSensitivityRange = 0.5 ... 10.0
    static let defaultScrollSensitivity = 1.0
    static let scrollSensitivityRange = 0.5 ... 3.0

    /// Direct Input: HID report output cadence (Hz) used to coalesce high-polling local mice.
    /// Higher = lower latency but more link load; capped by the Bluetooth HID link capacity.
    static let defaultDirectInputOutputHz = 125
    static let directInputOutputHzRange = 30 ... 1000
    /// Direct Input: maximum mouse reports in flight on the Bluetooth link. See
    /// `directInputMaxOutstandingWritesKey`. Higher = smoother but more backlog.
    static let defaultDirectInputMaxOutstandingWrites = 2
    static let directInputMaxOutstandingWritesRange = 1 ... 4
}
