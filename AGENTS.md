# AGENTS.md — BTRemote

Guidance for autonomous coding agents and contributors working on this repository.

## 1. What this project is

**BTRemote** is an open-source SwiftUI app that turns an iPhone, iPad, or Mac into a
**Bluetooth HID (Human Interface Device)** — a generic keyboard, mouse, and trackpad —
for any host that accepts standard Bluetooth input (Windows, Linux, macOS, iOS/iPadOS,
tvOS, Android, ChromeOS, SteamOS, etc.). It needs **no companion app on the target**:
the Apple device presents itself as a standard Bluetooth HID and streams input directly.

- Repository: `https://github.com/jqssun/darwin-bt-remote`
- License: **AGPL-3.0-only**
- Bundle ID: `io.github.jqssun.btremote`
- Display name: **Bluetooth Remote**

### Architecture at a glance

```
UI (SwiftUI) ──> HIDInput (backend-agnostic router)
                       │
         ┌─────────────┴──────────────┐
   LowEnergy backend              Classic backend
   (iOS + macOS, HOGP)            (macOS only, HIDP)
   HIDPeripheral + HIDCentral     HIDClassicDevice + SDPRecord
                       │
              Shared HID model (HIDReports, HIDProfile)
```

The app exposes **two HID transport backends** and picks the right one per platform:

| Backend | Profile | Platform | Core files | Mechanism |
|---|---|---|---|---|
| **Low Energy (HOGP)** | HID over GATT | iOS + macOS | `LowEnergy/HIDPeripheral.swift`, `LowEnergy/HIDCentral.swift` | `CBPeripheralManager` builds the GATT HID tree; the Apple device is the **peripheral** (device role) |
| **Classic (HIDP)** | HID Profile | macOS only | `Classic/HIDClassicDevice.swift`, `Classic/SDPRecord.swift` | `IOBluetooth` publishes an SDP record and opens L2CAP **control (0x0011)** + **interrupt (0x0013)** channels to a paired host |

Both backends emit the **same HID report descriptors** (see §5) supporting mouse, keyboard,
LED output, consumer (multimedia), system control, and battery.

A third capability, **Direct Input**, forwards the user's *local* hardware input straight
to the remote target. Implemented in `DirectInputController.swift`:
- **macOS**: `CGEvent` tap (requires Accessibility permission) captures keyboard/mouse/scroll.
- **iOS**: `GameController` (`GCKeyboard`/`GCMouse`) + pointer lock for raw deltas.

## 2. Repository layout

