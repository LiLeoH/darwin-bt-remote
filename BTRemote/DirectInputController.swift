#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import os

    @MainActor
    final class DirectInputController: ObservableObject {
        @Published private(set) var isCapturing = false
        @Published private(set) var lastError: String?
        @Published private(set) var needsAccessibility = false

        private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "DirectInputController")

        private var eventTap: CFMachPort?
        private var runLoopSource: CFRunLoopSource?
        private var pressedKeys: Set<Keycode> = []
        private var pressedMouseButtons: MouseButtons = []
        private var modifiers: KeyboardModifiers = []
        private var cursorHidden = false

        // MARK: Output rate matching

        /// Coalesces high-frequency local input into fixed-cadence HID reports so the
        /// capture rate is decoupled from the Classic Bluetooth HIDP output rate.
        /// Without this, a high-polling (e.g. 2.4G, 500-1000+ Hz) mouse overwhelms the
        /// L2CAP interrupt channel and the main-actor send queue, producing backlog and latency.
        private var flushTimer: DispatchSourceTimer?
        private var accumDX = 0
        private var accumDY = 0
        private var accumWheel = 0
        private var hasPendingMovement = false
        private var hasPendingScroll = false
        /// Maximum mouse reports allowed in flight on the Bluetooth link. Bounding this
        /// (instead of queueing every flush) caps end-to-end latency; resolved at `start()`.
        private var maxOutstandingWrites = AppSettings.defaultDirectInputMaxOutstandingWrites
        private var outstandingWrites = 0
        /// Consecutive flush intervals where the in-flight counter was pinned at the
        /// backpressure ceiling. A sustained maximum means completions have stopped
        /// arriving (e.g. a dropped link with an in-flight write whose ack was lost);
        /// the watchdog below resets the counter so the flush loop self-heals.
        private var maxedFlushStreak = 0
        /// Number of flush intervals at full backpressure before forcing a reset.
        /// At the default 125 Hz this is ~160 ms; at the 30 Hz floor ~670 ms.
        private let stallResetThreshold = 20
        /// Reads an Int setting, clamped to `range`, falling back to `fallback` when 0/absent.
        private func clampSetting(_ key: String, fallback: Int, range: ClosedRange<Int>) -> Int {
            let stored = UserDefaults.standard.integer(forKey: key)
            let raw = stored == 0 ? fallback : stored
            return min(max(raw, range.lowerBound), range.upperBound)
        }

        private var sendKeyboard: ((KeyboardReport) -> Void)?
        private var sendMouse: ((MouseReport, @escaping () -> Void) -> Void)?
        private var onRelease: (() -> Void)?

        /// User-configured shortcut that toggles capture while this controller is active.
        /// Set by `DirectInputShortcutManager`.
        var toggleHotkey: Hotkey?

        /// capture input and route it to HID backend
        func start(_ hid: HIDInput) {
            // Refuse to start when there is no way to stop (no toggle shortcut set) or no
            // host to forward to (subscription/connection count is 0). Surfaced via lastError.
            guard hid.isConnected else {
                lastError = L10n.DirectInput.noHostConnectedString
                return
            }
            guard toggleHotkey != nil else {
                lastError = L10n.DirectInput.needToggleHotkeyString
                return
            }
            start(sendKeyboard: hid.sendKeyboard, sendMouse: hid.sendMouse, onRelease: {})
        }

        func start(
            sendKeyboard: @escaping (KeyboardReport) -> Void,
            sendMouse: @escaping (MouseReport, @escaping () -> Void) -> Void,
            onRelease: @escaping () -> Void
        ) {
            stop()

            self.sendKeyboard = sendKeyboard
            self.sendMouse = sendMouse
            self.onRelease = onRelease
            let range = AppSettings.directInputMaxOutstandingWritesRange
            let def = AppSettings.defaultDirectInputMaxOutstandingWrites
            maxOutstandingWrites = clampSetting(AppSettings.directInputMaxOutstandingWritesKey, fallback: def, range: range)
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            lastError = nil

            guard AccessibilityPermission.isTrusted else {
                needsAccessibility = true
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
            startFlushTimer()
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
            sendMouse?(.zero) {}
            clearHandlers()
            isCapturing = false
            stopFlushTimer()
        }

        func clearAccessibilityRequest() {
            needsAccessibility = false
        }

        func clearError() {
            lastError = nil
        }

        private func clearHandlers() {
            sendKeyboard = nil
            sendMouse = nil
            onRelease = nil
        }

        private func handle(_ event: DirectInputEvent) {
            if case let .keyDown(key) = event.kind,
               let toggle = toggleHotkey,
               key == toggle.key,
               event.modifiers.collapsed == toggle.modifiers.collapsed
            {
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
                // Accumulate; the flush timer emits one report per interval regardless of input rate.
                accumDX += Int(dx)
                accumDY += Int(dy)
                hasPendingMovement = true
            case let .mouseButton(button, isDown):
                if isDown {
                    pressedMouseButtons.insert(button)
                } else {
                    pressedMouseButtons.remove(button)
                }
                // Button state is low-frequency; send immediately so press/release latches without waiting for the timer.
                sendMouse?(MouseReport(buttons: pressedMouseButtons)) {}
            case let .scroll(wheel):
                // Accumulate wheel ticks; flushed at the fixed cadence to avoid flooding the link.
                accumWheel += Int(wheel)
                hasPendingScroll = true
            }
        }

        private func sendKeyboardReport() {
            sendKeyboard?(KeyboardReport(
                modifiers: remapModifiersForWindows(modifiers),
                keys: Array(pressedKeys).prefix(6).map(\.self)
            ))
        }

        // MARK: Output coalescing

        /// Emits accumulated movement/scroll as HID reports at the fixed output cadence.
        /// Decouples the (potentially very high) local mouse polling rate from the rate
        /// the Classic Bluetooth HIDP link can drain, bounding latency to one interval.
        private func flush() {
            guard isCapturing else { return }

            // Safety net against a permanently elevated in-flight counter: if the
            // backpressure ceiling is held across many flush intervals (completions
            // stopped arriving), force it back to baseline so the loop resumes instead
            // of stalling. A healthy link oscillates below the ceiling each interval
            // (completions free a slot), so a sustained max only occurs on real stalls.
            if outstandingWrites >= maxOutstandingWrites {
                maxedFlushStreak += 1
                if maxedFlushStreak >= stallResetThreshold {
                    let ceiling = maxOutstandingWrites
                    log
                        .warning(
                            "DirectInput: outstanding writes stuck at ceiling (\(ceiling)); resetting backpressure counter"
                        )
                    outstandingWrites = 0
                    maxedFlushStreak = 0
                }
            } else {
                maxedFlushStreak = 0
            }

            if hasPendingMovement, outstandingWrites < maxOutstandingWrites {
                let dx = Self.clampAccum(accumDX)
                let dy = Self.clampAccum(accumDY)
                emit(MouseReport(buttons: pressedMouseButtons, dX: dx, dY: dy))
                accumDX = 0
                accumDY = 0
                hasPendingMovement = false
            }

            if hasPendingScroll, outstandingWrites < maxOutstandingWrites {
                let wheel = Self.clampAccum(accumWheel)
                emit(MouseReport(buttons: pressedMouseButtons, wheel: wheel))
                emit(MouseReport(buttons: pressedMouseButtons))
                accumWheel = 0
                hasPendingScroll = false
            }
        }

        /// Emits a mouse report and tracks it as in flight. `onSent` is invoked once the
        /// report has actually left the wire (Classic HIDP `l2capChannelWriteComplete`,
        /// Low Energy synchronously), keeping `outstandingWrites` bounded so the link never backs up.
        private func emit(_ report: MouseReport) {
            outstandingWrites += 1
            sendMouse?(report) { [weak self] in
                Task { @MainActor in self?.decrementOutstanding() }
            }
        }

        private func decrementOutstanding() {
            outstandingWrites = max(0, outstandingWrites - 1)
        }

        private static func clampAccum(_ value: Int) -> Int8 {
            Int8(max(-127, min(127, value)))
        }

        private func startFlushTimer() {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            let range = AppSettings.directInputOutputHzRange
            let def = AppSettings.defaultDirectInputOutputHz
            let interval = 1.0 / Double(clampSetting(AppSettings.directInputOutputHzKey, fallback: def, range: range))
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                Task { @MainActor in self?.flush() }
            }
            timer.resume()
            flushTimer = timer
        }

        private func stopFlushTimer() {
            flushTimer?.cancel()
            flushTimer = nil
            accumDX = 0
            accumDY = 0
            accumWheel = 0
            hasPendingMovement = false
            hasPendingScroll = false
            outstandingWrites = 0
            maxedFlushStreak = 0
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

    private struct DirectInputEvent {
        enum Kind {
            case keyDown(Keycode)
            case keyUp(Keycode)
            case flagsChanged
            case mouseMove(Int8, Int8)
            case mouseButton(MouseButtons, Bool)
            case scroll(Int8)
        }

        let kind: Kind
        let modifiers: KeyboardModifiers

        var key: Keycode? {
            switch kind {
            case let .keyDown(k), let .keyUp(k): k
            default: nil
            }
        }

        init?(type: CGEventType, event: CGEvent) {
            let flags = event.flags
            modifiers = KeyboardModifiers(eventFlags: flags)

            switch type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return nil
                }
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
            if flags.contains(.maskControl) {
                insert(.leftCtrl)
            }
            if flags.contains(.maskShift) {
                insert(.leftShift)
            }
            if flags.contains(.maskAlternate) {
                insert(.leftAlt)
            }
            if flags.contains(.maskCommand) {
                insert(.leftGUI)
            }
        }
    }

