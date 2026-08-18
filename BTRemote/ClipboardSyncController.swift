#if os(macOS)
    import AppKit
    import Combine
    import os
    import QuartzCore
    import SwiftUI

    /// Manages clipboard sync over the clipboard GATT service.
    /// Polls NSPasteboard changeCount while a host is subscribed; assembles
    /// incoming chunks via ClipboardSyncProfile.Reassembler.
    @MainActor
    final class ClipboardSyncController: ObservableObject {
        @AppStorage(AppSettings.clipboardSyncEnabledKey) private var syncEnabled = true
        @AppStorage(AppSettings.clipboardSyncImagesEnabledKey) private var syncImagesEnabled = true

        private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "ClipboardSync")
        @Published var progressStatus: String? {
            didSet { updateProgressWindow() }
        }

        private var progressWindow: NSWindow?
        private var progressLabel: NSTextField?
        private var progressMaxWidth: CGFloat = 80
        private var progressDismissTask: Task<Void, Never>?
        private var sendStartTime: TimeInterval = 0
        private var sendChunkTotal: Int = 0
        private var currentMsgType: String = ""
        private var peripheral: HIDPeripheral?
        private var subscribedCount = 0
        private var pollTimer: Timer?
        private var lastChangeCount: Int = NSPasteboard.general.changeCount
        private var lastSentHash: Data?
        private var lastAppliedRemoteHash: Data?

        // Sending state
        private var outbox: [Data] = [] // queued complete messages
        private var currentMsg: PendingMessage?
        private var msgIDCounter: UInt8 = 0
        private var chunkTimer: Timer?
        private var sendWatchdog: Timer?

        private static let chunkPacingInterval: TimeInterval = 0.01 // 10 ms between chunks
        private static let jpegQuality: CGFloat = 0.75
        private static let sendStallTimeout: TimeInterval = 5.0

        /// Reads the pasteboard PNG, converts to JPEG for smaller BLE transfer.
        private func jpegFromPasteboard(_ pasteboard: NSPasteboard) -> Data? {
            guard let pngData = pasteboard.data(forType: .png),
                  let image = NSImage(data: pngData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: Self.jpegQuality])
        }

        private struct PendingMessage {
            let msgID: UInt8
            let chunks: [Data]
            var nextIndex: Int
        }

        private var inboundReassembler = ClipboardSyncProfile.Reassembler()

        private var isAttached = false
        /// Observes the peripheral's live subscription set so the sync gate can never
        /// drift from what the UI shows as "Subscribed Centrals" (e.g. after a BLE
        /// power-cycle reset that clears subscriptions without firing unsubscribe).
        private var subscriptionObserver: AnyCancellable?

        func attach(peripheral: HIDPeripheral) {
            guard !isAttached else { return }
            isAttached = true
            self.peripheral = peripheral

            peripheral.onClipboardWrite = { [weak self] _, value in
                self?.handleIncomingChunk(value)
            }
            peripheral.onClipboardSubscriptionChange = { [weak self] in
                self?.refreshSubscriptionCount()
            }
            peripheral.onClipboardReady = { [weak self] in
                self?.resumeSending()
            }

            // Bind the sync gate to the authoritative subscription state. This fires
            // on every change — including resets that drop all subscriptions silently —
            // so polling/push never continues when the subscribed-central count is 0.
            subscriptionObserver = peripheral.$subscribedCentrals
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.refreshSubscriptionCount() }
                }
            refreshSubscriptionCount()
        }

        // MARK: - Subscription management

        private func refreshSubscriptionCount() {
            guard let p = peripheral else { return }
            let count = p.subscribedCentrals.values
                .filter { $0.contains(ClipboardSyncProfile.notifyChar) }
                .count
            let wasActive = subscribedCount > 0
            subscribedCount = count
            let isActive = count > 0
            if isActive, syncEnabled {
                startPolling()
                // Only push the current clipboard on a genuine (re)subscribe so that
                // unrelated subscription changes (e.g. a HID report subscribing) don't
                // re-fire a send.
                if !wasActive {
                    pushCurrentClipboard()
                }
            } else {
                stopPolling()
                // Peer dropped all subscriptions — abort any in-flight send
                if wasActive, currentMsg != nil || !outbox.isEmpty {
                    abortSend()
                }
            }
        }

        // MARK: - Polling

        private func startPolling() {
            guard pollTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollClipboard() }
            }
            pollTimer = timer
        }

        private func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
            chunkTimer?.invalidate()
            chunkTimer = nil
        }

        private func pollClipboard() {
            guard peripheral != nil, subscribedCount > 0, syncEnabled else { return }
            let pasteboard = NSPasteboard.general
            let currentCount = pasteboard.changeCount
            guard currentCount != lastChangeCount else { return }
            lastChangeCount = currentCount

            // Text first, then image
            if let text = pasteboard.string(forType: .string) {
                let payload = Data(text.utf8)
                guard payload.count <= ClipboardSyncProfile.maxPayloadBytes else { return }
                let hash = ClipboardSyncProfile.hash4(payload)
                if let lastApplied = lastAppliedRemoteHash, hash == lastApplied {
                    return
                }
                if let lastSent = lastSentHash, hash == lastSent {
                    return
                }
                enqueueMessage(
                    payload: payload,
                    hash: hash,
                    msgType: ClipboardSyncProfile.msgTypeText
                )
            } else if syncImagesEnabled,
                      let imageData = jpegFromPasteboard(pasteboard)
            {
                guard imageData.count <= ClipboardSyncProfile.maxPayloadBytes else { return }
                let hash = ClipboardSyncProfile.hash4(imageData)
                if let lastApplied = lastAppliedRemoteHash, hash == lastApplied {
                    return
                }
                if let lastSent = lastSentHash, hash == lastSent {
                    return
                }
                enqueueMessage(
                    payload: imageData,
                    hash: hash,
                    msgType: ClipboardSyncProfile.msgTypeImage
                )
            }
        }

        /// Push current clipboard on subscribe (mirrors didSubscribeTo cachedReports baseline).
        private func pushCurrentClipboard() {
            let pasteboard = NSPasteboard.general
            lastChangeCount = pasteboard.changeCount
            if let text = pasteboard.string(forType: .string) {
                let payload = Data(text.utf8)
                guard payload.count <= ClipboardSyncProfile.maxPayloadBytes else { return }
                let hash = ClipboardSyncProfile.hash4(payload)
                enqueueMessage(
                    payload: payload,
                    hash: hash,
                    msgType: ClipboardSyncProfile.msgTypeText
                )
            } else if syncImagesEnabled,
                      let imageData = jpegFromPasteboard(pasteboard)
            {
                guard imageData.count <= ClipboardSyncProfile.maxPayloadBytes else { return }
                let hash = ClipboardSyncProfile.hash4(imageData)
                enqueueMessage(
                    payload: imageData,
                    hash: hash,
                    msgType: ClipboardSyncProfile.msgTypeImage
                )
            }
        }

        // MARK: - Send queue

        private func enqueueMessage(payload: Data, hash: Data, msgType: UInt8) {
            guard subscribedCount > 0 else { return }
            let message = ClipboardSyncProfile.packMessage(
                msgType: msgType,
                payload: payload
            )
            outbox.append(message)
            lastSentHash = hash
            if currentMsg == nil {
                dequeueNext()
            }
        }

        private func dequeueNext() {
            guard !outbox.isEmpty else { return }
            let msg = outbox.removeFirst()
            let maxPayload = peripheral?.clipboardMaxChunkPayload() ?? 16
            let msgID = msgIDCounter
            msgIDCounter &+= 1

            let totalChunks = (msg.count + maxPayload - 1) / maxPayload
            guard totalChunks <= UInt16.max else { return }

            // Record send metadata for progress banner
            currentMsgType = msg[0] == ClipboardSyncProfile.msgTypeImage ? "image" : "text"
            sendChunkTotal = totalChunks
            sendStartTime = CACurrentMediaTime()
            let payloadSize = msg.count - ClipboardSyncProfile.messageHeaderLen
            let sizeStr = payloadSize < 1024 ? "\(payloadSize)B" : String(format: "%.1fKB", Double(payloadSize) / 1024)
            if totalChunks == 1 {
                progressStatus = "Sending \(currentMsgType) \(sizeStr)..."
            } else {
                progressStatus = "Sending \(currentMsgType) \(sizeStr) 0/\(totalChunks)"
            }

            var chunks: [Data] = []
            var offset = 0
            for idx in 0 ..< totalChunks {
                let flags: UInt8 = (idx == totalChunks - 1) ? ClipboardSyncProfile.chunkFlagLast : 0
                let end = min(offset + maxPayload, msg.count)
                let chunkPayload = msg.subdata(in: offset ..< end)
                let chunk = ClipboardSyncProfile.packChunk(
                    msgID: msgID,
                    chunkIndex: UInt16(idx),
                    flags: flags,
                    chunkPayload: chunkPayload
                )
                chunks.append(chunk)
                offset = end
            }
            currentMsg = PendingMessage(msgID: msgID, chunks: chunks, nextIndex: 0)
            sendOneChunk()
        }

        /// Sends exactly one chunk. On success, schedules the next chunk via a short timer;
        /// on failure (buffer full), waits for onClipboardReady to resume.
        private func sendOneChunk() {
            chunkTimer?.invalidate()
            chunkTimer = nil
            sendWatchdog?.invalidate()
            sendWatchdog = nil
            guard let state = currentMsg, let p = peripheral else { return }
            guard state.nextIndex < state.chunks.count else {
                // Message fully sent — show completion
                let elapsed = CACurrentMediaTime() - sendStartTime
                progressStatus = "Sent \(currentMsgType) in \(String(format: "%.1f", elapsed))s"
                scheduleProgressDismiss()
                currentMsg = nil
                dequeueNext()
                return
            }
            let chunk = state.chunks[state.nextIndex]
            if p.sendClipboardChunk(chunk) {
                currentMsg?.nextIndex += 1
                guard let state = currentMsg else { return }
                if state.chunks.count > 1 {
                    progressStatus = "Sending \(currentMsgType)... \(state.nextIndex)/\(state.chunks.count)"
                }
                scheduleNextChunk()
            } else {
                // Buffer full — wait for onClipboardReady, arm watchdog
                sendWatchdog = Timer.scheduledTimer(
                    withTimeInterval: Self.sendStallTimeout, repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in self?.abortSend() }
                }
            }
        }

        private func abortSend() {
            currentMsg = nil
            outbox.removeAll()
            chunkTimer?.invalidate()
            chunkTimer = nil
            sendWatchdog?.invalidate()
            sendWatchdog = nil
            progressStatus = "Send failed (peer disconnected)"
            scheduleProgressDismiss()
        }

        private func scheduleNextChunk() {
            chunkTimer?.invalidate()
            chunkTimer = Timer.scheduledTimer(
                withTimeInterval: Self.chunkPacingInterval, repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.sendOneChunk() }
            }
        }

        private func resumeSending() {
            chunkTimer?.invalidate()
            chunkTimer = nil
            sendOneChunk()
        }

        // MARK: - Incoming

        private func handleIncomingChunk(_ chunk: Data) {
            autoreleasepool {
                let hadPending = inboundReassembler.isActive
                guard let complete = inboundReassembler.feed(chunk: chunk) else {
                    if !hadPending, inboundReassembler.isActive {
                        progressStatus = "Receiving..."
                    }
                    return
                }
                applyRemoteMessage(complete)
            }
        }

        private func applyRemoteMessage(_ message: Data) {
            autoreleasepool {
                _applyRemoteMessageInner(message)
            }
        }

        private func _applyRemoteMessageInner(_ message: Data) {
            guard message.count >= ClipboardSyncProfile.messageHeaderLen else { return }
            let payload = message.subdata(
                in: ClipboardSyncProfile.messageHeaderLen ..< message.count
            )
            let msgType = message[0]
            let hash = ClipboardSyncProfile.hash4(payload)
            let expectedHash = message.subdata(in: 1 ..< 5)
            guard hash == expectedHash else { return }

            let kind = msgType == ClipboardSyncProfile.msgTypeImage ? "image" : "text"
            let sizeStr = payload.count < 1024 ? "\(payload.count)B" : String(format: "%.1fKB", Double(payload.count) / 1024)
            progressStatus = "Received \(kind) \(sizeStr)"
            scheduleProgressDismiss()

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            switch msgType {
            case ClipboardSyncProfile.msgTypeText:
                guard let text = String(data: payload, encoding: .utf8) else { return }
                pasteboard.setString(text, forType: .string)
            case ClipboardSyncProfile.msgTypeImage:
                guard let image = NSImage(data: payload) else { return }
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                pasteboard.setData(png, forType: .png)
            default:
                return
            }
            lastChangeCount = pasteboard.changeCount
            // Re-hash clipboard content for echo suppression (JPEG→PNG changes bytes)
            lastAppliedRemoteHash = _pasteboardHash(pasteboard)
        }

        private func _pasteboardHash(_ pb: NSPasteboard) -> Data? {
            if let text = pb.string(forType: .string) {
                return ClipboardSyncProfile.hash4(Data(text.utf8))
            }
            if let png = pb.data(forType: .png) {
                return ClipboardSyncProfile.hash4(png)
            }
            return nil
        }

        // MARK: - Progress window (independent floating window, top-right)

        private func updateProgressWindow() {
            if let status = progressStatus {
                showProgressWindow(status)
            } else {
                progressWindow?.orderOut(nil)
                progressMaxWidth = 80
            }
        }

        private func showProgressWindow(_ status: String) {
            if progressWindow == nil {
                let win = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 260, height: 36),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                win.level = .floating
                win.isOpaque = false
                win.backgroundColor = .clear
                win.ignoresMouseEvents = true
                win.collectionBehavior = [.canJoinAllSpaces, .stationary]
                win.hasShadow = true
                win.isMovable = false

                let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                container.layer?.cornerRadius = 18
                container.layer?.masksToBounds = true

                let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.alignment = .center
                label.textColor = .labelColor
                label.lineBreakMode = .byTruncatingMiddle
                label.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14)
                ])

                win.contentView = container
                progressLabel = label
                progressWindow = win
            }
            guard let win = progressWindow, let label = progressLabel else { return }

            label.stringValue = status

            // Grow-only width: never shrink, avoids jitter
            let textSize = (status as NSString).size(withAttributes: [.font: label.font!])
            let needed = max(textSize.width + 32, 80)
            if needed > progressMaxWidth {
                progressMaxWidth = needed
            }
            let width = progressMaxWidth
            let height: CGFloat = 36
            var frame = win.frame
            frame.size = NSSize(width: width, height: height)
            win.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)

            // Position top-right with padding
            if let screen = win.screen ?? NSScreen.main {
                let x = screen.visibleFrame.maxX - width - 20
                let y = screen.visibleFrame.maxY - height - 20
                frame.origin = NSPoint(x: x, y: y)
            }
            win.setFrame(frame, display: true)
            if !win.isVisible {
                win.orderFront(nil)
            }
        }

        private func scheduleProgressDismiss() {
            progressDismissTask?.cancel()
            progressDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    self?.progressStatus = nil
                }
            }
        }
    }
#endif
