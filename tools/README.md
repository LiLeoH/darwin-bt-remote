# Windows Clipboard Sync Companion

Reference implementation of a Windows companion app that syncs the clipboard with BTRemote's macOS clipboard sync feature over the LE (HOGP) link.

## Requirements

- Windows 10 or 11 with Bluetooth LE support
- Python 3.9+
- `pip install bleak pyperclip`
- (Optional, for image sync) `pip install pillow pywin32`

## Setup

1. Install dependencies:
   ```powershell
   pip install bleak pyperclip
   ```

2. Pair your Windows PC with the BTRemote device via **Bluetooth Settings** (standard pairing, no special tool needed).

3. On the macOS BTRemote app:
   - Switch to **Low Energy** transport mode
   - Enable **Clipboard Sync** in the Settings tab
   - Start advertising (Setup tab)

4. Run the companion:
   ```powershell
   python tools\win_clipboard_sync.py
   ```

## How It Works

The companion connects to the same BTRemote BLE device and discovers a custom GATT service (UUID `E95A7B2C-...`). It subscribes to notifications to receive Mac clipboard changes, and writes new Windows clipboard content in a chunked protocol back to the Mac. Content hashes prevent echo loops.

## Limitations

- Clipboard text (always) and PNG images (requires `pillow` + `pywin32`)
- Maximum clipboard size: 1 MiB
- Images transfer slowly over BLE; large images may take many seconds
- Encrypted link only (uses the existing Bluetooth bond)

## Troubleshooting

- **Device not found**: Confirm BTRemote is advertising in LE mode on the Mac. Check Windows Bluetooth settings for the paired device.
- **Service not found**: Clipboard Sync must be enabled in BTRemote Settings. You may need to restart BTRemote after enabling.
- **Write fails**: Ensure the device is paired. The encryption-required characteristic needs a bond.
- **"Both sides copy different text at the same time"**: Last-write-wins semantics — the two clipboards may swap. Normal with any sync tool.
