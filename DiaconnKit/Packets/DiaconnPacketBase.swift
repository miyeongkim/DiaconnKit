import Foundation

/// 디아콘 G8 패킷 인코딩/디코딩 기본 유틸리티
/// 패킷 구조: [SOP(1)] [msgType(1)] [msgSeq(1)] [msgConEnd(1)] [DATA(12)] [PAD(0xFF)] [CRC(1)]
/// 총 20바이트 고정 (대량 패킷은 182바이트)
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

    // 이전 호환성을 위한 opCode alias
    public var opCode: UInt8 { msgType }
}

/// 디아콘 G8에서 수신한 패킷 파싱 결과
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

/// 패킷 인코더: 명령을 20바이트 패킷으로 조립
public enum DiaconnPacketEncoder {
    private static var sequence: Int = 0

    /// 다음 시퀀스 번호 생성 (0~254 순환)
    static func nextSequence() -> UInt8 {
        let seq = sequence % 255
        sequence += 1
        if sequence == 255 {
            sequence = 0
        }
        return UInt8(seq)
    }

    /// 패킷 인코딩
    /// - Parameters:
    ///   - msgType: 명령 타입
    ///   - msgConEnd: 0x00=종료, 0x01=계속
    ///   - payload: 데이터 (최대 15바이트, 나머지 0xFF 패딩)
    /// - Returns: 20바이트 패킷
    public static func encode(
        msgType: UInt8,
        msgSeq: UInt8? = nil,
        msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END,
        payload: Data? = nil
    ) -> Data {
        var buffer = Data(count: DiaconnPacketType.MSG_LEN)

        // 헤더
        buffer[0] = DiaconnPacketType.SOP
        buffer[1] = msgType
        buffer[2] = msgSeq ?? nextSequence()
        buffer[3] = msgConEnd

        // 데이터 삽입
        if let payload = payload {
            let dataLen = min(payload.count, DiaconnPacketType.MSG_LEN - 5) // 헤더4 + CRC1 제외
            for i in 0 ..< dataLen {
                buffer[4 + i] = payload[i]
            }
        }

        // 남은 공간 패딩 (CRC 위치 제외)
        let dataEnd = 4 + (payload?.count ?? 0)
        for i in dataEnd ..< (DiaconnPacketType.MSG_LEN - 1) {
            buffer[i] = DiaconnPacketType.MSG_PAD
        }

        // CRC (마지막 1바이트)
        buffer[DiaconnPacketType.MSG_LEN - 1] = DiaconnCRC.calculate(buffer, length: DiaconnPacketType.MSG_LEN - 1)

        return buffer
    }

    /// 대량 패킷(182바이트) 인코딩
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

/// 패킷 디코더: 수신된 바이트를 파싱
public enum DiaconnPacketDecoder {
    /// 패킷 결함 검사
    /// - Returns: 0=정상, 97=길이오류, 98=SOP오류, 99=CRC오류
    public static func validatePacket(_ bytes: Data) -> Int {
        guard !bytes.isEmpty else { return 98 }

        // SOP 확인
        if bytes[0] != DiaconnPacketType.SOP && bytes[0] != DiaconnPacketType.SOP_BIG {
            return 98
        }

        // 길이 확인
        if (bytes[0] == DiaconnPacketType.SOP && bytes.count != DiaconnPacketType.MSG_LEN) ||
            (bytes[0] == DiaconnPacketType.SOP_BIG && bytes.count != DiaconnPacketType.MSG_LEN_BIG)
        {
            return 97
        }

        // CRC 확인
        let expectedCRC = DiaconnCRC.calculate(bytes, length: bytes.count - 1)
        if bytes[bytes.count - 1] != expectedCRC {
            return 99
        }

        return 0
    }

    /// msgType 추출
    public static func getMsgType(_ bytes: Data) -> UInt8 {
        bytes[DiaconnPacketType.MSG_TYPE_LOC]
    }

    /// 상위 2비트로 패킷 타입 추출 (0=설정, 1=조회, 2=?, 3=보고)
    public static func getType(_ bytes: Data) -> Int {
        (Int(bytes[DiaconnPacketType.MSG_TYPE_LOC]) & 0xC0) >> 6
    }

    /// 시퀀스 번호 추출
    public static func getSeq(_ bytes: Data) -> UInt8 {
        bytes[DiaconnPacketType.MSG_SEQ_LOC]
    }

    /// 데이터 영역 추출 (offset 4부터)
    public static func getPayload(_ bytes: Data) -> Data {
        let start = DiaconnPacketType.MSG_DATA_LOC
        let end = bytes.count - 1 // CRC 제외
        guard start < end else { return Data() }
        return bytes.subdata(in: start ..< end)
    }

    /// Little-endian으로 1바이트 읽기
    public static func readByte(_ data: Data, offset: Int) -> UInt8 {
        guard offset < data.count else { return 0 }
        return data[offset]
    }

    /// Little-endian으로 2바이트(short) 읽기
    public static func readShort(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    /// Little-endian으로 4바이트(int) 읽기
    public static func readInt(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

/// Little-endian으로 Data에 값 쓰기 헬퍼
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
}
