#!/usr/bin/env python3
"""
Windows clipboard sync companion for BTRemote (LE / HOGP).

Requires: pip install bleak pyperclip
Optional (image sync, Windows only): pip install pillow pywin32

## Protocol (ClipboardSyncProfile, mirrored from ClipboardSyncProfile.swift)

### GATT Layout
  Service: E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2C
  - Notify char (device -> host): E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2D
    Properties: read + notify (encryption required)
  - Write char  (host -> device): E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2E
    Properties: write + writeWithoutResponse (encryption required)

### Message (logical layer): [msgType:1][contentHash:4][payloadLen:4 LE][UTF-8 or JPEG payload]
  msgType 0x01 = text (UTF-8)
  msgType 0x02 = image (JPEG, quality ~75)
  contentHash = SHA-256(payload)[:4]
  Max payload = 1 MiB

### Chunk (link layer): [msgID:1][chunkIndex:2 LE][flags:1][payload]
  flags bit 0 = last chunk

### Loop Prevention
  When applying a remote clipboard, record its content hash (SHA-256[:4]).
  When the local clipboard changes, compute its hash:
    - If hash == last applied remote hash -> suppress (echo)
    - If hash == last sent hash -> suppress (no change)

  ## Usage
  1. Pair Windows with the BTRemote device normally via Bluetooth Settings.
  2. Enable Clipboard Sync in BTRemote Settings (macOS, LE mode).
  3. Run this script: python win_clipboard_sync.py
  4. Copy on Mac -> paste on Windows; copy on Windows -> paste on Mac.
  Press Ctrl+C to stop.

  ## Reliability
  - A clipboard holding **files** (not an image) is ignored instead of crashing
    (previously raised ``'list' object has no attribute 'mode'``).
  - The script **auto-reconnects** if BTRemote restarts or the BLE link drops, and
    surfaces errors instead of dying. A disconnect callback + watchdog detect link loss.
  - On first successful connect the device address is cached to
    ``~/.btremote_clipboard_sync.json``; subsequent starts (and Mac reboots) use a fast
    direct-connect by address instead of waiting for a slow advertisement scan.


  For image sync: install pillow and pywin32:
    pip install pillow pywin32
  Images sync as PNG (up to 1 MiB); BLE bandwidth limits practical image size.
"""

import asyncio
import hashlib
import json
import struct
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import bleak
import pyperclip

# ── Logging ──


def _ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def _log(msg: str):
    print(f"[{_ts()}] {msg}")


def _err(msg: str):
    print(f"[{_ts()}] ERROR: {msg}", file=sys.stderr)

# ── Constants (must match ClipboardSyncProfile.swift) ──

SERVICE_UUID = "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2C"
NOTIFY_UUID = "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2D"
WRITE_UUID = "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2E"

MAX_PAYLOAD_BYTES = 1_048_576  # 1 MiB
MSG_HEADER_LEN = 9
CHUNK_HEADER_LEN = 4
MSGTYPE_TEXT = 0x01
MSGTYPE_IMAGE = 0x02
CHUNK_FLAG_LAST = 0x01

# ── Image support (optional) ──

_IMAGE_OK = False
try:
    import io as _io
    import win32clipboard as _wincb

    from PIL import Image as _PILImage
    from PIL import ImageGrab as _ImageGrab

    _IMAGE_OK = True
except ImportError:
    pass


def _read_clipboard_image() -> bytes | None:
    """Returns JPEG bytes from Windows clipboard, or None.

    Note: ``ImageGrab.grabclipboard()`` returns a list of file paths when the
    clipboard holds files (not an image), so that case must be handled here —
    otherwise ``img.mode`` raises ``'list' object has no attribute 'mode'``.
    """
    if not _IMAGE_OK:
        return None
    try:
        img = _ImageGrab.grabclipboard()
        if img is None:
            return None
        if isinstance(img, list):
            # Clipboard contains file paths, not an image — nothing to sync.
            return None
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGBA")
            bg = _PILImage.new("RGBA", img.size, (255, 255, 255, 255))
            img = _PILImage.alpha_composite(bg, img).convert("RGB")
        elif img.mode != "RGB":
            img = img.convert("RGB")
        buf = _io.BytesIO()
        img.save(buf, format="JPEG", quality=75)
        return buf.getvalue()
    except Exception as exc:
        _err(f"Image grab failed: {exc}")
        return None