```
darwin-bt-remote/
├── AGENTS.md                 # this file
├── README.md                 # user-facing overview + platform caveats
├── LICENSE                   # AGPL-3.0-only
├── project.yml               # XcodeGen spec (the source of truth for the Xcode project)
├── build.sh                  # local dev build: format/lint + build macOS & iOS .ipa
├── ci_scripts/
│   └── ci_post_clone.sh      # CI bootstrap: install xcodegen, fetch JSON datasets, generate
├── fastlane/
│   ├── Fastfile              # release/build lanes (match + gym) for ios & mac
│   ├── Appfile
│   └── metadata, screenshots # store metadata
├── tools/
│   ├── win_clipboard_sync.py # Windows clipboard sync companion (Python, bleak)
│   └── README.md             # Setup & troubleshooting for the Windows companion
└── BTRemote/
    ├── BTRemoteApp.swift     # @main App; owns backend instances; macOS transport switching;
    │                         #   embeds a macOS AppDelegate (keeps app resident, tears down status bar)
    ├── ClipboardSyncProfile.swift # GATT UUIDs + chunking protocol + Reassembler (macOS-only);
    │                         #   nonisolated(unsafe) static let UUIDs, pack/unpack helpers;
    │                         #   msgType 0x01=text, 0x02=image(JPEG); SHA-256[:4] hash
    ├── ClipboardSyncController.swift # NSPasteboard poller + GATT send/receive + hash loop guard
    │                         #   (macOS-only); attaches to HIDPeripheral via closure bridge;
    │                         #   image=JPEG(q75) on wire; send watchdog 5s; floating progress window
    ├── ContentView.swift      # TabView: Setup / Keyboard / Remote / Settings; wires shortcut +
    │                         #   status-bar managers; toggle banner when Direct Input starts/stops
    ├── Info.plist            # BT usage strings, background modes, orientation
    ├── entitlements.plist    # app-sandbox + bluetooth device entitlement (macOS)
    ├── PrivacyInfo.xcprivacy  # Apple privacy manifest
    ├── Assets.xcassets       # AppIcon, AccentColor
    ├── Resources/
    │   ├── company_ids.json  # Bluetooth SIG company codes (fetched if missing)
    │   └── service_uuids.json# Bluetooth SIG service UUIDs (fetched if missing)
    ├── LowEnergy/
    │   ├── HIDProfile.swift  # HID UUIDs + the 239-byte report map + ReportID/Type
    │   ├── HIDReports.swift  # Report data structs + Keycode/ConsumerKey enums; ALSO owns the
    │   │                     #   Keycode.displayName / macVirtualKey / macVirtualKeys table
    │   ├── HIDPeripheral.swift # CBPeripheralManager GATT engine (server/device role)
    │   └── HIDCentral.swift  # CBCentralManager scanner + connection-event registrar
    ├── Classic/
    │   ├── HIDClassicDevice.swift # IOBluetooth L2CAP engine + HIDP transaction handling;
    │   │                         #   _WriteAck refcon carries write-completion through l2capChannelWriteComplete
    │   └── SDPRecord.swift   # Builds the classic HID SDP service record
    ├── HIDInput.swift         # Backend-agnostic router; tap/click/move/scroll/type helpers;
    │                         #   sendMouse carries an onSent completion so callers can track in-flight writes
    ├── DirectInputController.swift # Local input capture → HID (macOS CGEvent / iOS GameController);
    │                         #   user-configurable `toggleHotkey`; capture/send DECOUPLED via fixed-cadence
    │                         #   flush (outputReportHz) + in-flight backpressure (maxOutstandingWrites)
    ├── ModifierRemap.swift   # (macOS) remap local modifiers to Windows convention for DI forwarding
    ├── AppSettings.swift      # Centralized UserDefaults keys + constants
    ├── BluetoothNumbers.swift # Lookup helpers for company/service names
    ├── AccessibilityPermission.swift # macOS AXIsProcessTrusted wrapper
    ├── DeviceNameStore.swift  # Per-device display-name persistence
    ├── L10n.swift, L10nExtensions.swift # Localization keys (LocalizedStringKey) + string helpers
    ├── Localizable.xcstrings, InfoPlist.xcstrings # Localized strings
    ├── HIDTextSender.swift    # Shared "type text → HID keyboard reports" editor (TextField + KeyTypist);
    │                         #   used by KeyboardView AND the menu-bar popover; no AX permission needed
    ├── WindowsShortcuts.swift # WindowsShortcut model + windowsShortcuts chord list (shared UI data)
    ├── Hotkey.swift           # (macOS) Codable user shortcut; displayString / match / conflict checks
    ├── ShortcutRecorder.swift # (macOS) HotkeyRecorder SwiftUI view + RecorderEngine (captures a combo)
    ├── DirectInputHotkeyMonitor.swift # (macOS) global+local NSEvent monitor for the toggle Hotkey
    ├── DirectInputShortcutManager.swift # (macOS) singleton owning the persisted toggle Hotkey
    ├── OptionCursorPin.swift  # (macOS) shared Option-key "pin & stream" cursor engine
    │                         #   (NSObject/ObservableObject); freezes the local cursor via
    │                         #   CGAssociateMouseAndMouseCursorPosition and forwards movement (and,
    │                         #   in the popover, button press/drag) to the remote. Used by BOTH
    │                         #   TrackpadNSView (trackpad surface) and StatusBarMenuView (popover).
    ├── StatusBarController.swift # (macOS) always-present menu-bar item + NSPopover (app stays resident)
    ├── StatusBarMenuView.swift  # (macOS) popover content: text send, Windows shortcuts, DI toggle
    ├── CaptureIndicatorController.swift # (macOS) singleton drawing a persistent red border on every
    │                         #   screen while Direct Input captures; observes isCapturing + settings
    │                         #   toggle + screen changes; attach from ContentView, shutdown on quit
    ├── CaptureBorderView.swift # (macOS) SwiftUI red-frame + corner badge + gray dimming mask for the
    │                         #   Direct Input capture indicator
    ├── SetupView.swift        # Setup tab: pairing/getting-started instructions
    ├── GuideView.swift        # Detailed pairing walkthrough sheet
    ├── KeyboardView.swift     # On-screen keyboard + text sender + Windows shortcut chips
    ├── RemoteView.swift       # Trackpad / D-pad / consumer-control remote surface
    ├── SettingsView.swift     # Settings: Direct Input hotkey recorder, output-report rate, max-in-flight
    ├── Controls.swift         # Reusable PressGesture / HoldButton
    ├── TouchpadView.swift     # In-app trackpad surface (iOS)
    ├── TrackpadPanel.swift    # (macOS) Keyboard-tab trackpad surface; the macOS side is a native
    │                         #   NSView (TrackpadNSView) that pins the cursor on Option and forwards
    │                         #   held-button drags / right-click / wheel to the remote host
    ├── DPadView.swift         # Directional pad (iOS)
    ├── DeviceListView.swift   # Discovered/paired device list (classic/HIDP)
    ├── DeviceRow.swift        # Single device row
    └── DeviceInfoView.swift   # Per-device detail
```

> **macOS-only source** (fully excluded on iOS via `#if os(macOS)`): `Classic/*`,
> `DirectInputController` macOS branch, `ModifierRemap`, `AccessibilityPermission`, `Hotkey`, `ShortcutRecorder`,
> `DirectInputHotkeyMonitor`, `DirectInputShortcutManager`, `StatusBarController`, `StatusBarMenuView`,
> `CaptureIndicatorController`, `CaptureBorderView`,
> and the `AppDelegate` inside `BTRemoteApp.swift`.

## 3. Build & development

The Xcode project is **generated**, not committed. Always regenerate before opening in Xcode.

### Prerequisites
- macOS with Xcode 15+ (toolchain sets `SWIFT_VERSION: 6.0`).
- Command-line tools: `xcodegen`, `swiftformat`, `swiftlint`, `xcbeautify`.
  ```bash
  brew install xcodegen swiftformat swiftlint xcbeautify
  ```
- Deployment targets: **iOS 15.0**, **macOS 13.0**.

### Generate the project
```bash
# equivalent to what CI runs:
ci_scripts/ci_post_clone.sh     # installs xcodegen if needed, fetches JSON, then:
xcodegen generate               # produces BTRemote.xcodeproj from project.yml
```

### Local build (ad-hoc, unsigned)
```bash
./build.sh
```
What it does:
1. Runs `swiftformat --lint .` and `swiftlint lint --strict` (both must pass — CI fails otherwise).
2. Builds the **macOS** scheme `Release` with `CODE_SIGNING_ALLOWED=NO`, then ad-hoc codesigns
   the `.app` with `entitlements.plist`.
3. If the iOS SDK is available (probed via `xcrun --sdk iphoneos --show-sdk-path`), builds
   **iOS** and packages a `.ipa` under `.build/`; if the SDK is missing the iOS step is skipped
   gracefully rather than failing the whole script.

### Testing
There is **no automated test target** in `project.yml` (single application target only).
Verification is: (a) `build.sh` green, (b) manual pairing/streaming on real hardware.
Do not assume unit tests exist; if you add behavior, prefer adding a test target in
`project.yml` rather than relying on none.

