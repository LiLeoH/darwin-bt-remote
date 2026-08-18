#if os(macOS)
    import AppKit
    import Foundation

    /// Listens system-wide for a key-down event matching a configured `Hotkey` and invokes
    /// `onToggle`. Both a global (other apps focused) and a local (this app focused) monitor
    /// are installed; only one fires per physical keypress, so toggles are never doubled.
    @MainActor
    final class DirectInputHotkeyMonitor {
        private var globalMonitor: Any?
        private var localMonitor: Any?
        private var hotkey: Hotkey?
        private var onToggle: (() -> Void)?

        func start(hotkey: Hotkey?, onToggle: @escaping () -> Void) {
            self.hotkey = hotkey
            self.onToggle = onToggle
            install()
        }

        func update(hotkey: Hotkey?) {
            self.hotkey = hotkey
        }

        func setEnabled(_ enabled: Bool) {
            if enabled {
                install()
            } else {
                uninstall()
            }
        }

        func stop() {
            uninstall()
            onToggle = nil
        }

        private func install() {
            guard globalMonitor == nil, localMonitor == nil else { return }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
                return event
            }
        }

        private func uninstall() {
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            guard let hotkey, hotkey.matches(event: event) else { return }
            onToggle?()
        }
    }
#endif