def _write_clipboard_image(png_data: bytes) -> bool:
    """Writes a PNG image to the Windows clipboard. Returns True on success."""
    if not _IMAGE_OK:
        return False
    try:
        img = _PILImage.open(_io.BytesIO(png_data))
        # Convert to DIB for Win32 clipboard
        output = _io.BytesIO()
        img.save(output, "BMP")
        bmp_data = output.getvalue()[14:]  # skip 14-byte BMP file header
        output.close()
        _wincb.OpenClipboard()
        _wincb.EmptyClipboard()
        _wincb.SetClipboardData(_wincb.CF_DIB, bmp_data)
        _wincb.CloseClipboard()
        return True
    except Exception:
        try:
            _wincb.CloseClipboard()
        except Exception:
            pass
        return False


# ── Reassembler (mirrors ClipboardSyncProfile.Reassembler) ──


class Reassembler:
    def __init__(self):
        self.reset()

    def reset(self):
        self._gathered: bytearray | None = None
        self._expected_msg_id: int | None = None
        self._expected_chunk_idx: int = 0
        self._poison: bool = False

    @property
    def is_active(self) -> bool:
        return self._expected_msg_id is not None

    def feed(self, chunk: bytes) -> bytes | None:
        """Returns complete message bytes or None."""
        if len(chunk) < CHUNK_HEADER_LEN:
            return None
        msg_id = chunk[0]
        chunk_idx = struct.unpack_from("<H", chunk, 1)[0]
        flags = chunk[3]
        payload = chunk[CHUNK_HEADER_LEN:]

        if self._expected_msg_id is not None and msg_id != self._expected_msg_id:
            self.reset()

        if self._expected_msg_id is None:
            if chunk_idx != 0:
                return None
            self._expected_msg_id = msg_id
            self._expected_chunk_idx = 0
            self._gathered = bytearray()
            self._poison = False

        if self._poison:
            if flags & CHUNK_FLAG_LAST:
                self.reset()
            return None

        if chunk_idx != self._expected_chunk_idx:
            self.reset()
            return None

        self._gathered.extend(payload)
        self._expected_chunk_idx += 1

        if chunk_idx == 0 and len(self._gathered) >= MSG_HEADER_LEN:
            header_payload_len = struct.unpack_from("<I", self._gathered, 5)[0]
            if header_payload_len > MAX_PAYLOAD_BYTES:
                self._poison = True
                return None

        if flags & CHUNK_FLAG_LAST:
            complete = bytes(self._gathered)
            self.reset()
            if len(complete) < MSG_HEADER_LEN:
                return None
            header_payload_len = struct.unpack_from("<I", complete, 5)[0]
            payload = complete[MSG_HEADER_LEN:]
            if len(payload) != header_payload_len:
                return None
            msg_type = complete[0]
            if msg_type not in (MSGTYPE_TEXT, MSGTYPE_IMAGE):
                return None
            expected_hash = complete[1:5]
            actual_hash = hashlib.sha256(payload).digest()[:4]
            if actual_hash != expected_hash:
                return None
            return complete
        return None


# ── Clipboard Monitor (runs in a thread, pushes (msg_type, payload) to asyncio.Queue) ──




