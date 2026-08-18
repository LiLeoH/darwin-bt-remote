#if os(macOS)
    import AppKit
    import Combine
    import SwiftUI

    /// Owns the persistent full-screen red border shown while Direct Input is capturing.
    ///
    /// The border is intentionally decoupled from the main window's lifecycle: Direct Input is
    /// most often toggled via a global hotkey or the menu-bar item while the main window is closed
    /// (the app stays resident — see `AppDelegate`). A window-anchored banner is therefore
    /// insufficient. This controller creates one borderless, click-through overlay window per
    /// `NSScreen`, floating above full-screen Spaces, so the capture state is always visible.
    ///
    /// Visibility is gated by `AppSettings.directInputIndicatorEnabledKey` (default `true`) so a
    /// user in a long capture session can disable the border without losing the menu-bar/tooltip
    /// signals.
    @MainActor
    final class CaptureIndicatorController: ObservableObject {
        static let shared = CaptureIndicatorController()

        private weak var directInput: DirectInputController?
        private var cancellables = Set<AnyCancellable>()
        private var borderWindows: [NSWindow] = []

        private init() {}

        /// Called once from the root view with the live controller.
        func attach(directInput: DirectInputController) {
            guard self.directInput == nil else { return }
            self.directInput = directInput

            // Primary trigger: capture state flips.
            directInput.$isCapturing
                .receive(on: RunLoop.main)
                .sink { [weak self] capturing in self?.update(capturing: capturing) }
                .store(in: &cancellables)

            // React live to the settings toggle (AppStorage writes to UserDefaults).
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self, let di = self.directInput else { return }
                    update(capturing: di.isCapturing)
                }
                .store(in: &cancellables)

            // Rebuild on display hot-plug / resolution change so the border tracks the layout.
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self, let di = self.directInput, di.isCapturing, isEnabled else { return }
                    rebuild()
                }
                .store(in: &cancellables)
        }

        /// Removes all overlay windows; call from app termination.
        func shutdown() {
            teardown()
            cancellables.removeAll()
        }

        private var isEnabled: Bool {
            // Defaults are registered as `true` in BTRemoteApp; fall back to `true` defensively.
            UserDefaults.standard.object(forKey: AppSettings.directInputIndicatorEnabledKey) as? Bool ?? true
        }

        private func update(capturing: Bool) {
            if capturing, isEnabled {
                if borderWindows.isEmpty {
                    rebuild()
                }
            } else {
                teardown()
            }
        }

        private func rebuild() {
            teardown()
            borderWindows = NSScreen.screens.map(makeWindow(for:))
        }

        private func makeWindow(for screen: NSScreen) -> NSWindow {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // Never intercept input: the overlay is purely visual and must not break capture.
            window.ignoresMouseEvents = true
            // Float above full-screen apps and the menu bar.
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

            let exitHotkey = directInput?.toggleHotkey?.displayString
            let host = NSHostingView(rootView: CaptureBorderView(exitHotkey: exitHotkey))
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }

        private func teardown() {
            for window in borderWindows {
                window.orderOut(nil)
            }
            borderWindows.removeAll()
        }
    }
#endif
