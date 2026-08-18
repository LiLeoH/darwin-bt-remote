#if os(macOS)
    import Combine
    import Foundation

    /// Single source of truth for the Direct Input toggle shortcut.
    ///
    /// Owns the persistent `Hotkey`, drives the `DirectInputHotkeyMonitor`, and translates a
    /// detected shortcut into a start/stop of the `DirectInputController`. The binding is stored
    /// in `UserDefaults`, so it survives app restarts.
    @MainActor
    final class DirectInputShortcutManager: ObservableObject {
        static let shared = DirectInputShortcutManager()

        @Published var hotkey: Hotkey?
        @Published private(set) var isMonitoring = false

        private weak var directInput: DirectInputController?
        private var buildHID: (() -> HIDInput)?
        private var monitor: DirectInputHotkeyMonitor?

        private init() {
            hotkey = Self.load()
        }

        /// Called once from the root view with the live controller and a HID builder.
        func attach(directInput: DirectInputController, buildHID: @escaping () -> HIDInput) {
            self.directInput = directInput
            self.buildHID = buildHID
            directInput.toggleHotkey = hotkey
            reconfigureMonitor()
        }

        /// Re-read the persisted value (e.g. after a settings reset).
        func reload() {
            hotkey = Self.load()
            directInput?.toggleHotkey = hotkey
            reconfigureMonitor()
        }

        /// Persist and apply a new binding (nil disables the shortcut).
        func setHotkey(_ new: Hotkey?) {
            hotkey = new
            Self.save(new)
            directInput?.toggleHotkey = new
            reconfigureMonitor()
        }

        /// Pause/resume monitoring — used while the recorder is capturing a new combo so the
        /// app shortcut does not fire mid-recording.
        func setMonitoringEnabled(_ enabled: Bool) {
            monitor?.setEnabled(enabled)
            isMonitoring = enabled && hotkey != nil
        }

        /// Human-readable conflict description for a proposed binding, or nil if it is free.
        func conflict(for proposed: Hotkey) -> String? {
            proposed.conflictDescription()
        }

        private func reconfigureMonitor() {
            if let hotkey {
                if monitor == nil {
                    let monitor = DirectInputHotkeyMonitor()
                    monitor.start(hotkey: hotkey) { [weak self] in
                        guard let self else { return }
                        guard let build = buildHID else { return }
                        if directInput?.isCapturing == true {
                            directInput?.stop()
                        } else {
                            directInput?.start(build())
                        }
                    }
                    self.monitor = monitor
                    isMonitoring = true
                } else {
                    monitor?.update(hotkey: hotkey)
                }
            } else {
                monitor?.stop()
                monitor = nil
                isMonitoring = false
            }
        }

        private static func load() -> Hotkey? {
            guard let data = UserDefaults.standard.data(forKey: AppSettings.directInputToggleHotkeyKey) else { return nil }
            return try? JSONDecoder().decode(Hotkey.self, from: data)
        }

        private static func save(_ hotkey: Hotkey?) {
            let key = AppSettings.directInputToggleHotkeyKey
            if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
#endif
