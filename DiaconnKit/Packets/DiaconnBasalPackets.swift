import Foundation

// MARK: - Temp basal setting (msgType: 0x0A)

/// Generate temp basal setting command
/// - Parameters:
///   - status: 1=activate, 2=deactivate
///   - time: time code (2~96, 30min~1440min in 15min increments)
///   - injectRateRatio: absolute(1000~1600=0.00~6.00U) or percent(50000~50200=0~200%)
func generateTempBasalPacket(status: UInt8, time: UInt8, injectRateRatio: UInt16) -> Data {
    var payload = Data()
    payload.append(status)
    payload.append(time)
    payload.appendShortLE(injectRateRatio)
    payload.appendIntLE(946_652_400) // Fixed value: 2000-01-01 00:00:00 KST (AAPS: apsSecond)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.TEMP_BASAL_SETTING,
        payload: payload
    )
}

/// Temp basal setting - percent-based helper
/// - Parameters:
///   - percent: ratio (0~200%)
///   - durationMinutes: duration (minutes, in 30min increments)
func generateTempBasalPercentPacket(percent: Int, durationMinutes: Int) -> Data {
    let timeCode = UInt8(durationMinutes / 15)
    let rateRatio = UInt16(50000 + percent) // 50000=0%, 50100=100%, 50200=200%
    return generateTempBasalPacket(status: 1, time: timeCode, injectRateRatio: rateRatio)
}

/// Temp basal setting - absolute rate helper
/// - Parameters:
///   - unitsPerHour: U/h (0.00~6.00)
///   - durationMinutes: duration (minutes, in 30min increments)
///   - status: 1=new setting, 3=stealth change (seamless change while temp basal is already running)
func generateTempBasalAbsolutePacket(unitsPerHour: Double, durationMinutes: Int, status: UInt8 = 1) -> Data {
    let timeCode = UInt8(durationMinutes / 15)
    let rateRatio = UInt16(1000 + Int(unitsPerHour * 100)) // 1000=0.00U, 1600=6.00U
    return generateTempBasalPacket(status: status, time: timeCode, injectRateRatio: rateRatio)
}

/// Generate temp basal cancel command
func generateTempBasalCancelPacket() -> Data {
    generateTempBasalPacket(status: 2, time: 0, injectRateRatio: 0)
}

/// Parse temp basal response (msgType: 0x8A)
struct TempBasalSettingResponse {
    let result: UInt8
    let otpNumber: UInt32

    var isSuccess: Bool { result == 0 }
}

func parseTempBasalSettingResponse(_ data: Data) -> TempBasalSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return TempBasalSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - Basal pause/resume (msgType: 0x03)

/// Generate basal pause/resume command
/// - Parameter status: 1=pause(suspend), 2=resume(release)
func generateBasalPausePacket(status: UInt8) -> Data {
    var payload = Data()
    payload.append(status)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.BASAL_PAUSE_SETTING,
        payload: payload
    )
}

/// Suspend command
func generateSuspendPacket() -> Data {
    generateBasalPausePacket(status: 1)
}

/// Resume command
func generateResumePacket() -> Data {
    generateBasalPausePacket(status: 2)
}

/// Parse basal pause/resume response (msgType: 0x83)
struct BasalPauseSettingResponse {
    let result: UInt8
    let otpNumber: UInt32

    var isSuccess: Bool { result == 0 }
}

func parseBasalPauseSettingResponse(_ data: Data) -> BasalPauseSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BasalPauseSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - Basal profile setting (msgType: 0x0B)

/// Basal profile setting (24 hours = 4 groups x 6 hours)
/// - Parameters:
///   - pattern: profile number (1~6: basic, life1, life2, life3, dr1, dr2)
///   - group: group number (1=00-05h, 2=06-11h, 3=12-17h, 4=18-23h)
///   - amounts: 6 hourly basal amounts for the group (U/h)
///   - isLastGroup: whether this is the last group (true when group is 4)
func generateBasalSettingPacket(pattern: UInt8, group: UInt8, amounts: [Double], isLastGroup: Bool) -> Data {
    var payload = Data()
    payload.append(pattern)
    payload.append(group)

    for i in 0 ..< 6 {
        let amount = i < amounts.count ? amounts[i] : 0.0
        payload.appendShortLE(UInt16(amount * 100))
    }

    let msgConEnd = isLastGroup ? DiaconnPacketType.MSG_CON_END : DiaconnPacketType.MSG_CON_CONTINUE

    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.BASAL_SETTING,
        msgConEnd: msgConEnd,
        payload: payload
    )
}

/// Split 24-hour basal profile into 4 packets
/// - Parameters:
///   - pattern: profile number (1~6)
///   - hourlyRates: array of 24 hourly basal rates (U/h)
/// - Returns: array of 4 packets
func generateFullBasalProfile(pattern: UInt8, hourlyRates: [Double]) -> [Data] {
    var packets: [Data] = []
    for group in 1 ... 4 {
        let startHour = (group - 1) * 6
        let endHour = min(startHour + 6, hourlyRates.count)
        let amounts = Array(hourlyRates[startHour ..< endHour])
        let packet = generateBasalSettingPacket(
            pattern: pattern,
            group: UInt8(group),
            amounts: amounts,
            isLastGroup: group == 4
        )
        packets.append(packet)
    }
    return packets
}

/// Parse basal profile response (msgType: 0x8B)
struct BasalSettingResponse {
    let result: UInt8
    let otpNumber: UInt32

    var isSuccess: Bool { result == 0 }
}

func parseBasalSettingResponse(_ data: Data) -> BasalSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return BasalSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}
