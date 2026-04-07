import Foundation

// MARK: - 간식(스낵) 볼루스 주입 (msgType: 0x07)

/// 볼루스 주입 명령 생성
/// - Parameter amount: 인슐린 단위 (예: 2.5U → short값 250)
func generateBolusPacket(amount: Double) -> Data {
    var payload = Data()
    payload.appendShortLE(UInt16(amount * 100))
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_SNACK_SETTING,
        payload: payload
    )
}

/// 볼루스 응답 파싱 (msgType: 0x87)
struct BolusSettingResponse {
    let result: UInt8 // 0=성공, 기타=에러
    let otpNumber: UInt32 // OTP 확인 번호

    var isSuccess: Bool { result == 0 }
}

func parseBolusSettingResponse(_ data: Data) -> BolusSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BolusSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - 확장 볼루스 주입 (msgType: 0x0C)

/// 확장 볼루스 명령 생성
/// - Parameters:
///   - amount: 인슐린 단위
///   - durationMinutes: 지속 시간 (분)
func generateExtendedBolusPacket(amount: Double, durationMinutes: UInt16) -> Data {
    var payload = Data()
    payload.appendShortLE(durationMinutes)
    payload.appendShortLE(UInt16(amount * 100))
    payload.appendIntLE(UInt32(946_652_400)) // 기준 시간 (2000-01-01)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_EXTENDED_BOLUS_SETTING,
        payload: payload
    )
}

/// 확장 볼루스 응답 파싱 (msgType: 0x8C)
func parseExtendedBolusSettingResponse(_ data: Data) -> BolusSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BolusSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - 주입 취소 (msgType: 0x2B)

/// 주입 취소 명령 생성
/// - Parameter reqMsgType: 취소할 명령의 msgType (예: 0x07=볼루스, 0x0C=확장볼루스)
func generateInjectionCancelPacket(reqMsgType: UInt8) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_CANCEL_SETTING,
        payload: payload
    )
}

/// 주입 취소 응답 파싱 (msgType: 0xAB)
func parseInjectionCancelResponse(_ data: Data) -> BolusSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BolusSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - 볼루스 속도 설정 (msgType: 0x0E)

/// 볼루스 속도 설정 (1~8)
func generateBolusSpeedPacket(speed: UInt8) -> Data {
    var payload = Data()
    payload.append(speed)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.BOLUS_SPEED_SETTING,
        payload: payload
    )
}

/// 볼루스 속도 설정 응답 (msgType: 0x85)
/// 응답 포맷: 주입속도(1byte, 1~8) + 1회용 토큰키(4bytes, 6자리 Random)
struct BolusSpeedSettingResponse {
    let speed: UInt8
    let token: UInt32
    var isSuccess: Bool { speed >= 1 && speed <= 8 }
}

func parseBolusSpeedSettingResponse(_ data: Data) -> BolusSpeedSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }
    return BolusSpeedSettingResponse(
        speed: DiaconnPacketDecoder.readByte(payload, offset: 0),
        token: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - OTP 확인 (msgType: 0x2A) — 2단계 커밋

/// 설정 명령 확인 (OTP 번호로 커밋)
/// 모든 설정 명령(볼루스, 임시기저, 기저프로파일 등)은 응답에서 otpNumber를 받고,
/// 이 패킷으로 확인해야 실제 실행됨
/// - Parameters:
///   - reqMsgType: 원래 명령의 msgType
///   - otpNumber: 응답에서 받은 OTP 번호
func generateAppConfirmPacket(reqMsgType: UInt8, otpNumber: UInt32) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    payload.appendIntLE(otpNumber)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.APP_CONFIRM_SETTING,
        payload: payload
    )
}

/// 앱 취소 (msgType: 0x29) — OTP 커밋 거부
func generateAppCancelPacket(reqMsgType: UInt8, otpNumber: UInt32) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    payload.appendIntLE(otpNumber)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.APP_CANCEL_SETTING,
        payload: payload
    )
}
