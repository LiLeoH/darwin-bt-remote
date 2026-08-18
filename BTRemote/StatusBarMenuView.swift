#if os(macOS)
    import AppKit
    import SwiftUI

    /// SwiftUI content shown when the menu-bar item is clicked.
    struct StatusBarMenuView: View {
        @ObservedObject var directInput: DirectInputController
        let hid: HIDInput
        var send: (WindowsShortcut) -> Void
        var toggleDirectInput: () -> Void
        var openMainWindow: () -> Void

        @FocusState private var textFieldFocused: Bool
        @StateObject private var optionPin = OptionCursorPin()
        @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity

        private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 2)

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                typeSection
                Divider()
                shortcutsSection
                Divider()
                directInputButton
                Divider()
                openMainWindowButton
            }
            .padding(14)
            .frame(width: 320)
            .onAppear {
                let s = CGFloat(touchpadSensitivity)
                optionPin.onMoveWithButtons = { [hid] dx, dy, buttons in
                    hid.sendMouse(MouseReport(buttons: buttons, dX: HIDInput.clamp(dx * s), dY: HIDInput.clamp(dy * s))) {}
                }
                optionPin.onButtonDown = { [hid] button in
                    hid.sendMouse(MouseReport(buttons: button)) {}
                }
                optionPin.onButtonUp = { [hid] _ in
                    hid.sendMouse(.zero) {}
                }
                optionPin.activate()
            }
            .onDisappear {
                optionPin.isEnabled = false
                optionPin.deactivate()
            }
            // SwiftUI's onDisappear is unreliable inside a popover whose hosting controller is
            // retained by StatusBarController, so the Option-pin monitors could outlive the
            // closed popover and trigger anywhere (e.g. while a Dock menu is showing). Track
            // the popover's real close notification instead. (No didShow/re-activation handler
            // is needed: presentPopover recreates this view, so onAppear runs on every open.
            // App activation transitions are deliberately not gated either — an inactive app
            // receives no local monitor events, and re-evaluating focus on activation races
            // the popover's autofocus and can leave the pin wrongly disabled.)
            .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
                optionPin.isEnabled = false
                optionPin.deactivate()
            }
            .onChange(of: textFieldFocused) { newValue in
                optionPin.isEnabled = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                optionPin.cancelPin()
            }
        }

        private var header: some View {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(Color.accentColor)
                Text(L10n.StatusBar.title)
                    .font(.headline)
                Spacer()
            }
        }

        private var typeSection: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.StatusBar.typeSection)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                HIDTextSender(hid: hid, mods: .constant([]), focus: $textFieldFocused, autoFocus: true)
                    .disabled(!hid.isActive)
                if !hid.isActive {
                    Text(L10n.StatusBar.typeHintDisconnected)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }

        private var shortcutsSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.StatusBar.windowsShortcuts)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(windowsShortcuts) { shortcut in
                        shortcutChip(shortcut)
                    }
                }
            }
        }

        private func shortcutChip(_ shortcut: WindowsShortcut) -> some View {
            Button {
                send(shortcut)
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
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(groupFill))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shortcut.caption), \(shortcut.accessibility)")
        }

        private var directInputButton: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    toggleDirectInput()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: directInput.isCapturing ? "stop.circle.fill" : "play.circle.fill")
                        Text(directInput.isCapturing ? L10n.StatusBar.stopDirectInput : L10n.StatusBar.startDirectInput)
                        Spacer()
                        if directInput.isCapturing {
                            Text(L10n.StatusBar.active)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(directInput.isCapturing ? .red : .accentColor)
                .disabled(!directInput.isCapturing && !canStartDirectInput)

                if let hint = directInputStartHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }

        private var canStartDirectInput: Bool {
            directInput.toggleHotkey != nil && hid.isConnected
        }

        private var directInputStartHint: String? {
            guard !directInput.isCapturing else { return nil }
            if directInput.toggleHotkey == nil {
                return L10n.DirectInput.needToggleHotkeyString
            } else if !hid.isConnected {
                return L10n.DirectInput.noHostConnectedString
            } else {
                return nil
            }
        }

        private var openMainWindowButton: some View {
            Button {
                openMainWindow()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                    Text(L10n.StatusBar.openMain)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 2)
        }
    }
#endif
