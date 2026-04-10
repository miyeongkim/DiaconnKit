import Foundation

// MARK: - Snack bolus injection (msgType: 0x07)

/// Generate bolus injection command
/// - Parameter amount: insulin units (e.g. 2.5U → short value 250)
func generateBolusPacket(amount: Double) -> Data {
    var payload = Data()
    payload.appendShortLE(UInt16(amount * 100))
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_SNACK_SETTING,
        payload: payload
    )
}

/// Parse bolus response (msgType: 0x87)
struct BolusSettingResponse {
    let result: UInt8 // 0=success, other=error
    let otpNumber: UInt32 // OTP confirmation number

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

// MARK: - Extended bolus injection (msgType: 0x0C)

/// Generate extended bolus command
/// - Parameters:
///   - amount: insulin units
///   - durationMinutes: duration (minutes)
func generateExtendedBolusPacket(amount: Double, durationMinutes: UInt16) -> Data {
    var payload = Data()
    payload.appendShortLE(durationMinutes)
    payload.appendShortLE(UInt16(amount * 100))
    payload.appendIntLE(UInt32(946_652_400)) // Reference time (2000-01-01)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_EXTENDED_BOLUS_SETTING,
        payload: payload
    )
}

/// Parse extended bolus response (msgType: 0x8C)
func parseExtendedBolusSettingResponse(_ data: Data) -> BolusSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BolusSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - Injection cancel (msgType: 0x2B)

/// Generate injection cancel command
/// - Parameter reqMsgType: msgType of command to cancel (e.g. 0x07=bolus, 0x0C=extended bolus)
func generateInjectionCancelPacket(reqMsgType: UInt8) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.INJECTION_CANCEL_SETTING,
        payload: payload
    )
}

/// Parse injection cancel response (msgType: 0xAB)
func parseInjectionCancelResponse(_ data: Data) -> BolusSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BolusSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - Bolus speed setting (msgType: 0x0E)

/// Bolus speed setting (1~8)
func generateBolusSpeedPacket(speed: UInt8) -> Data {
    var payload = Data()
    payload.append(speed)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.BOLUS_SPEED_SETTING,
        payload: payload
    )
}

/// Bolus speed setting response (msgType: 0x85)
/// Response format: injection speed(1byte, 1~8) + one-time token(4bytes, 6-digit random)
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

// MARK: - OTP confirm (msgType: 0x2A) — two-step commit

/// Confirm setting command (commit with OTP number)
/// All setting commands (bolus, temp basal, basal profile, etc.) receive otpNumber in response,
/// and must be confirmed with this packet for actual execution
/// - Parameters:
///   - reqMsgType: msgType of the original command
///   - otpNumber: OTP number received from the response
func generateAppConfirmPacket(reqMsgType: UInt8, otpNumber: UInt32) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    payload.appendIntLE(otpNumber)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.APP_CONFIRM_SETTING,
        payload: payload
    )
}

/// App cancel (msgType: 0x29) — reject OTP commit
func generateAppCancelPacket(reqMsgType: UInt8, otpNumber: UInt32) -> Data {
    var payload = Data()
    payload.append(reqMsgType)
    payload.appendIntLE(otpNumber)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.APP_CANCEL_SETTING,
        payload: payload
    )
}
