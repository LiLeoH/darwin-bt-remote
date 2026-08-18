#if os(macOS)
    import CoreBluetooth
    import CryptoKit
    import Foundation

    /// Clipboard sync GATT service protocol definitions.
    /// The service exposes two characteristics:
    /// - Notify (device → host): chunked clipboard content.
    /// - Write  (host → device): chunked clipboard content.
    enum ClipboardSyncProfile {
        // MARK: - UUIDs (hardcoded; must match the Windows companion tool)

        nonisolated(unsafe) static let service = CBUUID(string: "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2C")
        nonisolated(unsafe) static let notifyChar = CBUUID(string: "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2D")
        nonisolated(unsafe) static let writeChar = CBUUID(string: "E95A7B2C-3F4D-4A1E-8C5D-6B7F9E0A1B2E")

        // MARK: - Limits

        static let maxPayloadBytes = 1_048_576
        static let messageHeaderLen = 9
        static let chunkHeaderLen = 4
        static let reassembleTimeout: TimeInterval = 5

        // MARK: - Message Types

        static let msgTypeText: UInt8 = 0x01
        static let msgTypeImage: UInt8 = 0x02

        // MARK: - Chunk Flags

        static let chunkFlagLast: UInt8 = 0x01

        // MARK: - Hashing

        static func hash4(_ payload: Data) -> Data {
            Data(SHA256.hash(data: payload).prefix(4))
        }

        // MARK: - Packing

        /// Builds a complete message: [msgType:1][contentHash:4][payloadLen:4 LE][payload UTF-8]
        static func packMessage(msgType: UInt8, payload: Data) -> Data {
            var data = Data(capacity: messageHeaderLen + payload.count)
            data.append(msgType)
            data.append(hash4(payload))
            let len = UInt32(payload.count).littleEndian
            withUnsafeBytes(of: len) { data.append(contentsOf: $0) }
            data.append(payload)
            return data
        }

        /// Wraps `chunkPayload` in a chunk header: [msgID:1][chunkIndex:2 LE][flags:1][chunkPayload]
        static func packChunk(msgID: UInt8, chunkIndex: UInt16, flags: UInt8, chunkPayload: Data) -> Data {
            var chunk = Data(capacity: chunkHeaderLen + chunkPayload.count)
            chunk.append(msgID)
            let cidx = chunkIndex.littleEndian
            withUnsafeBytes(of: cidx) { chunk.append(contentsOf: $0) }
            chunk.append(flags)
            chunk.append(chunkPayload)
            return chunk
        }

        // MARK: - Reassembler

        final class Reassembler {
            private var gatheredChunks: Data?
            private var expectedMsgID: UInt8?
            private var expectedChunkIndex: UInt16 = 0
            private var poison = false

            /// Whether a message is currently being reassembled.
            var isActive: Bool {
                expectedMsgID != nil
            }

            func feed(chunk: Data) -> Data? {
                guard chunk.count >= chunkHeaderLen else { return nil }
                let msgID = chunk[0]
                let cidxRaw = chunk.subdata(in: 1 ..< 3)
                let chunkIndex = cidxRaw.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
                let flags = chunk[3]
                let payload = chunk.subdata(in: chunkHeaderLen ..< chunk.count)

                if let expected = expectedMsgID, msgID != expected {
                    reset()
                }

                if expectedMsgID == nil {
                    if chunkIndex != 0 {
                        return nil
                    }
                    expectedMsgID = msgID
                    expectedChunkIndex = 0
                    gatheredChunks = Data()
                    poison = false
                }

                if poison {
                    if flags & chunkFlagLast != 0 {
                        reset()
                    }
                    return nil
                }

                if chunkIndex != expectedChunkIndex {
                    reset()
                    return nil
                }

                gatheredChunks?.append(payload)
                expectedChunkIndex += 1

                if chunkIndex == 0, let raw = gatheredChunks {
                    if raw.count >= messageHeaderLen {
                        let headerPayloadLen = raw.subdata(in: 5 ..< 9)
                            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                        if headerPayloadLen > maxPayloadBytes {
                            poison = true
                            return nil
                        }
                    }
                }

                if flags & chunkFlagLast != 0 {
                    let complete = gatheredChunks
                    reset()
                    guard let complete, complete.count >= messageHeaderLen else { return nil }
                    let headerPayloadLen = complete
                        .subdata(in: 5 ..< 9)
                        .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                    let payload = complete.subdata(in: messageHeaderLen ..< complete.count)
                    guard payload.count == headerPayloadLen else { return nil }
                    let msgType = complete[0]
                    guard msgType == msgTypeText || msgType == msgTypeImage else { return nil }
                    let expectedHash = complete.subdata(in: 1 ..< 5)
                    guard hash4(payload) == expectedHash else { return nil }
                    return complete
                }

                return nil
            }

            func reset() {
                gatheredChunks = nil
                expectedMsgID = nil
                expectedChunkIndex = 0
                poison = false
            }
        }
    }
#endif
