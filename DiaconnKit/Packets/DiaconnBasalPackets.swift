import Foundation

// MARK: - 임시 기저 설정 (msgType: 0x0A)

/// 임시 기저 설정 명령 생성
/// - Parameters:
///   - status: 1=실행, 2=해제
///   - time: 시간 코드 (2~96, 30분~1440분을 15분 단위로)
///   - injectRateRatio: 절대량(1000~1600=0.00~6.00U) 또는 퍼센트(50000~50200=0~200%)
func generateTempBasalPacket(status: UInt8, time: UInt8, injectRateRatio: UInt16) -> Data {
    var payload = Data()
    payload.append(status)
    payload.append(time)
    payload.appendShortLE(injectRateRatio)
    payload.appendIntLE(946_652_400) // 고정값: 2000-01-01 00:00:00 KST (AAPS: apsSecond)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.TEMP_BASAL_SETTING,
        payload: payload
    )
}

/// 임시 기저 설정 - 퍼센트 기반 헬퍼
/// - Parameters:
///   - percent: 비율 (0~200%)
///   - durationMinutes: 지속 시간 (분, 30분 단위)
func generateTempBasalPercentPacket(percent: Int, durationMinutes: Int) -> Data {
    let timeCode = UInt8(durationMinutes / 15)
    let rateRatio = UInt16(50000 + percent) // 50000=0%, 50100=100%, 50200=200%
    return generateTempBasalPacket(status: 1, time: timeCode, injectRateRatio: rateRatio)
}

/// 임시 기저 설정 - 절대량 기반 헬퍼
/// - Parameters:
///   - unitsPerHour: U/h (0.00~6.00)
///   - durationMinutes: 지속 시간 (분, 30분 단위)
///   - status: 1=신규 설정, 3=스텔스 변경 (이미 임시기저 실행 중일 때 끊김 없이 변경)
func generateTempBasalAbsolutePacket(unitsPerHour: Double, durationMinutes: Int, status: UInt8 = 1) -> Data {
    let timeCode = UInt8(durationMinutes / 15)
    let rateRatio = UInt16(1000 + Int(unitsPerHour * 100)) // 1000=0.00U, 1600=6.00U
    return generateTempBasalPacket(status: status, time: timeCode, injectRateRatio: rateRatio)
}

/// 임시 기저 해제 명령 생성
func generateTempBasalCancelPacket() -> Data {
    generateTempBasalPacket(status: 2, time: 0, injectRateRatio: 0)
}

/// 임시 기저 응답 파싱 (msgType: 0x8A)
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

// MARK: - 기저 정지/재개 (msgType: 0x03)

/// 기저 정지/재개 명령 생성
/// - Parameter status: 1=정지(서스펜드), 2=재개(해제)
func generateBasalPausePacket(status: UInt8) -> Data {
    var payload = Data()
    payload.append(status)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.BASAL_PAUSE_SETTING,
        payload: payload
    )
}

/// 서스펜드 명령
func generateSuspendPacket() -> Data {
    generateBasalPausePacket(status: 1)
}

/// 서스펜드 해제 명령
func generateResumePacket() -> Data {
    generateBasalPausePacket(status: 2)
}

/// 기저 정지/재개 응답 파싱 (msgType: 0x83)
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

// MARK: - 기저 프로파일 설정 (msgType: 0x0B)

/// 기저 프로파일 설정 (24시간 = 4그룹 × 6시간)
/// - Parameters:
///   - pattern: 프로파일 번호 (1~6: basic, life1, life2, life3, dr1, dr2)
///   - group: 그룹 번호 (1=00-05시, 2=06-11시, 3=12-17시, 4=18-23시)
///   - amounts: 해당 그룹의 6개 시간별 기저량 (U/h)
///   - isLastGroup: 마지막 그룹 여부 (group 4일 때 true)
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

/// 24시간 기저 프로파일을 4개 패킷으로 분할 생성
/// - Parameters:
///   - pattern: 프로파일 번호 (1~6)
///   - hourlyRates: 24개 시간별 기저량 배열 (U/h)
/// - Returns: 4개의 패킷 배열
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

/// 기저 프로파일 응답 파싱 (msgType: 0x8B)
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
