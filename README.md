# Bluetooth HID Remote for iOS & macOS

[![Stars](https://img.shields.io/github/stars/jqssun/darwin-bt-remote?label=stars&logo=GitHub)](https://github.com/jqssun/darwin-bt-remote)
[![GitHub](https://img.shields.io/github/downloads/jqssun/darwin-bt-remote/total?label=GitHub&logo=GitHub)](https://github.com/jqssun/darwin-bt-remote/releases)
[![license](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![build](https://img.shields.io/github/actions/workflow/status/jqssun/darwin-bt-remote/build.yml?label=build)](https://github.com/jqssun/darwin-bt-remote/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/jqssun/darwin-bt-remote)](https://github.com/jqssun/darwin-bt-remote/releases)

**Remote** is a free, open-source app that turns your iPhone, iPad, or Mac into a Bluetooth keyboard, mouse, and trackpad. Use any Apple device as a serverless wireless remote for anything that accepts Bluetooth input, with no companion app on the target. It is the first device-agnostic Bluetooth HID implementation to work across every major platform that is open-source.

As the Apple counterpart of [BT Remote for Android](https://github.com/jqssun/android-bt-remote), it acts as a Bluetooth HID controller for Windows, Linux, macOS, iOS (and iPadOS), tvOS, Android (and Android TV, Google TV, Fire TV), ChromeOS, and SteamOS, plus any other host that supports a standard Bluetooth keyboard or mouse.

Unlike network remote-control tools, it needs nothing installed on the target and relies on its built-in Bluetooth HID support. Your Apple device presents itself as a standard Bluetooth Human Interface Device (HID) and sends keyboard, media, and mouse input directly over Bluetooth.

[<img height="48" alt="Get it on App Store" src="https://jqssun.github.io/images/badges/apple-app-store.svg">](https://apps.apple.com/app/id6778921831)
[<img height="48" alt="Get it on GitHub" src="https://jqssun.github.io/images/badges/github.svg">](https://github.com/jqssun/darwin-bt-remote/releases/latest)

## Compatibility

- HID device (controller):
    - iOS 15 (iPadOS 15) and later
    - macOS 13 and later

- HID host (target):
    - Android 4 and later
    - Android TV, Google TV, and Fire OS
    - ChromeOS
    - iOS 13 (iPadOS 13) and later
    - iOS 4 and later (keyboard only)
    - tvOS 9.2 and later
    - Mac OS X 10.3 and later
    - Linux kernel 2.6 and later
    - SteamOS
    - Windows XP Service Pack 2 and later

## Implementation

The app includes two HID backends and picks the right one per platform:

- **(Bluetooth Classic) Human Interface Device (HID) Profile**, in [`BTRemote/Classic`](BTRemote/Classic): IOBluetooth SDP record with L2CAP control and interrupt channels.
- **(Bluetooth Low Energy) HID over GATT Profile**, in [`BTRemote/LowEnergy`](BTRemote/LowEnergy): CoreBluetooth peripheral exposing the HID service.

Both backends emit the same HID reports: relative mouse with wheel, full keyboard with LED state, consumer (media) controls, and system controls.

## License

[AGPL-3.0-only](LICENSE). Commercial license is available upon request.

Bundling this software into closed-source commercial applications, proprietary products, or App Store distributions without an explicit commercial license is copyright infringement.