class ClipboardMonitor:
    def __init__(self, queue: asyncio.Queue, interval: float = 0.5):
        self.queue = queue
        self.interval = interval
        self._last_applied_hash: bytes | None = None
        self._last_sent_hash: bytes | None = None
        self._last_text: str | None = None
        self._running = False
        self._thread: threading.Thread | None = None

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(
            target=self._poll_loop, daemon=True, name="clipboard-monitor"
        )
        self._thread.start()

    def stop(self):
        self._running = False

    def record_applied_text(self, text: str):
        self._last_applied_hash = hashlib.sha256(text.encode()).digest()[:4]
        self._last_text = text
        try:
            pyperclip.copy(text)
        except Exception:
            pass

    def record_applied_image(self, png_data: bytes):
        self._last_text = None
        if _IMAGE_OK:
            try:
                _write_clipboard_image(png_data)
                # Re-read clipboard to get stable hash (JPEG re-encoding changes bytes)
                re_read = _read_clipboard_image()
                if re_read is not None:
                    self._last_applied_hash = hashlib.sha256(re_read).digest()[:4]
                else:
                    self._last_applied_hash = hashlib.sha256(png_data).digest()[:4]
            except Exception:
                self._last_applied_hash = hashlib.sha256(png_data).digest()[:4]
        else:
            self._last_applied_hash = hashlib.sha256(png_data).digest()[:4]

    def _poll_loop(self):
        while self._running:
            try:
                # Image first (clipboard images give empty text from pyperclip)
                img_data = _read_clipboard_image()
                if img_data is not None:
                    h = hashlib.sha256(img_data).digest()[:4]
                    if not (self._last_applied_hash is not None and h == self._last_applied_hash) \
                       and not (self._last_sent_hash is not None and h == self._last_sent_hash):
                        if len(img_data) <= MAX_PAYLOAD_BYTES:
                            self._last_sent_hash = h
                            self._last_text = None
                            _log(f"LOCAL image detected ({len(img_data) / 1024:.1f} KB)")
                            self.queue.put_nowait((MSGTYPE_IMAGE, img_data))
                        else:
                            _log(f"LOCAL image too large ({len(img_data) / 1024:.1f} KB), skipped")
                    continue

                # Text check
                current_text = pyperclip.paste()
                if current_text != self._last_text:
                    self._last_text = current_text
                    if not current_text:
                        continue  # empty clipboard — probably an image we can't read
                    h = hashlib.sha256(current_text.encode()).digest()[:4]
                    if self._last_applied_hash is not None and h == self._last_applied_hash:
                        continue
                    if self._last_sent_hash is not None and h == self._last_sent_hash:
                        continue
                    payload = current_text.encode("utf-8")
                    if len(payload) <= MAX_PAYLOAD_BYTES:
                        self._last_sent_hash = h
                        desc = current_text[:50].replace("\n", " ")
                        _log(f"LOCAL text detected ({len(payload)} B): \"{desc}{'...' if len(current_text) > 50 else ''}\"")
                        self.queue.put_nowait((MSGTYPE_TEXT, payload))
                    else:
                        _log(f"LOCAL text too large ({len(payload)} B), skipped")
            except Exception as exc:
                _err(f"Clipboard poll error: {exc}")
            finally:
                threading.Event().wait(self.interval)


# ── Chunking helpers ──


def pack_message(msg_type: int, payload: bytes) -> bytes:
    """[msgType:1][contentHash:4][payloadLen:4 LE][payload]"""
    h = hashlib.sha256(payload).digest()[:4]
    return struct.pack("<B4sI", msg_type, h, len(payload)) + payload


def pack_chunk(msg_id: int, chunk_idx: int, flags: int, chunk_payload: bytes) -> bytes:
    """[msgID:1][chunkIndex:2 LE][flags:1][chunkPayload]"""
    return struct.pack("<BHB", msg_id, chunk_idx, flags) + chunk_payload


# ── Reconnect / persistence ──


class DeviceDisconnected(Exception):
    """Raised internally when the BLE link drops, to trigger a reconnect."""


CONFIG_PATH = Path.home() / ".btremote_clipboard_sync.json"


def load_saved_device() -> tuple[str | None, str | None]:
    """Return (address, name) of the last successfully connected device, or (None, None)."""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("address"), data.get("name")
    except Exception:
        return None, None


def save_device(address: str, name: str | None):
    """Persist the connected device so the next run can quick-connect by address."""
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump({"address": address, "name": name or ""}, f)
    except Exception as exc:
        _err(f"Could not save device info: {exc}")


# ── Main ──


async def connect_to(address: str, timeout: float) -> bleak.BleakClient:
    """Open a BLE connection, attaching a disconnect callback for fast failure detect."""
    disconnected = asyncio.Event()

    def _on_disconnect(_c):
        disconnected.set()

    client = bleak.BleakClient(address, disconnected_callback=_on_disconnect)
    try:
        await asyncio.wait_for(client.connect(), timeout=timeout)
    except Exception:
        try:
            await client.disconnect()
        except Exception:
            pass
        raise
    client._btremote_disconnected = disconnected  # type: ignore[attr-defined]
    return client