## 4. UI structure (SwiftUI)

- **`BTRemoteApp`** (`@main`): instantiates the backend controllers as `@StateObject`s and
  injects them via `.environmentObject(...)`. On macOS it adds a `TransportMode`
  environment value, tears down the inactive backend when the user switches transport, and
  registers a macOS **`AppDelegate`** (`@NSApplicationDelegateAdaptor`) so the app stays
  resident after the main window closes (`applicationShouldTerminateAfterLastWindowClosed`
  returns `false`) and tears down the status bar on quit.
- **`ContentView`**: a `TabView` with **Setup**, **Keyboard**, **Remote**, **Settings** tabs.
  It owns a single `DirectInputController` (`@StateObject`) and builds the active `HIDInput`
  router via `HIDInput.make(...)`. On macOS it also attaches `DirectInputShortcutManager.shared`
  and `StatusBarController.shared` (each with a `buildHID` closure), injects the shortcut
  manager into the environment, and shows a transient banner when Direct Input toggles.
- **`HIDInput`** is the single integration seam between UI and transport. UI calls
  `tap/click/move/scroll/type/typeWord`; the router forwards to the active backend's
  `sendMouse/sendKeyboard/sendConsumer`. **Add new input features here, not in the backends.**
- **macOS menu bar (`StatusBarController` + `StatusBarMenuView`)**: an always-present
  `NSStatusItem` (independent of the main window) that opens an `NSPopover` with quick access
  to the text sender, the **Windows shortcuts** grid, and a Direct Input start/stop button.
  Its icon tints red while capture is active. This replaced the transient capture-only status
  item that `DirectInputController` used to show.

  - **Option-key pin inside the popover**: when the text field is focused and the **Option** key
    is held, the same `OptionCursorPin` engine pins the local cursor and streams movement (plus
    mouse-button press/drag when `onMoveWithButtons` is set) to the remote — mirroring the
    trackpad's hover-pin. Implementation notes (do not regress):
    - The pin is gated solely by text-field focus (`@FocusState textFieldFocused` →
      `optionPin.isEnabled`), **not** by cursor position — so the cursor is not frozen to keep it
      inside the view (unlike the trackpad, whose `mouseExited` would otherwise end the pin).
    - The popover's button monitors **observe but never consume** (`return nil`) mouse events:
      consuming the `mouseDown` stops AppKit from starting a drag session, so the subsequent
      `*Dragged` events are dropped before any monitor sees them and drag forwarding dies.
    - `OptionCursorPin.forwardPinnedMove` intersects the tracked `activeButtons` with
      `NSEvent.pressedMouseButtons` on every move so a missed `mouseUp` can't leave a stuck
      button (a real release self-heals on the next move).
    - `StatusBarController.presentPopover()` sets `window.acceptsMouseMovedEvents = true` so the
      focused text field receives movement deltas.
    - Monitor lifetime is tied to the popover, not the view: SwiftUI `onDisappear` is unreliable
      inside a popover whose hosting controller `StatusBarController` retains, so teardown uses
      `NSPopover.didCloseNotification` (`optionPin.deactivate()`) — this is what keeps the pin from
      leaking out and triggering while, e.g., a Dock menu is showing.
- **Direct Input capture indicator (macOS)**: `CaptureIndicatorController.shared` draws a persistent
  full-screen **red border** (plus a top-leading "Direct Input" badge) on **every `NSScreen`** while
  capture is active. It also paints a full-screen **gray dimming mask** (`CaptureBorderView`'s
  `maskOpacity = 0.35`, a `Color.gray` layer beneath the red border) so the capture state is
  unmistakable; the mask does **not** intercept input (`allowsHitTesting(false)`). The overlay
  windows are borderless, `ignoresMouseEvents = true` (purely visual,
  never break capture), `level = .screenSaver`, and `collectionBehavior` joins all Spaces — so the
  signal survives a closed main window and full-screen Spaces. It observes
  `DirectInputController.$isCapturing` and the `directInputIndicatorEnabledKey` setting (default
  `true`, toggle in **Settings → Capture Border**), and rebuilds on
  `NSApplication.didChangeScreenParametersNotification` (display hot-plug). Attach once from
  `ContentView._onAppear`; `shutdown()` runs in `AppDelegate.applicationWillTerminate`.
- **macOS trackpad surface — native `NSView` (`TrackpadPanel` / `TrackpadNSView`)**: the macOS
  Keyboard-tab trackpad area is a **native `NSView`** (`MacTrackpadSurface`/`TrackpadNSView`), not
  SwiftUI gestures — because only the native event path can capture mouse buttons, the scroll wheel,
  and pin the OS cursor. Behavior:
  - **Option-key pin**: while the pointer is inside the surface **and** the Option key is held
    (a `flagsChanged` local monitor + tracking-area `mouseEntered`/`mouseExited`), the local cursor is
    frozen at the pin point via `CGAssociateMouseAndMouseCursorPosition(0)` and only movement deltas
    are mirrored to the remote. Releasing Option (`stopPin`) re-associates the cursor and warps it
    back to the pin point (no jump). App deactivation (`didResignActiveNotification`) cancels the pin
    safely so the cursor is never left frozen. The pin engine itself is the shared
    `OptionCursorPin` class (see `OptionCursorPin.swift`), also used by the menu-bar popover's
    text field (below) — keep both surfaces behind it rather than re-implementing the Quartz
    cursor-freeze/warp dance.
  - **Held-button drag model**: `TrackpadNSView` tracks `activeButtons` (a `MouseButtons` OptionSet).
    `mouseDown`/`rightMouseDown` insert the button and `mouseUp`/`rightMouseUp` remove it; every
    movement report (`forwardMove`, used by both `mouseMoved` while pinned and `mouseDragged`) is sent
    as `MouseReport(buttons: activeButtons, dX:, dY:)`. **This is required because HID mouse reports
    are full state snapshots** — a left-button drag only becomes a remote drag/box-select if the left
    button is present in *every* move frame, not just the initial press frame.
  - Left/right click and wheel sync work with or without Option held. iOS `TouchpadView` is unchanged
    (SwiftUI gestures with its own right-click/scroll handling).
