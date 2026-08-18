# Bluetooth HID Remote for iOS & macOS

[![license](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)

**Bluetooth Remote** turns an iPhone, iPad, or Mac into a generic Bluetooth keyboard, mouse, and trackpad for anything that accepts standard Bluetooth input — with no companion app needed on the target. It is the Apple counterpart of [BT Remote for Android](https://github.com/jqssun/android-bt-remote).

Your Apple device presents itself as a standard [Bluetooth Human Interface Device (HID)](https://www.bluetooth.com/specifications/specs/hid-service-specification/) and sends keyboard, media, and mouse input directly over Bluetooth. It also features a Direct Input mode (forward your local hardware straight to the target), and **clipboard sync** (macOS ↔ Windows, LE only) for text and images.

## Compatibility

- **Controller (this app):** iOS 15 / iPadOS 15 and later, macOS 13 and later.
- **Host (target):** Android 4+, Android TV / Google TV / Fire OS, ChromeOS, iOS 13+ / iPadOS 13+, iOS 4+ (keyboard only), tvOS 9.2+, Mac OS X 10.3+, Linux kernel 2.6+, SteamOS, Windows XP Service Pack 2+.

## Features

- **Two HID transports** — Bluetooth Low Energy (HOGP) on iOS + macOS, Bluetooth Classic (HIDP) on macOS. The macOS app can switch between them (Classic reaches Android; LE is the portable path).
- **Full input set** — on-screen keyboard, trackpad surface, D-pad, and consumer (multimedia) controls.
- **macOS menu-bar app** — an always-present status item opens a popover for quick text entry, Windows shortcut chords, and a Direct Input toggle. The app stays resident after the main window is closed.
- **Direct Input** — forward your local keyboard / mouse / scroll straight to the remote host (macOS `CGEvent` tap; iOS `GameController` + pointer lock). A user-configured global hotkey toggles capture.
- **Clipboard sync** — bidirectional text + image (JPEG) between the Mac and a paired Windows host over a custom GATT service, with an optional Python companion.
- **Option-key cursor pin** — hold **Option** on the macOS trackpad surface, or while the menu-bar popover's text field is focused, to freeze the local cursor and stream movement (plus click / drag) to the remote.
- **Capture indicator (macOS)** — a persistent red border (and gray dimming mask) on every screen while Direct Input captures.
- **Windows shortcut chips** — Ctrl+Alt+Del, Win+L/D/E/R/V, Alt+Tab, Ctrl+Shift+Esc, and more.

## How it works

The app exposes two Bluetooth HID backends and selects the right one per platform:

| backend | profile | platform | path | description |
|---|---|---|---|---|
| Bluetooth Classic | HID Profile | macOS | [`BTRemote/Classic`](BTRemote/Classic) | IOBluetooth SDP record with L2CAP control (0x0011) + interrupt (0x0013) channels |
| Bluetooth Low Energy | HID over GATT | macOS, iOS | [`BTRemote/LowEnergy`](BTRemote/LowEnergy) | CoreBluetooth peripheral exposing the HID service |

Both backends emit the **same HID report descriptors** (`HIDProfile.reportMapData`), supporting mouse (relative, with wheel), keyboard (with LED output), battery, consumer-control, and system-control. All UI input flows through the backend-agnostic `HIDInput` router, which forwards to the active backend's `sendMouse` / `sendKeyboard` / `sendConsumer`.

## Menu-bar app (macOS)

An always-present `NSStatusItem` (`StatusBarController`) opens an `NSPopover` (`StatusBarMenuView`) with the text sender, a Windows-shortcuts grid, and a Direct Input start/stop button — the icon tints red while capture is active. Opening the popover enables the Option-key cursor-pin for its focused text field.

## Direct Input

Forwards your current hardware input to the target. On macOS this needs **Accessibility permission** (a `CGEvent` tap); on iOS it uses `GameController` (`GCKeyboard`/`GCMouse`) plus pointer lock for raw deltas. A user-configured global **hotkey** (recorded in Settings) toggles capture — there is no separate release combo. Send cadence (`outputReportHz`) and the in-flight write limit (`maxOutstandingWrites`) are tunable in Settings; capture and send are decoupled so a high-polling mouse stays smooth. On macOS the cursor is hidden during capture via `NSCursor.hide()`.

## Clipboard sync

Bidirectional text + image (JPEG q75 on the wire) sync between the Mac and a paired Windows host, over a custom GATT service alongside HOGP. A Python companion, [`tools/win_clipboard_sync.py`](tools/win_clipboard_sync.py) (`bleak` + `pyperclip`; `pillow` + `pywin32` for images), runs on Windows. Echo loops are suppressed by hashing the *re-read* pasteboard content (JPEG re-encoding changes bytes).

## Option-key cursor pin

On the macOS trackpad surface, holding **Option** (with the pointer inside the surface) freezes the local cursor at the pin point via `CGAssociateMouseAndMouseCursorPosition(0)` and streams only movement deltas; releasing re-associates the cursor and warps it back. The menu-bar popover mirrors this while its text field is focused. Both surfaces share the implementation in [`OptionCursorPin`](BTRemote/OptionCursorPin.swift) (`TrackpadPanel` / `TrackpadNSView` and `StatusBarMenuView`), so the logic is defined once.

## Build from source

Prerequisites: macOS with **Xcode 15+** (the toolchain sets `SWIFT_VERSION: 6.0`), and the command-line tools `xcodegen`, `swiftformat`, `swiftlint`, `xcbeautify` (`brew install xcodegen swiftformat swiftlint xcbeautify`). Deployment targets: iOS 15.0, macOS 13.0.

The Xcode project is **generated**, not committed:

```bash
xcodegen generate          # regenerates BTRemote.xcodeproj from project.yml
# (or run ./ci_scripts/ci_post_clone.sh, which also fetches the Bluetooth SIG JSON datasets)
./build.sh                 # swiftformat --lint + swiftlint, then ad-hoc macOS build
```

`build.sh` runs `swiftformat --lint` and `swiftlint lint --strict` (both must pass), then builds the **macOS** scheme in Release (unsigned, then ad-hoc codesigned with `entitlements.plist`). If the iOS SDK is available it also produces an `.ipa` under `.build/`.

## Architecture & contributing

[`AGENTS.md`](AGENTS.md) is the authoritative guide for agents and contributors: it documents the HID stack's load-bearing constraints, the `HIDInput` backend seam, the macOS-only modules, and code conventions. **The HID stack was built over weeks of working around undocumented platform behaviors; changing it is highly discouraged** — it is likely to break SDP negotiation, GATT layout, or bonding with no clear error logs. Key constraints:

### iOS (HOGP)
- iOS exposes no HID device role, so the full GATT tree is constructed manually in `CBPeripheralManager`; preserve the existing service/characteristic/descriptor layout.
- SIG UUIDs must use the full 128-bit canonical string (the 16-bit short form is rejected as system-reserved).
- Do not set `.extendedProperties` on Protocol Mode, Boot Keyboard Output, or Output Report characteristics.
- Hosts may stall after subscribing until a baseline input report is pushed; an initial report on subscribe is required.
- Encryption and bonding are mandatory; a stale bond on either side requires a full re-pair.

### macOS (HIDP)
- `bluetoothd` binds the HID L2CAP ports at startup and always operates as the HID host, so the stack is restricted to **outbound** connections and can never listen for inbound.
- `bluetoothd` performs an SDP lookup for the HID device record on every inbound attempt; Windows exposes none, so the daemon resets the connection. **Windows is unreachable via HIDP by design** — Classic can only reach stacks that accept device-initiated connections (namely Android).
- The existing SDP record layout (control PSM 0x0011, interrupt PSM 0x0013, HID v1.1, subclass 0xC0 combo device) must be preserved.

## License

[AGPL-3.0-only](LICENSE).