#elseif os(iOS)
    import CoreGraphics
    import Foundation
    import GameController
    import SwiftUI
    import UIKit

    @MainActor
    final class DirectInputController: ObservableObject {
        @Published private(set) var isCapturing = false
        @Published private(set) var lastError: String?
        @Published private(set) var hasInputDevice = false

        private var sendKeyboard: ((KeyboardReport) -> Void)?
        private var sendMouse: ((MouseReport, @escaping () -> Void) -> Void)?
        private var pressedKeys: Set<Keycode> = []
        private var pressedMouseButtons: MouseButtons = []
        private var modifiers: KeyboardModifiers = []
        private var observers: [NSObjectProtocol] = []

        // GCMouse deltas are in points; tune on-device
        private static let sensitivity: CGFloat = 1
        private static let scrollSensitivity: CGFloat = 1

        init() {
            refreshDevicePresence()
            observeDevices()
        }

        func start(_ hid: HIDInput) {
            start(sendKeyboard: hid.sendKeyboard, sendMouse: hid.sendMouse)
        }

        func start(
            sendKeyboard: @escaping (KeyboardReport) -> Void,
            sendMouse: @escaping (MouseReport, @escaping () -> Void) -> Void
        ) {
            stop()
            guard hasInputDevice else { return }

            self.sendKeyboard = sendKeyboard
            self.sendMouse = sendMouse
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            lastError = nil

            attachHandlers()
            isCapturing = true
        }

        func stop() {
            detachHandlers()
            if isCapturing {
                sendKeyboard?(.zero)
                sendMouse?(.zero) {}
            }
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            sendKeyboard = nil
            sendMouse = nil
            isCapturing = false
        }

        private func attachHandlers() {
            if let keyboard = GCKeyboard.coalesced {
                keyboard.handlerQueue = .main
                keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                    let raw = keyCode.rawValue
                    Task { @MainActor in self?.handleKey(raw: raw, pressed: pressed) }
                }
            }
            if let mouse = GCMouse.current {
                mouse.handlerQueue = .main
                let input = mouse.mouseInput
                input?.mouseMovedHandler = { [weak self] _, dx, dy in
                    Task { @MainActor in self?.handleMove(dx: dx, dy: dy) }
                }
                input?.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.left, pressed) }
                }
                input?.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.right, pressed) }
                }
                input?.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.middle, pressed) }
                }
                input?.scroll.valueChangedHandler = { [weak self] _, _, y in
                    Task { @MainActor in self?.handleScroll(y) }
                }
            }
        }

        private func detachHandlers() {
            GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
            if let input = GCMouse.current?.mouseInput {
                input.mouseMovedHandler = nil
                input.leftButton.pressedChangedHandler = nil
                input.rightButton?.pressedChangedHandler = nil
                input.middleButton?.pressedChangedHandler = nil
                input.scroll.valueChangedHandler = nil
            }
        }

        /// GCKeyCode raw values are HID usage IDs; 0xE0...0xE7 are modifier keys
        private func handleKey(raw: Int, pressed: Bool) {
            if (0xE0 ... 0xE7).contains(raw) {
                let mod = KeyboardModifiers(rawValue: UInt8(1) << UInt8(raw - 0xE0))
                if pressed {
                    modifiers.insert(mod)
                } else {
                    modifiers.remove(mod)
                }
            } else if let key = Keycode(rawValue: UInt8(truncatingIfNeeded: raw)) {
                if pressed {
                    pressedKeys.insert(key)
                } else {
                    pressedKeys.remove(key)
                }
            } else {
                return
            }
            if releaseComboHeld {
                stop()
                return
            }
            sendKeyboard?(KeyboardReport(modifiers: modifiers, keys: Array(pressedKeys.prefix(6))))
        }

        private var releaseComboHeld: Bool {
            !modifiers.isDisjoint(with: [.leftCtrl, .rightCtrl]) &&
                !modifiers.isDisjoint(with: [.leftAlt, .rightAlt])
        }

        private func handleMove(dx: Float, dy: Float) {
            let mx = HIDInput.clamp(CGFloat(dx) * Self.sensitivity)
            let my = HIDInput.clamp(CGFloat(-dy) * Self.sensitivity) // GC y is up-positive, HID is down-positive
            guard mx != 0 || my != 0 else { return }
            sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: mx, dY: my)) {}
        }

        private func handleButton(_ button: MouseButtons, _ pressed: Bool) {
            if pressed {
                pressedMouseButtons.insert(button)
            } else {
                pressedMouseButtons.remove(button)
            }
            sendMouse?(MouseReport(buttons: pressedMouseButtons)) {}
        }

        private func handleScroll(_ y: Float) {
            let wheel = HIDInput.clamp(CGFloat(y) * Self.scrollSensitivity)
            guard wheel != 0 else { return }
            sendMouse?(MouseReport(buttons: pressedMouseButtons, wheel: wheel)) {}
            sendMouse?(MouseReport(buttons: pressedMouseButtons)) {}
        }

        private func refreshDevicePresence() {
            hasInputDevice = GCKeyboard.coalesced != nil || GCMouse.current != nil
        }

        private func observeDevices() {
            let names: [Notification.Name] = [
                .GCKeyboardDidConnect, .GCKeyboardDidDisconnect, .GCMouseDidConnect, .GCMouseDidDisconnect
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.refreshDevicePresence()
                        if self.isCapturing {
                            self.attachHandlers()
                        }
                        if !self.hasInputDevice {
                            self.stop()
                        }
                    }
                }
                observers.append(token)
            }
        }
    }

    /// iPadOS pointer lock hides system pointer so GameController receives raw deltas
    struct PointerLockHost: UIViewControllerRepresentable {
        var locked: Bool

        func makeUIViewController(context: Context) -> PointerLockController {
            PointerLockController()
        }

        func updateUIViewController(_ controller: PointerLockController, context: Context) {
            controller.locked = locked
        }
    }

    final class PointerLockController: UIViewController {
        var locked = false {
            didSet {
                guard locked != oldValue else { return }
                setNeedsUpdateOfPrefersPointerLocked()
            }
        }

        override var prefersPointerLocked: Bool {
            locked
        }
    }
#endif
