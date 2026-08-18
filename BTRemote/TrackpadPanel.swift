import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct TrackpadPanel: View {
    let hid: HIDInput

    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity

    var body: some View {
        VStack(spacing: cellGap) {
            HStack(spacing: cellGap) {
                surface
                scrollColumn.frame(width: 46)
            }
            .frame(maxHeight: .infinity)
            mouseButtonsRow.frame(height: 52)
        }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(groupFill)
            #if os(iOS)
                TouchpadView(
                    moveSensitivity: touchpadSensitivity,
                    scrollSensitivity: scrollSensitivity,
                    onMove: { hid.move(dx: $0, dy: $1) },
                    onScroll: { hid.scroll($0) },
                    onLeftClick: { Haptics.tap(); hid.click(.left) },
                    onRightClick: { Haptics.tap(); hid.click(.right) }
                )
            #endif
            #if os(macOS)
                MacTrackpadSurface(
                    hid: hid,
                    moveSensitivity: touchpadSensitivity,
                    scrollSensitivity: scrollSensitivity
                )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
            .contentShape(Rectangle())
        #endif
    }

    private var scrollAmount: Int8 {
        max(1, HIDInput.clamp(CGFloat(3 * scrollSensitivity)))
    }

    private var scrollColumn: some View {
        VStack(spacing: cellGap) {
            scrollButton("arrow.up", L10n.Mouse.wheelUp, scrollAmount)
            scrollButton("arrow.down", L10n.Mouse.wheelDown, -scrollAmount)
        }
    }

    private var mouseButtonsRow: some View {
        HStack(spacing: cellGap) {
            mouseButton(.left, L10n.Mouse.leftButton)
            mouseButton(.middle, L10n.Mouse.middleButton)
            mouseButton(.right, L10n.Mouse.rightButton)
        }
    }

    private func mouseButton(_ button: MouseButtons, _ label: LocalizedStringKey) -> some View {
        HoldButton(
            onPress: { hid.sendMouse(MouseReport(buttons: button)) {} },
            onRelease: { hid.sendMouse(.zero) {} },
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Color.clear }
        )
        .accessibilityLabel(label)
    }

    private func scrollButton(_ icon: String, _ label: LocalizedStringKey, _ wheel: Int8) -> some View {
        HoldButton(
            onPress: { hid.scroll(wheel) },
            onRelease: {},
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Image(systemName: icon).font(.body) }
        )
        .accessibilityLabel(label)
    }
}