async def scan_for_device(stop_event: asyncio.Event, timeout: float = 30):
    """Passively scan for a BTRemote peripheral; returns the device or None on timeout."""
    device = None

    def detection_callback(d, adv_data):
        nonlocal device
        if device is not None:
            return
        name = adv_data.local_name or d.name or ""
        if "BTRemote" in name or "btremote" in name.lower():
            device = d
        elif "00001812-0000-1000-8000-00805F9B34FB" in [u.lower() for u in (adv_data.service_uuids or [])]:
            device = d

    _log("Scanning for BTRemote device...")
    try:
        async with bleak.BleakScanner(detection_callback) as _scanner:
            try:
                await asyncio.wait_for(
                    asyncio.shield(asyncio.create_task(_wait_device(stop_event))),
                    timeout=timeout,
                )
            except asyncio.TimeoutError:
                pass
    except Exception as exc:
        _err(f"Scan error: {exc}")
    return device


async def run_session(client: bleak.BleakClient, stop_event: asyncio.Event):
    """Run the sync loop until the link drops, the user stops, or an error occurs.

    Raises ``DeviceDisconnected`` (or another exception) to signal the outer loop
    that a reconnect is needed.
    """
    clipboard_svc = None
    for svc in client.services:
        if svc.uuid.lower() == SERVICE_UUID.lower():
            clipboard_svc = svc
            break
    if clipboard_svc is None:
        raise DeviceDisconnected("Clipboard sync service not found — enable Clipboard Sync in BTRemote Settings")
    notify_char = None
    write_char = None
    for char in clipboard_svc.characteristics:
        if char.uuid.lower() == NOTIFY_UUID.lower():
            notify_char = char
        elif char.uuid.lower() == WRITE_UUID.lower():
            write_char = char
    if notify_char is None or write_char is None:
        raise DeviceDisconnected("Clipboard sync characteristics missing — try restarting BTRemote")

    queue: asyncio.Queue = asyncio.Queue()
    monitor = ClipboardMonitor(queue)
    reassembler = Reassembler()

    def on_notify(_char_handle: int, data: bytearray):
        was_active = reassembler.is_active
        msg = reassembler.feed(bytes(data))
        if msg is None:
            if not was_active and reassembler.is_active:
                _log("RECV from Mac: receiving...")
            return
        payload = msg[MSG_HEADER_LEN:]
        msg_type = msg[0]
        msg_len = len(payload)
        if msg_type == MSGTYPE_IMAGE:
            _log(f"RECV from Mac: image ({msg_len / 1024:.1f} KB)")
            monitor.record_applied_image(payload)
        else:
            text = payload.decode("utf-8", errors="replace")
            preview = text[:50].replace("\n", " ")
            _log(f"RECV from Mac: text ({msg_len} B) \"{preview}{'...' if len(text) > 50 else ''}\"")
            monitor.record_applied_text(text)

    await client.start_notify(notify_char, on_notify)

    # Negotiate a larger ATT MTU for faster chunk transfer
    try:
        if hasattr(client, "_backend") and hasattr(client._backend, "_request_mtu"):
            await client._backend._request_mtu(512)
            await asyncio.sleep(0.2)
        chunk_len = max(client.mtu_size - 3 - CHUNK_HEADER_LEN, 16)
        _log(f"MTU: {client.mtu_size} → chunk payload {chunk_len} bytes")
    except Exception as exc:
        _log(f"MTU negotiation skipped: {exc}")

    _log("Notifications subscribed — clipboard sync active")
    _log("Press Ctrl+C to stop")

    # Push current Windows clipboard on connect
    send_queue: asyncio.Queue = asyncio.Queue()
    try:
        initial_text = pyperclip.paste()
        if initial_text:
            initial_payload = initial_text.encode("utf-8")
            if len(initial_payload) <= MAX_PAYLOAD_BYTES:
                send_queue.put_nowait((MSGTYPE_TEXT, initial_payload))
                _log(f"Pushing current Windows clipboard: text ({len(initial_text)} chars)")
    except Exception:
        pass

    monitor.start()
    msg_id_counter = 0

    async def sender():
        nonlocal msg_id_counter
        while True:
            msg_type, payload = await send_queue.get()
            kind = "IMG" if msg_type == MSGTYPE_IMAGE else "TXT"
            msg = pack_message(msg_type, payload)
            msg_id = msg_id_counter % 256
            msg_id_counter += 1
            try:
                mtu = client.mtu_size or 23
            except Exception:
                mtu = 23
            max_chunk_payload = max(mtu - 3 - CHUNK_HEADER_LEN, 16)
            total = (len(msg) + max_chunk_payload - 1) // max_chunk_payload
            size_kb = len(payload) / 1024
            _log(f"SEND {kind} msg_id={msg_id}: {size_kb:.1f} KB, {total} chunks")
            t0 = time.monotonic()
            offset = 0
            for i in range(total):
                flags = CHUNK_FLAG_LAST if i == total - 1 else 0
                end = min(offset + max_chunk_payload, len(msg))
                chunk_payload = msg[offset:end]
                chunk = pack_chunk(msg_id, i, flags, chunk_payload)
                # Bulk-send via writeWithoutResponse; ack only the last chunk
                ack = (i == total - 1)
                try:
                    await client.write_gatt_char(write_char, chunk, response=ack)
                except Exception as exc:
                    raise DeviceDisconnected(f"write failed: {exc}")
                offset = end
            elapsed = time.monotonic() - t0
            _log(f"SEND {kind} msg_id={msg_id}: done in {elapsed:.1f}s")
            send_queue.task_done()

    sender_task = asyncio.create_task(sender())

    async def bridge():
        while True:
            item = await queue.get()
            await send_queue.put(item)

    bridge_task = asyncio.create_task(bridge())

    disconnected = getattr(client, "_btremote_disconnected", None)

    async def watchdog():
        while True:
            await asyncio.sleep(2)
            if disconnected is not None and disconnected.is_set():
                raise DeviceDisconnected("link lost (disconnect callback fired)")
            if not client.is_connected:
                raise DeviceDisconnected("link lost (is_connected=False)")

    watchdog_task = asyncio.create_task(watchdog())

    stop_wait = asyncio.create_task(stop_event.wait())
    try:
        done, _pending = await asyncio.wait(
            {sender_task, bridge_task, watchdog_task, stop_wait},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for t in done:
            if t is stop_wait:
                continue
            exc = t.exception()
            if exc is not None:
                raise exc
    finally:
        monitor.stop()
        for t in (sender_task, bridge_task, watchdog_task, stop_wait):
            t.cancel()
        try:
            await client.stop_notify(notify_char)
        except Exception:
            pass
        for t in (sender_task, bridge_task, watchdog_task):
            try:
                await t
            except (asyncio.CancelledError, DeviceDisconnected):
                pass


async def main():
    _log("=== BTRemote Clipboard Sync ===")
    if _IMAGE_OK:
        _log("Image sync: enabled (pillow + pywin32 found)")
    else:
        _log("Image sync: unavailable (install pillow + pywin32 for image support)")

    stop_event = asyncio.Event()
    saved_addr, saved_name = load_saved_device()
    if saved_addr:
        _log(f"Saved device: {saved_name or saved_addr} — will quick-connect")

    reconnect_delay = 3
    while not stop_event.is_set():
        client = None
        try:
            # Fast path: direct connect to the last known address (no scan wait).
            if saved_addr:
                _log(f"Quick-connect to saved device {saved_addr}...")
                try:
                    client = await connect_to(saved_addr, timeout=10)
                except Exception as exc:
                    _err(f"Quick-connect failed ({exc}); falling back to scan")
                    client = None

            if client is None or not client.is_connected:
                device = await scan_for_device(stop_event, timeout=30)
                if device is None:
                    _err("No BTRemote device found; retrying in 5s")
                    await asyncio.sleep(5)
                    continue
                saved_addr = device.address
                saved_name = device.name
                client = await connect_to(device.address, timeout=15)

            if not client.is_connected:
                _err("Connection failed — ensure the device is paired in Bluetooth Settings")
                await asyncio.sleep(reconnect_delay)
                continue

            save_device(client.address, saved_name)
            _log(f"Connected: {client.address}")
            await run_session(client, stop_event)
        except KeyboardInterrupt:
            _log("Stopping...")
            break
        except DeviceDisconnected as exc:
            _err(f"Disconnected: {exc}")
        except Exception as exc:
            _err(f"Session error: {exc}")
        finally:
            if client is not None:
                try:
                    await client.disconnect()
                except Exception:
                    pass
            _log(f"Reconnecting in {reconnect_delay}s...")
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=reconnect_delay)
            except asyncio.TimeoutError:
                pass
    return 0


async def _wait_device(stop_event: asyncio.Event):
    """Wait until stop_event is set (used to bound the scan window)."""
    while not stop_event.is_set():
        await asyncio.sleep(0.1)


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
