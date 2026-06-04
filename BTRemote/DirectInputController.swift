#if os(macOS)
import ApplicationServices
import AppKit
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
        case .keyDown(let key):
            pressedKeys.insert(key)
            sendKeyboardReport()
        case .keyUp(let key):
            pressedKeys.remove(key)
            sendKeyboardReport()
        case .flagsChanged:
            sendKeyboardReport()
        case .mouseMove(let dx, let dy):
            sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: dx, dY: dy))
        case .mouseButton(let button, let isDown):
            if isDown {
                pressedMouseButtons.insert(button)
            } else {
                pressedMouseButtons.remove(button)
            }
            sendMouse?(MouseReport(buttons: pressedMouseButtons))
        case .scroll(let wheel):
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

    private nonisolated static let eventTapCallback: CGEventTapCallBack = { proxy, type, cgEvent, userInfo in
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
        case .leftMouseDown:
            kind = .mouseButton(.left, true)
        case .leftMouseUp:
            kind = .mouseButton(.left, false)
        case .rightMouseDown:
            kind = .mouseButton(.right, true)
        case .rightMouseUp:
            kind = .mouseButton(.right, false)
        case .otherMouseDown:
            kind = .mouseButton(.middle, true)
        case .otherMouseUp:
            kind = .mouseButton(.middle, false)
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
        switch key {
        case 0x00: self = .a
        case 0x0B: self = .b
        case 0x08: self = .c
        case 0x02: self = .d
        case 0x0E: self = .e
        case 0x03: self = .f
        case 0x05: self = .g
        case 0x04: self = .h
        case 0x22: self = .i
        case 0x26: self = .j
        case 0x28: self = .k
        case 0x25: self = .l
        case 0x2E: self = .m
        case 0x2D: self = .n
        case 0x1F: self = .o
        case 0x23: self = .p
        case 0x0C: self = .q
        case 0x0F: self = .r
        case 0x01: self = .s
        case 0x11: self = .t
        case 0x20: self = .u
        case 0x09: self = .v
        case 0x0D: self = .w
        case 0x07: self = .x
        case 0x10: self = .y
        case 0x06: self = .z
        case 0x12: self = .digit1
        case 0x13: self = .digit2
        case 0x14: self = .digit3
        case 0x15: self = .digit4
        case 0x17: self = .digit5
        case 0x16: self = .digit6
        case 0x1A: self = .digit7
        case 0x1C: self = .digit8
        case 0x19: self = .digit9
        case 0x1D: self = .digit0
        case 0x24, 0x4C: self = .return
        case 0x35: self = .escape
        case 0x33: self = .backspace
        case 0x30: self = .tab
        case 0x31: self = .space
        case 0x1B: self = .minus
        case 0x18: self = .equal
        case 0x21: self = .leftBracket
        case 0x1E: self = .rightBracket
        case 0x2A: self = .backslash
        case 0x29: self = .semicolon
        case 0x27: self = .quote
        case 0x32: self = .grave
        case 0x2B: self = .comma
        case 0x2F: self = .period
        case 0x2C: self = .slash
        case 0x39: self = .capsLock
        case 0x7A: self = .f1
        case 0x78: self = .f2
        case 0x63: self = .f3
        case 0x76: self = .f4
        case 0x60: self = .f5
        case 0x61: self = .f6
        case 0x62: self = .f7
        case 0x64: self = .f8
        case 0x65: self = .f9
        case 0x6D: self = .f10
        case 0x67: self = .f11
        case 0x6F: self = .f12
        case 0x7C: self = .rightArrow
        case 0x7B: self = .leftArrow
        case 0x7D: self = .downArrow
        case 0x7E: self = .upArrow
        default: return nil
        }
    }
}
#endif