- **Direct Input cursor hiding (macOS)**: `DirectInputController.start()` calls `NSCursor.hide()` and
  `stop()` calls `NSCursor.unhide()`. This is AppKit-level and only reliably hides the cursor while the
  app is the **active** application. When capture is toggled from the background via the global hotkey
  (app not active), the cursor may stay visible because the front app owns cursor presentation. Input
  capture itself (the `CGEvent` tap + `CGAssociateMouseAndMouseCursorPosition`) is unaffected and works
  in the background. A Quartz-level `CGDisplayHideCursor` alternative was evaluated but reverted: that
  display-level state does not auto-reset on process exit, so a force-quit mid-capture could leave the
  system cursor permanently hidden.
- **Direct Input toggle shortcut (macOS)**: the user assigns a global **Hotkey** in Settings
  (via `ShortcutRecorder`/`HotkeyRecorder`). `DirectInputShortcutManager` (singleton) persists
  it in `UserDefaults` (`AppSettings.directInputToggleHotkeyKey`), drives
  `DirectInputHotkeyMonitor` (global + local `NSEvent` monitor), and starts/stops
  `DirectInputController`. The same combo both starts and stops capture — there is **no
  separate release key combo** (the old hardcoded ⌃⌥ release was removed).
- **Direct Input stop behavior (iOS)**: on iOS, `DirectInputController` (GameController branch)
  stops capture when **both Ctrl and Alt are held** (`releaseComboHeld` in
  `handleKey`) — this is a *separate* mechanism from the macOS user-configured `toggleHotkey`.
  Do not assume the macOS shortcut model applies to iOS; never port the `toggleHotkey`
  machinery into the iOS branch.
- **Direct Input modifier remap (macOS, opt-in)**: `SettingsView` exposes a
  "macOS → Windows Modifier Remap" toggle (`AppSettings.macToWindowsModifierRemapKey`,
  default `false`, registered in `BTRemoteApp.init`). When on, `ModifierRemap.swift`'s
  `remapModifiersForWindows(_:)` maps **Command → Ctrl** (replacing GUI, not adding it) on forwarded
  keyboard reports, so Mac muscle memory (Cmd+C) drives Windows (Ctrl+C). Control already maps to
  Ctrl and is left unchanged; Alt/Shift pass through. The remap is applied **only at send time** in
  `DirectInputController.sendKeyboardReport()`; the in-memory `modifiers` and the toggle
  `Hotkey` still use the *real* macOS modifier identity (`Hotkey.KeyboardModifiers(_:)` is
  intentionally left un-swapped), so enabling remap never affects starting/stopping capture.
  The on-screen keyboard and `windowsShortcuts` are unaffected (they specify `modifiers` directly).
- **Direct Input latency & throughput model (macOS)**: capture and send are **decoupled** so a high-polling
  source (e.g. a 1000 Hz 2.4G mouse) does not back up the Classic HIDP link (~125 Hz effective). This is what
  keeps Direct Input smooth under sustained movement.
  - *Capture side* (variable rate): the `CGEvent` tap accumulates raw deltas into `accumDX / accumDY / accumWheel`
    (and sets `hasPendingMovement` / `hasPendingScroll`) but does **not** send per event.
  - *Send side* (fixed cadence): a `DispatchSourceTimer` flushes at `outputReportHz`
    (`AppSettings.directInputOutputHzKey`, default `125`, range `30…1000`). Each tick, if there is pending
    movement/scroll and the link is not saturated, it sends **one** merged report carrying the accumulated deltas.
  - *Backpressure*: `flush()` only sends when `outstandingWrites < maxOutstandingWrites`
    (`AppSettings.directInputMaxOutstandingWritesKey`, default `2`, range `1…4`). `outstandingWrites` is
    incremented before `sendMouse` and decremented in the **write-completion** callback. This caps reports in
    flight on the link so end-to-end latency stays bounded (≈ `maxOutstandingWrites ×` link delivery interval)
    instead of growing without limit over a long session.
  - *Displacement is conserved*: when a flush is skipped because the link is saturated, the accumulators are
    **not** cleared — pending deltas ride along on the next successful flush. HID relative-delta semantics mean
    motion is never lost, only deferred.
  - *Write-completion plumbing*: `HIDInput.sendMouse` is `(MouseReport, @escaping () -> Void) -> Void`.
    `HIDClassicDevice` boxes the closure in a `_WriteAck` class, passes it as `writeAsync`'s `refcon`
    (`Unmanaged.passRetained`), and fires it from `l2capChannelWriteComplete` via `takeRetainedValue().handler()`
    — exactly **once** per report (success path) or synchronously on a `writeAsync` failure (failure path).
    `HIDPeripheral` (LE) calls `onSent()` synchronously after `updateValue`, because GATT notify has its own
    flow control and needs no real backpressure. **Do not change the refcon ownership model** — the
    `passRetained`/`takeRetainedValue` pair must stay balanced (see `HIDClassicDevice.swift` for inline comments).
  - *Both settings take effect only after re-starting Direct Input* (toggle off/on); `SettingsView` footers say so.
    Buttons (press/click) send immediately and bypass the backpressure gate.
