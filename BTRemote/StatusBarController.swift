#if os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    /// A always-present menu-bar item giving quick access to Windows shortcuts and the
    /// Direct Input toggle, independent of the main window (which the user may close).
    ///
    /// This replaces the transient capture-only status item that `DirectInputController`
    /// used to show: the icon now lives for the whole session and reflects capture state
    /// by tinting red while Direct Input is active.
    @MainActor
    final class StatusBarController: ObservableObject {
        static let shared = StatusBarController()

        private var statusItem: NSStatusItem?
        private var popover: NSPopover?
        private weak var directInput: DirectInputController?
        private var buildHID: (() -> HIDInput)?
        private var cancellables = Set<AnyCancellable>()
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var openMainWindowAction: (() -> Void)?

        private init() {}

        /// Called once from the root view with the live controller and a HID builder.
        func attach(directInput: DirectInputController, buildHID: @escaping () -> HIDInput, openMainWindow: @escaping () -> Void) {
            self.directInput = directInput
            self.buildHID = buildHID
            openMainWindowAction = openMainWindow
            ensureStatusItem()
            observeCaptureState()
        }

        private func ensureStatusItem() {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                configure(button: button, capturing: directInput?.isCapturing == true)
                button.action = #selector(togglePopover(_:))
                button.target = self
            }
            statusItem = item

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 320, height: 500)
            self.popover = popover
        }

        private func configure(button: NSStatusBarButton, capturing: Bool) {
            let symbol = capturing ? "keyboard" : "bolt.horizontal.fill"
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [capturing ? .systemRed : .systemBlue]))
            icon?.isTemplate = false
            button.image = icon
            button.imagePosition = .imageLeading
            button.toolTip = capturing
                ? String(localized: "status_bar.tooltip_capturing")
                : String(localized: "status_bar.tooltip_idle")
        }

        private func observeCaptureState() {
            guard let directInput else { return }
            directInput.$isCapturing
                .receive(on: RunLoop.main)
                .sink { [weak self] capturing in
                    guard let self, let button = statusItem?.button else { return }
                    configure(button: button, capturing: capturing)
                }
                .store(in: &cancellables)
        }

        @objc private func togglePopover(_ sender: NSStatusBarButton) {
            guard let popover else { return }
            if popover.isShown {
                closePopover()
            } else {
                presentPopover()
            }
        }

        private func presentPopover() {
            guard let popover, let button = statusItem?.button, let di = directInput, let hid = buildHID?() else { return }
            popover.contentViewController = NSHostingController(
                rootView: StatusBarMenuView(
                    directInput: di,
                    hid: hid,
                    send: { [weak self] shortcut in self?.send(shortcut) },
                    toggleDirectInput: { [weak self] in self?.toggleDirectInput() },
                    openMainWindow: { [weak self] in self?.openMainWindow() }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Let the popover window receive mouse-moved events so the focused text field's
            // Option-key cursor-pin (see StatusBarMenuView) can stream movement deltas.
            popover.contentViewController?.view.window?.acceptsMouseMovedEvents = true
            addEventMonitors()
        }

        private func closePopover() {
            removeEventMonitors()
            popover?.performClose(nil)
        }

        /// Closes the popover when the user clicks anywhere outside it, including desktop
        /// space where no other window exists. `behavior = .transient` only handles clicks
        /// on other *windows*, so this monitor is required for the click-empty-space case.
        private func addEventMonitors() {
            guard localMonitor == nil, globalMonitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handleOutsideClick(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handleOutsideClick(event)
            }
        }

        private func removeEventMonitors() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
        }

        private func handleOutsideClick(_ event: NSEvent) {
            guard let popover, popover.isShown,
                  let window = popover.contentViewController?.view.window else { return }
            let clickPoint = NSEvent.mouseLocation
            // clicks inside the popover, or on the status-bar button itself, are ignored
            // so the button's own toggle logic can run and internal controls stay usable
            if window.frame.contains(clickPoint) {
                return
            }
            if let buttonFrame = statusItem?.button?.window?.frame, buttonFrame.contains(clickPoint) {
                return
            }
            closePopover()
        }

        private func send(_ shortcut: WindowsShortcut) {
            guard let hid = buildHID?() else { return }
            let down = KeyboardReport(modifiers: shortcut.modifiers, keys: shortcut.keys)
            // pace the release so a rapid identical press is not coalesced and lost
            hid.sendKeyboard(down)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                hid.sendKeyboard(.zero)
            }
        }

        private func toggleDirectInput() {
            guard let directInput else { return }
            if directInput.isCapturing {
                directInput.stop()
                return
            }
            guard AccessibilityPermission.isTrusted else {
                AccessibilityPermission.request()
                return
            }
            guard let hid = buildHID?() else { return }
            directInput.start(hid)
        }

        private func openMainWindow() {
            closePopover()
            openMainWindowAction?()
        }

        /// Removes the menu-bar item; call from app termination.
        func shutdown() {
            removeEventMonitors()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            popover = nil
            cancellables.removeAll()
        }
    }
#endif