#if os(macOS)
    /// Native macOS trackpad surface. Replaces the previous SwiftUI drag/tap gestures so the
    /// surface can forward the full set of pointer events and pin the local cursor:
    /// - hold **Option** with the pointer inside the surface → pin the local cursor at the
    ///   current point and stream movement to the remote (the local cursor stays motionless,
    ///   so only the movement deltas are mirrored to the remote host);
    /// - physical left-click → forward a left button press/release (click sync);
    /// - physical right-click → forward a right click to the remote;
    /// - scroll-wheel → forward wheel ticks to the remote.
    struct MacTrackpadSurface: NSViewRepresentable {
        let hid: HIDInput
        var moveSensitivity: CGFloat
        var scrollSensitivity: CGFloat

        func makeNSView(context: Context) -> NSView {
            let view = TrackpadNSView()
            view.apply(hid: hid, moveSensitivity: moveSensitivity, scrollSensitivity: scrollSensitivity)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if let view = nsView as? TrackpadNSView {
                view.apply(hid: hid, moveSensitivity: moveSensitivity, scrollSensitivity: scrollSensitivity)
            }
        }
    }

    final class TrackpadNSView: NSView {
        private var hid: HIDInput?
        private var moveSensitivity: CGFloat = 1
        private var scrollSensitivity: CGFloat = 1

        /// Buttons currently held down, so movement frames can carry them (HID mouse reports
        /// are full state snapshots; a drag needs the button present in every move frame).
        private var activeButtons: MouseButtons = []
        /// Pin-and-sync state, shared with the popover text field via `OptionCursorPin`.
        /// The surface pins the local cursor and streams movement to the remote only while the
        /// Option key is held with the pointer inside the surface.
        private var pointerInside = false
        private let optionPin = OptionCursorPin()
        private var resignObserver: NSObjectProtocol?

        func apply(hid: HIDInput, moveSensitivity: CGFloat, scrollSensitivity: CGFloat) {
            self.hid = hid
            self.moveSensitivity = moveSensitivity
            self.scrollSensitivity = scrollSensitivity
            optionPin.onMove = { [weak self] dx, dy in
                self?.sendMove(dx: dx, dy: dy)
            }
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            // Track the held button so subsequent movement reports keep the button pressed
            // (HID mouse reports are full state snapshots; a drag requires the button in every
            // move frame). Pinning is driven by the Option key, not by the mouse button.
            activeButtons.insert(.left)
            hid?.sendMouse(MouseReport(buttons: activeButtons)) {}
        }

        override func mouseUp(with event: NSEvent) {
            activeButtons.remove(.left)
            hid?.sendMouse(MouseReport(buttons: activeButtons)) {}
        }

        override func rightMouseDown(with event: NSEvent) {
            activeButtons.insert(.right)
            hid?.sendMouse(MouseReport(buttons: activeButtons)) {}
        }

        override func rightMouseUp(with event: NSEvent) {
            activeButtons.remove(.right)
            hid?.sendMouse(MouseReport(buttons: activeButtons)) {}
        }

        override func mouseDragged(with event: NSEvent) {
            // A left-button drag is an explicit interaction: always mirror the movement to
            // the remote, independent of the Option pin. The local cursor moves normally here
            // (pinning is reserved for the Option-key hover mode).
            forwardMove(event)
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.deltaY != 0 else { return }
            let wheel = Int8(max(1, HIDInput.clamp(CGFloat(3 * scrollSensitivity))))
            hid?.scroll(event.deltaY > 0 ? wheel : -wheel)
        }

        // MARK: - Pin (Option-key driven, via OptionCursorPin)

        private func forwardMove(_ event: NSEvent) {
            // NSEvent deltaX/deltaY follow the Quartz convention (x right+, y down+),
            // which matches HIDInput.move (dy positive = remote moves down). No sign flip.
            // Sensitivity is applied in `sendMove`.
            sendMove(dx: CGFloat(event.deltaX), dy: CGFloat(event.deltaY))
        }

        private func sendMove(dx: CGFloat, dy: CGFloat) {
            // Carry the currently held buttons so a left-drag becomes a real drag/box-select
            // on the remote (the button must be present in every move frame).
            let scaledX = HIDInput.clamp(dx * moveSensitivity)
            let scaledY = HIDInput.clamp(dy * moveSensitivity)
            hid?.sendMouse(MouseReport(buttons: activeButtons, dX: scaledX, dY: scaledY)) {}
        }

        override func mouseEntered(with event: NSEvent) {
            pointerInside = true
            optionPin.isEnabled = true
        }

        override func mouseExited(with event: NSEvent) {
            pointerInside = false
            optionPin.isEnabled = false
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if trackingAreas.isEmpty {
                let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
                addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                window.acceptsMouseMovedEvents = true
                optionPin.activate()
                if resignObserver == nil {
                    resignObserver = NotificationCenter.default.addObserver(
                        forName: NSApplication.didResignActiveNotification,
                        object: nil,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.optionPin.cancelPin()
                            self?.hid?.sendMouse(.zero) {}
                        }
                    }
                }
            } else {
                optionPin.deactivate()
                if let token = resignObserver {
                    NotificationCenter.default.removeObserver(token)
                    resignObserver = nil
                }
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let token = resignObserver {
                    NotificationCenter.default.removeObserver(token)
                }
            }
            // The owned `optionPin` tears down its monitors and re-enables cursor
            // association on its own deinit, so nothing to clean up here.
        }
    }
#endif
