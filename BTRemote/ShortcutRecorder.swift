#if os(macOS)
    import AppKit
    import SwiftUI

    /// A control that lets the user record a keyboard shortcut.
    ///
    /// While recording, a local event monitor swallows the next key-down and builds a `Hotkey`.
    /// A modifiers-only press is rejected (a key is required) and any conflict with a reserved
    /// shortcut is reported inline without saving.
    struct HotkeyRecorder: View {
        @Binding var hotkey: Hotkey?
        var conflict: (Hotkey) -> String?

        @StateObject private var engine = RecorderEngine()

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        engine.begin(conflict: conflict)
                    } label: {
                        Text(engine.isRecording
                            ? L10n.Shortcut.recordingString
                            : (hotkey?.displayString ?? L10n.Shortcut.recorderIdleString))
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 150, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(engine.isRecording
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(engine.isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .help(L10n.Shortcut.recorderHelpString)

                    if hotkey != nil {
                        Button(L10n.Shortcut.clearString) { engine.clear() }
                            .buttonStyle(.borderless)
                    }
                }

                if let message = engine.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let hotkey {
                    Text(String(format: L10n.Shortcut.hintString, hotkey.displayString))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                engine.onCommit = { [binding = $hotkey] in binding.wrappedValue = $0 }
            }
            .onDisappear { engine.cancel() }
        }
    }

    @MainActor
    final class RecorderEngine: ObservableObject {
        @Published var isRecording = false
        @Published var message: String?

        var onCommit: ((Hotkey?) -> Void)?

        private var monitor: Any?

        func begin(conflict: @escaping (Hotkey) -> String?) {
            message = nil
            isRecording = true
            DirectInputShortcutManager.shared.setMonitoringEnabled(false)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.capture(event, conflict: conflict)
                return nil
            }
        }

        private func capture(_ event: NSEvent, conflict: @escaping (Hotkey) -> String?) {
            // Ignore pure modifier key presses (⌃ ⌥ ⇧ ⌘). They must not consume the
            // recording: the actual key arrives afterward, and its `modifierFlags` already
            // carries the held modifiers. Aborting here would make every modifier combo —
            // e.g. ⌃⌥Z — impossible to record, because the first key pressed is a modifier.
            if Self.isModifierKeyCode(event.keyCode) {
                return
            }

            guard let captured = Hotkey.from(event: event) else {
                // Unmapped key: keep listening rather than silently ending the recording.
                return
            }

            removeMonitor()
            isRecording = false
            DirectInputShortcutManager.shared.setMonitoringEnabled(true)

            guard captured.key != nil else {
                message = L10n.Shortcut.requiresKeyString
                return
            }
            if let description = conflict(captured) {
                message = description
                return
            }
            message = nil
            onCommit?(captured)
        }

        private static let modifierKeyCodes: Set<UInt16> = [
            0x37, 0x36, // command (left / right)
            0x3B, 0x3E, // control (left / right)
            0x3A, 0x3D, // option (left / right)
            0x38, 0x3C // shift (left / right)
        ]

        private static func isModifierKeyCode(_ code: UInt16) -> Bool {
            modifierKeyCodes.contains(code)
        }

        func clear() {
            message = nil
            onCommit?(nil)
        }

        func cancel() {
            removeMonitor()
            isRecording = false
            DirectInputShortcutManager.shared.setMonitoringEnabled(true)
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
#endif
