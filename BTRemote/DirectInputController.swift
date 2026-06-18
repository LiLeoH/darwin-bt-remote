#if os(macOS)
    import AppKit
    import ApplicationServices
    import CoreGraphics
    import Foundation

    @MainActor
    final class DirectInputController: ObservableObject {
        @Published private(set) var isCapturing = false
        @Published private(set) var lastError: String?

        private var eventTap: CFMachPort?
        private var runLoopSource: CFRunLoopSource?
        private var pressedKeys: Set<Keycode> = []
        private var pressedMouseButtons: MouseButtons = []
        private var modifiers: KeyboardModifiers = []
        private var cursorHidden = false

        private var sendKeyboard: ((KeyboardReport) -> Void)?
        private var sendMouse: ((MouseReport) -> Void)?
        private var onRelease: (() -> Void)?

        func start(
            sendKeyboard: @escaping (KeyboardReport) -> Void,
            sendMouse: @escaping (MouseReport) -> Void,
            onRelease: @escaping () -> Void
        ) {
            stop()

            self.sendKeyboard = sendKeyboard
            self.sendMouse = sendMouse
            self.onRelease = onRelease
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            lastError = nil

            guard Self.hasAccessibilityPermission else {
                lastError = L10n.DirectInput.captureFailedString
                Self.openAccessibilitySettings()
                clearHandlers()
                onRelease()
                return
            }

            let mask = [
                CGEventType.keyDown,
                .keyUp,
                .flagsChanged,
                .mouseMoved,
                .leftMouseDown,
                .leftMouseUp,
                .leftMouseDragged,
                .rightMouseDown,
                .rightMouseUp,
                .rightMouseDragged,
                .otherMouseDown,
                .otherMouseUp,
                .otherMouseDragged,
                .scrollWheel
            ].reduce(CGEventMask(0)) { result, type in
                result | (CGEventMask(1) << CGEventMask(type.rawValue))
            }

            let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: DirectInputController.eventTapCallback,
                userInfo: refcon
            ) else {
                lastError = L10n.DirectInput.captureFailedString
                clearHandlers()
                onRelease()
                return
            }

            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
            NSCursor.hide()
            cursorHidden = true
            isCapturing = true
        }

        func stop() {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil

            if cursorHidden {
                NSCursor.unhide()
                cursorHidden = false
            }
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))

            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            sendKeyboard?(.zero)
            sendMouse?(.zero)
            clearHandlers()
            isCapturing = false
        }

        private func clearHandlers() {
            sendKeyboard = nil
            sendMouse = nil
            onRelease = nil
        }

        private func handle(_ event: DirectInputEvent) {
            if event.releaseShortcutPressed {
                onRelease?()
                stop()
                return
            }

            modifiers = event.modifiers

            switch event.kind {
            case let .keyDown(key):
                pressedKeys.insert(key)
                sendKeyboardReport()
            case let .keyUp(key):
                pressedKeys.remove(key)
                sendKeyboardReport()
            case .flagsChanged:
                sendKeyboardReport()
            case let .mouseMove(dx, dy):
                sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: dx, dY: dy))
            case let .mouseButton(button, isDown):
                if isDown {
                    pressedMouseButtons.insert(button)
                } else {
                    pressedMouseButtons.remove(button)
                }
                sendMouse?(MouseReport(buttons: pressedMouseButtons))
            case let .scroll(wheel):
                sendMouse?(MouseReport(buttons: pressedMouseButtons, wheel: wheel))
                sendMouse?(MouseReport(buttons: pressedMouseButtons))
            }
        }

        private func sendKeyboardReport() {
            sendKeyboard?(KeyboardReport(modifiers: modifiers, keys: Array(pressedKeys).prefix(6).map(\.self)))
        }

        private static var hasAccessibilityPermission: Bool {
            AXIsProcessTrusted()
        }

        private static func openAccessibilitySettings() {
            let promptOption = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)

            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        }

        private nonisolated static let eventTapCallback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
                if let userInfo {
                    let controller = Unmanaged<DirectInputController>.fromOpaque(userInfo).takeUnretainedValue()
                    Task { @MainActor in
                        controller.eventTap.map { CGEvent.tapEnable(tap: $0, enable: true) }
                    }
                }
                return nil
            }

            guard let userInfo, let event = DirectInputEvent(type: type, event: cgEvent) else {
                return nil
            }

            let controller = Unmanaged<DirectInputController>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                controller.handle(event)
            }
            return nil
        }
    }

    private struct DirectInputEvent: Sendable {
        enum Kind: Sendable {
            case keyDown(Keycode)
            case keyUp(Keycode)
            case flagsChanged
            case mouseMove(Int8, Int8)
            case mouseButton(MouseButtons, Bool)
            case scroll(Int8)
        }

        let kind: Kind
        let modifiers: KeyboardModifiers
        let releaseShortcutPressed: Bool

        init?(type: CGEventType, event: CGEvent) {
            let flags = event.flags
            modifiers = KeyboardModifiers(eventFlags: flags)
            releaseShortcutPressed = flags.contains(.maskControl) && flags.contains(.maskAlternate)

            switch type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                guard let key = Keycode(macVirtualKey: UInt16(event.getIntegerValueField(.keyboardEventKeycode))) else { return nil }
                kind = .keyDown(key)
            case .keyUp:
                guard let key = Keycode(macVirtualKey: UInt16(event.getIntegerValueField(.keyboardEventKeycode))) else { return nil }
                kind = .keyUp(key)
            case .flagsChanged:
                kind = .flagsChanged
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                let dx = Self.clampInt8(event.getIntegerValueField(.mouseEventDeltaX))
                let dy = Self.clampInt8(event.getIntegerValueField(.mouseEventDeltaY))
                guard dx != 0 || dy != 0 else { return nil }
                kind = .mouseMove(dx, dy)
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                guard let button = Self.mouseButton(for: type) else { return nil }
                kind = .mouseButton(button.0, button.1)
            case .scrollWheel:
                let wheel = Self.clampInt8(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                guard wheel != 0 else { return nil }
                kind = .scroll(wheel)
            default:
                return nil
            }
        }

        private static func clampInt8(_ value: Int64) -> Int8 {
            Int8(max(-127, min(127, Int(value))))
        }

        private static func mouseButton(for type: CGEventType) -> (MouseButtons, Bool)? {
            switch type {
            case .leftMouseDown: (.left, true)
            case .leftMouseUp: (.left, false)
            case .rightMouseDown: (.right, true)
            case .rightMouseUp: (.right, false)
            case .otherMouseDown: (.middle, true)
            case .otherMouseUp: (.middle, false)
            default: nil
            }
        }
    }

    private extension KeyboardModifiers {
        init(eventFlags flags: CGEventFlags) {
            self.init()
            if flags.contains(.maskControl) { insert(.leftCtrl) }
            if flags.contains(.maskShift) { insert(.leftShift) }
            if flags.contains(.maskAlternate) { insert(.leftAlt) }
            if flags.contains(.maskCommand) { insert(.leftGUI) }
        }
    }

    private extension Keycode {
        init?(macVirtualKey key: UInt16) {
            guard let code = Self.macVirtualKeys[key] else { return nil }
            self = code
        }

        static let macVirtualKeys: [UInt16: Keycode] = [
            0x00: .a, 0x0B: .b, 0x08: .c, 0x02: .d, 0x0E: .e, 0x03: .f, 0x05: .g, 0x04: .h,
            0x22: .i, 0x26: .j, 0x28: .k, 0x25: .l, 0x2E: .m, 0x2D: .n, 0x1F: .o, 0x23: .p,
            0x0C: .q, 0x0F: .r, 0x01: .s, 0x11: .t, 0x20: .u, 0x09: .v, 0x0D: .w, 0x07: .x,
            0x10: .y, 0x06: .z,
            0x12: .digit1, 0x13: .digit2, 0x14: .digit3, 0x15: .digit4, 0x17: .digit5,
            0x16: .digit6, 0x1A: .digit7, 0x1C: .digit8, 0x19: .digit9, 0x1D: .digit0,
            0x24: .return, 0x4C: .return,
            0x35: .escape, 0x33: .backspace, 0x30: .tab, 0x31: .space,
            0x1B: .minus, 0x18: .equal, 0x21: .leftBracket, 0x1E: .rightBracket,
            0x2A: .backslash, 0x29: .semicolon, 0x27: .quote, 0x32: .grave,
            0x2B: .comma, 0x2F: .period, 0x2C: .slash, 0x39: .capsLock,
            0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4, 0x60: .f5, 0x61: .f6,
            0x62: .f7, 0x64: .f8, 0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12,
            0x7C: .rightArrow, 0x7B: .leftArrow, 0x7D: .downArrow, 0x7E: .upArrow
        ]
    }
#endif