- **Direct Input long-session latency robustness (do not regress)**: three safeguards were added to
  fix "mouse delay grows over a long session", especially in LE (HOGP) mode:
  - *Classic write recovery*: `HIDClassicDevice` keeps `pendingWriteAcks` and, on
    `l2capChannelClosed`, releases every in-flight refcon and fires its `onSent`, so `outstandingWrites`
    never stays stuck high after a disconnect.
  - *Flush watchdog*: `DirectInputController.flush()` counts consecutive stalled flushes
    (`maxedFlushStreak`) and, once it reaches `stallResetThreshold` (~20 ≈ 160 ms at 125 Hz), zeroes
    `outstandingWrites` to self-heal a wedged backpressure window.
  - *LE notification flow-control watchdog*: `HIDPeripheral` runs `readyWatchdog`; if
    `isReadyToSendNotification` stays false past `readyStallTimeout` (1.5 s) it forces it true and
    drains the pending broadcast. `attemptSend` also falls back to **per-central** `updateValue` when a
    bulk send is rejected, so one stalled central does not freeze delivery to the others.
  - *LE pending-broadcast delta merge*: when a stalled report is stashed via `stashPending` and the
    slot already holds a **mouse** report for the same characteristic, the two are merged
    (`mergeMouseReports`): buttons from the newest snapshot (same semantics as plain overwrite),
    dX/dY/wheel summed with Int8 clamping. Because LE `sendMouse` fires `onSent` synchronously,
    `DirectInputController`'s accumulators are cleared regardless of queue state, so plain overwrite
    silently lost accumulated motion whenever the link drained slower than the flush cadence
    (Windows-negotiated LE connection intervals are typically 11.25–30 ms ≪ 125 Hz) — the signature
    was choppy, jumpy cursor movement on Windows hosts. Do not revert this to plain overwrite; other
    report types (keyboard/consumer/system) are full-state snapshots and keep latest-wins semantics.
  - **Critical constraint**: `CBPeripheralManager.updateValue(...)` returning `false` means the send
    **buffer is full (flow control)** — it does **not** mean a central is dead, and it cannot identify
    which central. Never prune `subscribedCentrals`/`activeRecipients()` based on that return value;
    dead-central cleanup must use real reachability evidence. (A previous per-central *prune* attempt
    silently dropped live centrals and broke Direct Input — do not reintroduce it.)
