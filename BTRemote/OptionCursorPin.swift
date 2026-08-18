#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation

    /// Encapsulates the Option-key "pin and stream" cursor behavior shared by the macOS
    /// trackpad surface and the menu-bar popover's text field.
    ///
    /// While the Option modifier is held *and* `isEnabled` is true, the local cursor is
    /// frozen in place (`CGAssociateMouseAndMouseCursorPosition(0)`) and pointer movement
    /// deltas are forwarded to `onMove`. Releasing Option restores cursor association and
    /// warps the pointer back to the pin point, matching the trackpad's hover-pin feel.
    ///
    /// When `onMoveWithButtons` is also set (the popover case), mouse button presses are
    /// forwarded too, so clicking/dragging while pinned drives the remote just like the
    /// touchpad. The trackpad does not set these callbacks — it forwards clicks itself via
    /// its own `NSView` overrides — so this helper stays out of its click path.
    final class OptionCursorPin: NSObject, ObservableObject {
        /// Forwarded raw Quartz-style movement deltas (x right+, y down+) while pinned.
        var onMove: ((CGFloat, CGFloat) -> Void)?

        /// Like `onMove`, but also carries the currently held mouse buttons so a drag while
        /// pinned becomes a real drag/box-select on the remote. Set this (instead of `onMove`)
        /// to enable click + drag forwarding; it also arms the button monitors below.
        var onMoveWithButtons: ((CGFloat, CGFloat, MouseButtons) -> Void)?

        /// Forwarded on a mouse-button press/release while pinned (only used with
        /// `onMoveWithButtons`). A pure click with no movement still reaches the remote.
        var onButtonDown: ((MouseButtons) -> Void)?
        var onButtonUp: ((MouseButtons) -> Void)?

        /// Caller-controlled gate. On the trackpad this is "pointer inside the surface"; in the
        /// popover it is "the text field is focused". Disabling while pinned cancels the pin.
        var isEnabled = false {
            didSet {
                guard isEnabled != oldValue else { return }
                if isEnabled {
                    updatePinState()
                } else {
                    stopPin()
                }
            }
        }

        private var pinned = false
        private var pinStart: CGPoint = .zero
        private var optionDown = false
        private var activeButtons: MouseButtons = []
        private var optionMonitor: Any?
        private var mouseMonitor: Any?
        private var clickMonitors: [Any] = []

        func activate() {
            installMonitors()
        }

        func deactivate() {
            removeMonitors()
            cancelPin()
        }

        private func installMonitors() {
            if optionMonitor == nil {
                optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.applyOptionFlag(event.modifierFlags.contains(.option))
                    return event
                }
            }
            if mouseMonitor == nil {
                // While a button is held macOS replaces mouseMoved with *Dragged events. Only
                // the button-forwarding mode (popover) needs them here — the trackpad surface
                // forwards drags via its own mouseDragged override, and matching them in the
                // monitor too would double every drag frame.
                let mask: NSEvent.EventTypeMask = onMoveWithButtons != nil
                    ? [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
                    : [.mouseMoved]
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    self?.forwardPinnedMove(dx: CGFloat(event.deltaX), dy: CGFloat(event.deltaY))
                    return event
                }
            }
            if onMoveWithButtons != nil {
                installButtonMonitors()
            }
        }

        private func installButtonMonitors() {
            // activate() may be called more than once over the pin's lifetime; install only once.
            guard clickMonitors.isEmpty else { return }
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleMouseDown(.left, event: event) ?? event
            })
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.handleMouseUp(.left, event: event) ?? event
            })
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                self?.handleMouseDown(.right, event: event) ?? event
            })
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
                self?.handleMouseUp(.right, event: event) ?? event
            })
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                self?.handleMouseDown(.middle, event: event) ?? event
            })
            clickMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
                self?.handleMouseUp(.middle, event: event) ?? event
            })
        }

        private func removeMonitors() {
            if let monitor = optionMonitor {
                NSEvent.removeMonitor(monitor)
                optionMonitor = nil
            }
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
            for token in clickMonitors {
                NSEvent.removeMonitor(token)
            }
            clickMonitors.removeAll()
        }

        /// Button events are observed, never consumed: consuming the mouseDown would prevent
        /// AppKit from starting a drag session, and the subsequent *Dragged events would be
        /// dropped before reaching any monitor — killing drag forwarding. Letting the event
        /// through matches the trackpad surface, which also never consumes clicks.
        private func handleMouseDown(_ button: MouseButtons, event: NSEvent) -> NSEvent? {
            guard pinned else { return event }
            activeButtons.insert(button)
            onButtonDown?(button)
            return event
        }

        private func handleMouseUp(_ button: MouseButtons, event: NSEvent) -> NSEvent? {
            guard pinned else { return event }
            activeButtons.remove(button)
            onButtonUp?(button)
            return event
        }

        private func applyOptionFlag(_ value: Bool) {
            optionDown = value
            updatePinState()
        }

        private static func currentButtons() -> MouseButtons {
            MouseButtons(rawValue: UInt8(NSEvent.pressedMouseButtons & 0x07))
        }

        private func forwardPinnedMove(dx: CGFloat, dy: CGFloat) {
            guard pinned else { return }
            // Heal any button we believe is held but the OS no longer reports as pressed
            // (e.g. a mouseUp the local monitor didn't observe). This keeps a real release
            // from turning into a stuck drag where every later move re-sends the button.
            activeButtons = activeButtons.intersection(Self.currentButtons())
            if let onMoveWithButtons {
                onMoveWithButtons(dx, dy, activeButtons)
            } else {
                onMove?(dx, dy)
            }
        }

        private func updatePinState() {
            if optionDown, isEnabled, !pinned {
                startPin()
            } else if pinned, !optionDown || !isEnabled {
                stopPin()
            }
        }

        private func startPin() {
            pinned = true
            pinStart = CGEvent(source: nil)?.location ?? .zero
            CGAssociateMouseAndMouseCursorPosition(0)
        }

        private func stopPin() {
            guard pinned else { return }
            pinned = false
            if !activeButtons.isEmpty {
                // Release any button still held when the pin ended so the remote isn't left
                // with a stuck mouse button.
                onButtonUp?(activeButtons)
                activeButtons = []
            }
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(pinStart)
        }

        /// Force the pin to end without warping (used when the app loses focus).
        func cancelPin() {
            guard pinned else { return }
            pinned = false
            if !activeButtons.isEmpty {
                onButtonUp?(activeButtons)
                activeButtons = []
            }
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        deinit {
            if let monitor = optionMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
            }
            for token in clickMonitors {
                NSEvent.removeMonitor(token)
            }
            // Never leave cursor association disabled if torn down mid-pin.
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }
#endif
