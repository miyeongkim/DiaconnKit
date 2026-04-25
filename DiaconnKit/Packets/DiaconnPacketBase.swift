import Foundation

/// Diaconn G8 packet encoding/decoding base utility
/// Packet structure: [SOP(1)] [msgType(1)] [msgSeq(1)] [msgConEnd(1)] [DATA(12)] [PAD(0xFF)] [CRC(1)]
/// Fixed 20 bytes total (big packet is 182 bytes)
public struct DiaconnGeneratePacket {
    public let name: String
    public let msgType: UInt8
    public let msgConEnd: UInt8
    public let data: Data?

    public init(name: String, msgType: UInt8, msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END, data: Data? = nil) {
        self.name = name
        self.msgType = msgType
        self.msgConEnd = msgConEnd
        self.data = data
    }

    // opCode alias for backward compatibility
    public var opCode: UInt8 { msgType }
}

/// Parsed result of packet received from Diaconn G8
public struct DiaconnParsePacket {
    public let success: Bool
    public let msgType: UInt8
    public let msgSeq: UInt8
    public let rawData: Data
    public let data: Any?

    public init(success: Bool, msgType: UInt8 = 0, msgSeq: UInt8 = 0, rawData: Data, data: Any?) {
        self.success = success
        self.msgType = msgType
        self.msgSeq = msgSeq
        self.rawData = rawData
        self.data = data
    }
}

/// Packet encoder: assemble command into 20-byte packet
public enum DiaconnPacketEncoder {
    private static var sequence: Int = 0

    /// Generate next sequence number (0~254 cyclic)
    static func nextSequence() -> UInt8 {
        let seq = sequence % 255
        sequence += 1
        if sequence == 255 {
            sequence = 0
        }
        return UInt8(seq)
    }

    /// Encode packet
    /// - Parameters:
    ///   - msgType: command type
    ///   - msgConEnd: 0x00=end, 0x01=continue
    ///   - payload: data (max 15 bytes, remainder padded with 0xFF)
    /// - Returns: 20-byte packet
    public static func encode(
        msgType: UInt8,
        msgSeq: UInt8? = nil,
        msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END,
        payload: Data? = nil
    ) -> Data {
        var buffer = Data(count: DiaconnPacketType.MSG_LEN)

        // Header
        buffer[0] = DiaconnPacketType.SOP
        buffer[1] = msgType
        buffer[2] = msgSeq ?? nextSequence()
        buffer[3] = msgConEnd

        // Insert data
        if let payload = payload {
            let dataLen = min(payload.count, DiaconnPacketType.MSG_LEN - 5) // Excluding header(4) + CRC(1)
            for i in 0 ..< dataLen {
                buffer[4 + i] = payload[i]
            }
        }

        // Pad remaining space (excluding CRC position)
        let dataEnd = 4 + (payload?.count ?? 0)
        for i in dataEnd ..< (DiaconnPacketType.MSG_LEN - 1) {
            buffer[i] = DiaconnPacketType.MSG_PAD
        }

        // CRC (last 1 byte)
        buffer[DiaconnPacketType.MSG_LEN - 1] = DiaconnCRC.calculate(buffer, length: DiaconnPacketType.MSG_LEN - 1)

        return buffer
    }

    /// Encode big packet (182 bytes)
    public static func encodeBig(
        msgType: UInt8,
        msgSeq: UInt8? = nil,
        msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END,
        payload: Data? = nil
    ) -> Data {
        var buffer = Data(count: DiaconnPacketType.MSG_LEN_BIG)

        buffer[0] = DiaconnPacketType.SOP_BIG
        buffer[1] = msgType
        buffer[2] = msgSeq ?? nextSequence()
        buffer[3] = msgConEnd

        if let payload = payload {
            let dataLen = min(payload.count, DiaconnPacketType.MSG_LEN_BIG - 5)
            for i in 0 ..< dataLen {
                buffer[4 + i] = payload[i]
            }
        }

        let dataEnd = 4 + (payload?.count ?? 0)
        for i in dataEnd ..< (DiaconnPacketType.MSG_LEN_BIG - 1) {
            buffer[i] = DiaconnPacketType.MSG_PAD
        }

        buffer[DiaconnPacketType.MSG_LEN_BIG - 1] = DiaconnCRC.calculate(buffer, length: DiaconnPacketType.MSG_LEN_BIG - 1)

        return buffer
    }
}

/// Packet decoder: parse received bytes
public enum DiaconnPacketDecoder {
    /// Validate packet
    /// - Returns: 0=valid, 97=length error, 98=SOP error, 99=CRC error
    public static func validatePacket(_ bytes: Data) -> Int {
        guard !bytes.isEmpty else { return 98 }

        // SOP check
        if bytes[0] != DiaconnPacketType.SOP && bytes[0] != DiaconnPacketType.SOP_BIG {
            return 98
        }

        // Length check
        if (bytes[0] == DiaconnPacketType.SOP && bytes.count != DiaconnPacketType.MSG_LEN) ||
            (bytes[0] == DiaconnPacketType.SOP_BIG && bytes.count != DiaconnPacketType.MSG_LEN_BIG)
        {
            return 97
        }

        // CRC check
        let expectedCRC = DiaconnCRC.calculate(bytes, length: bytes.count - 1)
        if bytes[bytes.count - 1] != expectedCRC {
            return 99
        }

        return 0
    }

    /// Extract msgType
    public static func getMsgType(_ bytes: Data) -> UInt8 {
        bytes[DiaconnPacketType.MSG_TYPE_LOC]
    }

    /// Extract packet type from upper 2 bits (0=setting, 1=inquiry, 2=?, 3=report)
    public static func getType(_ bytes: Data) -> Int {
        (Int(bytes[DiaconnPacketType.MSG_TYPE_LOC]) & 0xC0) >> 6
    }

    /// Extract sequence number
    public static func getSeq(_ bytes: Data) -> UInt8 {
        bytes[DiaconnPacketType.MSG_SEQ_LOC]
    }

    /// Extract data payload (from offset 4)
    public static func getPayload(_ bytes: Data) -> Data {
        let start = DiaconnPacketType.MSG_DATA_LOC
        let end = bytes.count - 1 // Exclude CRC
        guard start < end else { return Data() }
        return bytes.subdata(in: start ..< end)
    }

    /// Read 1 byte as little-endian
    public static func readByte(_ data: Data, offset: Int) -> UInt8 {
        guard offset < data.count else { return 0 }
        return data[offset]
    }

    /// Read 2 bytes (short) as little-endian
    public static func readShort(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    /// Read 4 bytes (int) as little-endian
    public static func readInt(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

/// Helper for writing values to Data in little-endian
extension Data {
    mutating func appendShortLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendIntLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