- **Shared text input (`HIDTextSender` + `KeyTypist`)**: a reusable "type text → paced HID
  keyboard reports" editor used by both `KeyboardView` and the status-bar popover. It does
  **not** require Accessibility permission (unlike Direct Input's global event tap). Reports
  are built via `HIDInput.keyReports(for:)` / `keyReports(for:adding:)` (US-ASCII `mapASCII`)
  and the field is diffed against already-sent text so deletions emit `Backspace` reports. The
  `KeyTypist` pacer (20 ms spacing) prevents rapid identical key presses from being coalesced.
- **Windows shortcuts (`WindowsShortcuts` + `windowsShortcuts`)**: a list of Windows key chords
  (Ctrl+Alt+Del, Win+L/D/E/R/V, Alt+Tab, Ctrl+Shift+Esc) rendered as chips in both `KeyboardView`
  and the status-bar popover; each sends a `KeyboardReport` (modifiers held) then `.zero`.
- Reusable controls live in `Controls.swift` (`PressGesture`, `HoldButton`).
- Platform-specific views are guarded with `#if os(macOS)` / `#if os(iOS)` where needed
  (e.g. `TrackpadPanel` floating window vs in-app `TouchpadView`; `DPadView` on iOS).
- **macOS clipboard sync over LE (`ClipboardSyncController` + `ClipboardSyncProfile`)**:
  bidirectional text + image (JPEG q75) clipboard sync between the Mac and a paired Windows host
  via a custom GATT service alongside HOGP. A Python companion (`tools/win_clipboard_sync.py`)
  runs on Windows. Key design points:
  - *Protocol*: message = `[msgType:1][SHA-256[:4]][payloadLen:4 LE][payload]`; chunk =
    `[msgID:1][chunkIndex:2 LE][flags:1][payload]`. `msgType 0x01`=text(UTF-8), `0x02`=image(JPEG).
    Images are converted PNG→JPEG on send (q75) and JPEG→PNG on receive for pasteboard compatibility.
  - *Echo suppression*: after writing to `NSPasteboard`, re-read the clipboard content and hash
    THAT (not the original payload) — JPEG re-encoding changes bytes, so the original hash would
    mismatch and trigger an echo loop. Same approach on the Windows side.
  - *Send path*: one chunk per `sendOneChunk()` call, paced by a 10 ms `Timer`. When
    `sendClipboardChunk` returns false (buffer full), arms a 5 s `sendWatchdog`; if
    `onClipboardReady` doesn't fire in time, `abortSend()` clears the queue and shows an error.
    When subscription count drops to 0 (peer disconnect), `abortSend()` fires immediately.
  - *Progress window*: independent floating `NSWindow` (borderless, `.floating` level,
    `ignoresMouseEvents`, `hasShadow = true`) in the top-right corner. It shows a **capsule**
    (an opaque rounded `NSView` with `cornerRadius = 18`, system `windowBackgroundColor` fill
    and `labelColor` centered text, so it reads as a neutral gray that adapts to light/dark) — the
    previous **translucent** `NSVisualEffectView` (`.hudWindow`)
    glass box was removed because it looked like an ugly semi-transparent rectangle; the capsule
    shape is kept but now uses a solid, non-translucent fill. The label is pure AppKit (**[not**
    `NSHostingView`/SwiftUI — using `NSHostingView` caused a `SIGSEGV` in `objc_release` during
    Swift Concurrency autorelease pool drain). Window is created once and kept alive; only
    `orderFront`/`orderOut` toggles visibility. Width is grow-only (never shrinks during a sync
    session to avoid jitter).
  - *Guards*: `enqueueMessage` and `pollClipboard` check `subscribedCount > 0`; no sync
    activity when no host is subscribed. `DirectInputController.start(_ hid:)` (macOS) refuses
    to start and sets `lastError` when **either** (a) `hid.isConnected` is false — i.e. no host
    is subscribed/connected (subscription count 0) — **or** (b) no toggle shortcut is configured
    (`toggleHotkey == nil`, since there would be no way to stop capture). Only after those two
    checks pass does it validate `AccessibilityPermission.isTrusted` (setting `needsAccessibility`
    and calling `onRelease()` when denied) and that the `CGEvent` tap can be created (otherwise
    it sets `lastError` to the capture-failed string). The menu-bar button (`StatusBarMenuView`)
    is disabled and shows the same reason as a hint when a precondition is unmet.
  - *Windows companion*: `bleak` + `pyperclip` (text) + `pillow` + `pywin32` (images, optional).
    Non-last chunks use `writeWithoutResponse` (zero gap); last chunk uses `writeWithResponse`
    for delivery confirmation. Attempts MTU 512 negotiation for larger chunk payloads.

## 5. HID model (shared, platform-independent)

- **`HIDProfile.swift`**
  - All SIG UUIDs are declared as **full 128-bit canonical strings** (`CBUUID(string:)`).
    The 16-bit short form is rejected by CoreBluetooth as system-reserved — never shorten them.
  - `reportMapData` is the **239-byte HID report descriptor** shared by both backends.
    It defines Report IDs 1–6: mouse, keyboard, keyboard-LEDs, battery, system-control,
    consumer-control. Treat this blob as **load-bearing** (see §6).
  - `HIDProfile.reportMapData` is the single source for both the GATT `Report Map`
    characteristic and the classic SDP `HIDDescriptorList`.
- **`HIDReports.swift`**: `MouseReport`, `KeyboardReport`, `KeyboardModifiers`, `KeyboardLEDs`,
  `Keycode` (USB HID usage page 0x07), `SystemControlReport`/`SystemActions`,
  `ConsumerReport`/`ConsumerKey` (usage page 0x0C). Each `struct` has a `data` property that
  serializes to the wire format, plus a static `.zero` (all-released) report used to clear state.
  **This file also owns the `Keycode` UI/bridge extensions** — `displayName`, the
  `init?(macVirtualKey:)` mapping, and the `macVirtualKeys` table — which were moved here from
  `DirectInputController` so both macOS and the shared `Hotkey` code can use them. New HID
  usages (e.g. `Keycode.deleteForward = 0x4C`) are added to the `Keycode` enum here.
- **`ReportID` / `ReportType`**: map report IDs to descriptor/feature bytes.

## 6. CRITICAL constraints — read before changing the HID stack

The README is explicit: **the Bluetooth HID stack was built over weeks of working around
undocumented platform behaviors. Changing it is highly discouraged** and likely to break
SDP negotiation, GATT layout, or the bonding handshake **with no clear error logs.**

### iOS (HOGP) — `HIDPeripheral.swift`
- iOS exposes **no HID device role**, so the full HOGP GATT tree must be constructed manually
  in `CBPeripheralManager`. Adhere to the existing service/characteristic/descriptor layout.
- SIG UUIDs must use the **full 128-bit string** (see §5).
- Do **not** set `.extendedProperties` on Protocol Mode, Boot Keyboard Output, or Output Report
  characteristics — it implicitly appends a descriptor that altering the GATT layout and breaks
  host HID binding.
- Hosts may **stall after subscribing** until a baseline input report is pushed; an initial
  report on subscribe is required (`peripheralManager(_:central:didSubscribeTo:)` pushes `cachedReports`).
- **Encryption and bonding are mandatory.** A stale bond on either side triggers teardowns that
  only a full re-pair clears.

### macOS (HIDP) — `HIDClassicDevice.swift`
- `bluetoothd` **binds the HID L2CAP ports at startup and always operates as the HID host**,
  so the stack is restricted to **outbound** connections and can never listen for inbound.
- `bluetoothd` performs an SDP lookup for the HID device record on every inbound attempt;
  Windows hosts expose no such record, so the daemon resets the connection. **Windows is
  unreachable via HIDP by design**; the classic backend can only reach stacks that accept
  device-initiated connections (namely Android).
- The existing SDP record layout in `SDPRecord.swift` (control PSM 0x0011, interrupt PSM 0x0013,
  HID profile v1.1, subclass 0xC0 combo device) must be preserved.

### General
- Never edit `HIDProfile.reportMapData` without re-validating both backends and real-device pairing.
- Keep the report ID numbering (1–6) and the `.zero` clear-report convention consistent.

## 7. Code conventions

- **Language**: Swift 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`. Code must satisfy
  strict concurrency in CI.
- **Concurrency model**: all backend controllers (`HIDPeripheral`, `HIDCentral`,
  `HIDClassicDevice`, `DirectInputController`) are `@MainActor final class: ObservableObject`.
  `@Published` properties are the source of UI state. CoreBluetooth managers are created with
  `queue: nil` (main queue). Delegate conformances use `@preconcurrency`
  (e.g. `extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate`).
- **Static shared constants**: declared `nonisolated(unsafe) static let` in `HIDProfile`
  (e.g. UUIDs) to avoid isolation warnings — preserve this pattern for new cross-actor constants.
- **macOS manager singletons**: `StatusBarController.shared`, `DirectInputShortcutManager.shared`, and
  `CaptureIndicatorController.shared` are `@MainActor final class: ObservableObject` singletons attached
  once from the root view (`ContentView._onAppear`). The first two take a `buildHID: () -> HIDInput`
  closure; `CaptureIndicatorController` takes the live `DirectInputController` via `attach(directInput:)`
  and `shutdown()` is invoked from `AppDelegate.applicationWillTerminate`. Follow this pattern for new
  app-global macOS services; do not recreate them per-view.
- **Event monitors (macOS)**: global/local `NSEvent` monitors (`DirectInputHotkeyMonitor`,
  `ShortcutRecorder.RecorderEngine`, `StatusBarController`) must be balanced — always
  `removeMonitor` in the inverse of `add*MonitorForEvents`, and `setEnabled(false)` during
  shortcut recording so the app's own toggle does not fire mid-capture.
- **HID builder duplication**: the `buildHID` closure that selects the active backend
  (`classicMode` from `UserDefaults` `BTRemote.macTransportMode`) is defined **twice inline**
  inside `ContentView._onAppear` — once for `DirectInputShortcutManager.shared.attach(buildHID:)`
  and once for `StatusBarController.shared.attach(buildHID:)`. The two managers only *store* the
  closure and invoke it on demand (`DirectInputShortcutManager` in its hotkey callback,
  `StatusBarController` when building the popover or toggling capture); they do **not** define
  their own copy. If transport-selection logic changes, update **both** inline closures in
  `_onAppear` (or extract a single shared helper that both `attach` calls reference).
- **Platform gating**: wrap platform-specific code in `#if os(macOS)` / `#if os(iOS)`.
  macOS-only files (`Classic/*`, `DirectInputController` macOS branch, `AccessibilityPermission`,
  `Hotkey`, `ShortcutRecorder`, `DirectInputHotkeyMonitor`, `DirectInputShortcutManager`,
  `StatusBarController`, `StatusBarMenuView`, `entitlements.plist`) are fully excluded on iOS.
- **Formatting & linting**: `swiftformat` and `swiftlint` (strict) are enforced by `build.sh`
  and CI. Run `swiftformat --lint .` and `swiftlint lint --strict` before committing; the
  project will not pass CI otherwise.
- **Localization**: all user-facing strings go through `L10n.*` returning `LocalizedStringKey`,
  with values in `Localizable.xcstrings`. Do not hardcode visible strings.
- **Settings**: all `UserDefaults` keys and tunable constants live in `AppSettings.swift`.
  Add new keys there rather than string-literal keys scattered in views. The one exception is
  the transport-mode key `BTRemote.macTransportMode`, which is kept as a raw `@AppStorage` string
  literal in `BTRemoteApp.swift` (and mirrored in `SetupView.swift` / read directly in
  `ContentView`'s inline `buildHID` closures) because it drives the `@AppStorage`-bound UI and the
  transport switch; it is intentionally not surfaced through `AppSettings`.
- **Backend seam**: UI/input logic should talk to `HIDInput`, never to a specific backend
  class. Add transport features in the shared router or both backends symmetrically.

## 8. Where to make common changes

| Change | File(s) |
|---|---|
| Add/modify a key, mouse, or consumer behavior | `HIDReports.swift`, `HIDInput.swift`, UI views |
| Change the HID descriptor / report map | `HIDProfile.swift` (**high risk, see §6**) |
| Add a HID usage / keycode (incl. `Keycode.displayName`, mac-virtual-key map) | `HIDReports.swift` |
| New iOS/macOS peripheral (BLE) behavior | `LowEnergy/HIDPeripheral.swift` |
| New scanner / connection-event behavior | `LowEnergy/HIDCentral.swift` |
| New classic (macOS) behavior | `Classic/HIDClassicDevice.swift`, `Classic/SDPRecord.swift` |
| Local input forwarding (direct mode) | `DirectInputController.swift` |
| Direct Input latency tuning (output rate / in-flight limit, backpressure) | `DirectInputController.swift`, `AppSettings.swift`, `SettingsView.swift`, `HIDInput.swift`, `Classic/HIDClassicDevice.swift` (see §4 "Direct Input latency & throughput model") |
| Direct Input toggle shortcut (record/monitor/persist) | `Hotkey.swift`, `ShortcutRecorder.swift`, `DirectInputHotkeyMonitor.swift`, `DirectInputShortcutManager.swift` |
| Menu-bar item / popover | `StatusBarController.swift`, `StatusBarMenuView.swift` |
| Option-key cursor-pin (shared engine) | `OptionCursorPin.swift`, wired in `TrackpadPanel.swift` (trackpad) and `StatusBarMenuView.swift` (popover) |
| Direct Input capture indicator (red border + gray mask) | `CaptureIndicatorController.swift`, `CaptureBorderView.swift`, `AppSettings.directInputIndicatorEnabledKey`, `SettingsView.swift` |
| macOS trackpad surface (Option pin, drag/box-select, right-click, wheel) | `TrackpadPanel.swift` (`TrackpadNSView`) |
| Shared "type text" editor | `HIDTextSender.swift` |
| Windows / platform shortcut chips | `WindowsShortcuts.swift` + `KeyboardView.swift` / `StatusBarMenuView.swift` |
| macOS app lifecycle (residency, quit cleanup) | `BTRemoteApp.swift` (`AppDelegate`) |
| New settings / persistence | `AppSettings.swift` + `SettingsView.swift` |
| New strings | `L10n.swift` / `L10nExtensions.swift` + `Localizable.xcstrings` |
| Build / CI config | `project.yml`, `build.sh`, `ci_scripts/`, `fastlane/Fastfile` |
| App metadata / capabilities | `Info.plist`, `entitlements.plist` |
| macOS clipboard sync over LE | `ClipboardSyncController.swift`, `ClipboardSyncProfile.swift`, `LowEnergy/HIDPeripheral.swift` (clipboard GATT service + APIs), `BTRemoteApp.swift` (attach), `AppSettings.swift` + `SettingsView.swift`; also `tools/win_clipboard_sync.py` |

## 9. Do / Don't summary for agents

**Do**
- Regenerate the Xcode project via `xcodegen generate` after editing `project.yml`.
- Run `swiftformat --lint .` and `swiftlint lint --strict` before any commit/build.
- Keep new cross-platform code behind `#if os(...)` and within existing controller boundaries.
- Route all input through `HIDInput`; preserve `.zero` clear-report semantics.

**Don't**
- Do not modify `HIDProfile.reportMapData`, the GATT characteristic ordering, or the SDP
  record layout unless you can validate pairing end-to-end on real hardware (§6).
- Do not switch CoreBluetooth managers off the main queue, or remove `@MainActor`/`@preconcurrency`.
- Do not hardcode user-facing strings or `UserDefaults` keys outside the established modules.
- Do not add the 16-bit short-form UUIDs; always use full 128-bit canonical strings.
- Do not assume the macOS classic backend can reach Windows (it cannot, by design).
- Do not recreate `StatusBarController` / `DirectInputShortcutManager` per view — use the
  existing `.shared` singletons and attach them once from `ContentView`.
- Do not leave `NSEvent` monitors installed; always balance `add*MonitorForEvents` with
  `removeMonitor`, and pause the toggle monitor while `ShortcutRecorder` is capturing.
- Do not consume (`return nil`) mouse-button events in `OptionCursorPin`'s popover monitors. The
  popover path needs a real AppKit drag session: consuming `mouseDown` prevents the session from
  starting, so the subsequent `*Dragged` events are dropped before any monitor sees them and drag
  forwarding dies. Observe the events and `return event`.
- Do not gate the popover Option-pin on cursor position; `StatusBarController` retains the popover's
  hosting controller, so the pin must be gated by text-field focus (`@FocusState`) and torn down on
  `NSPopover.didCloseNotification`, or the monitors leak and the pin triggers outside the popover.
- Do not remove the `activeButtons.intersection(NSEvent.pressedMouseButtons)` heal in
  `OptionCursorPin.forwardPinnedMove` — a missed `mouseUp` would otherwise leave a stuck button and
  every later move re-sends the press (a real release self-heals on the next move).
- Do not reintroduce a separate "release" key combo for Direct Input; the user-configured
  `toggleHotkey` is the single control that both starts and stops capture.
- Do not reintroduce `CGDisplayHideCursor` for Direct Input cursor hiding unless you also guarantee a
  cursor restore on every process exit (it does not auto-reset like `NSCursor.hide()`; a force-quit
  mid-capture could leave the system cursor permanently hidden — see §4).
- Do not update only one of the two inline `buildHID` closures in `ContentView._onAppear`
  (both passed to `DirectInputShortcutManager.shared` and `StatusBarController.shared`) when
  changing transport selection.
- Do not port the macOS `toggleHotkey` machinery into the iOS `DirectInputController` branch;
  iOS stops capture via the Ctrl+Alt `releaseComboHeld` mechanism instead.
- Do not remove the `onSent` completion from `HIDInput.sendMouse` or the `_WriteAck` refcon plumbing in
  `HIDClassicDevice`: the `outstandingWrites` backpressure counter depends on `onSent` firing **exactly once**
  per report (success path in `l2capChannelWriteComplete`, failure path synchronously). Breaking the
  `passRetained`/`takeRetainedValue` balance leaks the boxed ack or double-fires the completion.
- Do not clear `accumDX / accumDY / accumWheel` when a flush is skipped for backpressure — that is what keeps
  HID relative-delta motion lossless (the deltas ride along on the next successful flush).
- Do not make `outputReportHz` or `maxOutstandingWrites` take effect live without also adding a `UserDefaults`
  observer; the current design reads them in `start()`, so they require re-starting Direct Input.
- Do not prune `subscribedCentrals` / `activeRecipients()` based on `CBPeripheralManager.updateValue(...)`
  returning `false` — that boolean only signals flow control, not a dead central, and pruning live
  centrals silently breaks Direct Input (see §4 "Direct Input long-session latency robustness").
- Do not remove the `pendingWriteAcks` recovery in `HIDClassicDevice`, the `maxedFlushStreak` watchdog
  in `DirectInputController`, or the `readyWatchdog` / per-central fallback in `HIDPeripheral` — they
  keep latency bounded across long sessions (see §4).
- Do not send a drag as a bare button-press plus buttonless move frames; HID mouse reports are full
  state snapshots, so both `TrackpadNSView.forwardMove` and `OptionCursorPin.forwardPinnedMove` must
  carry `activeButtons` in every move frame for a remote drag/box-select to register (see §4 "macOS
  trackpad surface" and "Option-key pin inside the popover").
- Do not pass a Swift `Bool` to `CGAssociateMouseAndMouseCursorPosition` — its parameter is `boolean_t`
  (an integer); pass the integer literals `0` (disable) / `1` (enable) or the call fails to compile.
- Do not reuse `pendingBroadcast` / `stashPending` in `HIDPeripheral` for clipboard chunk delivery;
  clipboard chunks are lossy-tolerant mouse-specific state — dropping a chunk corrupts a clipboard
  message. Use the dedicated `sendClipboardChunk` → `onClipboardReady` path instead.
- Do not shorten the clipboard sync service/characteristic UUIDs to 16-bit form; use the full 128-bit
  canonical strings from `ClipboardSyncProfile` to avoid collision with reserved SIG UUIDs.
- Do not use `NSHostingView` / SwiftUI views inside the clipboard progress floating `NSWindow` — it
  causes a `SIGSEGV` in `objc_release` during Swift Concurrency autorelease pool drain. Use pure
  AppKit (a plain `NSView` container + `NSTextField`, no `NSVisualEffectView` background box) and
  keep the window alive (only `orderFront`/`orderOut`, never `close()` + recreate).
- Do not hash the original JPEG payload for clipboard echo suppression — JPEG re-encoding changes
  bytes. Re-read the clipboard content after writing and hash THAT (see §4 "macOS clipboard sync").
- Do not remove the `sendWatchdog` (5 s) or the `abortSend()` on disconnect in
  `ClipboardSyncController` — without them a peer disconnect mid-image leaves the sender stuck
  forever showing "Sending image...".
- `DirectInputController.start(_ hid:)` (macOS) **does** now refuse to start when `hid.isConnected`
  is false (no host subscribed) or when no toggle shortcut is set (`toggleHotkey == nil`), setting
  `lastError` in both cases. Do not work around or remove these guards, and do not add a start path
  that skips them — a capture session with no connected host or no way to stop is unrecoverable.
