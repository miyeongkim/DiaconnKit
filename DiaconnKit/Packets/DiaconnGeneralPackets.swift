import Foundation

// MARK: - APS 전체 상태 조회 (msgType: 0x54, 응답: 0x94, 182바이트)

/// APS 전체 상태 조회 패킷 생성
func generateBigAPSMainInfoInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.BIG_APS_MAIN_INFO_INQUIRE)
}

/// APS 전체 상태 응답 데이터 (182바이트 대량 패킷)
public struct DiaconnPumpStatus {
    // 시스템 상태
    public var remainInsulin: Double = 0 // 잔여 인슐린 (U)
    public var remainBattery: Int = 0 // 잔여 배터리 (1~100%)
    public var basePattern: UInt8 = 0 // 현재 기저 패턴 (0~6)
    public var tbStatus: UInt8 = 0 // 임시 기저 상태
    public var mealBolusStatus: UInt8 = 0 // 식사 볼루스 상태
    public var snackBolusStatus: UInt8 = 0 // 간식 볼루스 상태
    public var squareBolusStatus: UInt8 = 0 // 확장 볼루스 상태
    public var dualBolusStatus: UInt8 = 0 // 듀얼 볼루스 상태
    public var basePauseStatus: UInt8 = 0 // 기저 정지 상태 (1=정지, 2=해제)

    // 펌프 시간
    public var pumpYear: Int = 0
    public var pumpMonth: Int = 0
    public var pumpDay: Int = 0
    public var pumpHour: Int = 0
    public var pumpMinute: Int = 0
    public var pumpSecond: Int = 0

    // 펌프 정보
    public var country: UInt8 = 0
    public var productType: UInt8 = 0
    public var makeYear: UInt8 = 0
    public var makeMonth: UInt8 = 0
    public var makeDay: UInt8 = 0
    public var lotNo: UInt8 = 0
    public var serialNo: UInt16 = 0
    public var majorVersion: UInt8 = 0
    public var minorVersion: UInt8 = 0

    // 로그 상태
    public var lastLogNum: UInt16 = 0
    public var wrappingCount: UInt8 = 0

    // 볼루스 속도
    public var bolusSpeed: UInt8 = 0

    // 임시 기저 상세
    public var tempBasalStatus: UInt8 = 0
    public var tempBasalTime: UInt8 = 0
    public var tempBasalRateRatio: UInt16 = 0
    public var tempBasalElapsedTime: UInt16 = 0

    // 기저 상태
    public var basalStatus: UInt8 = 0
    public var basalHour: UInt8 = 0
    public var basalAmount: Double = 0 // 현재 시간 기저량 (U/h)
    public var basalInjectedAmount: Double = 0 // 현재 시간 주입량

    // 간식 볼루스 상태
    public var snackStatus: UInt8 = 0
    public var snackAmount: Double = 0
    public var snackInjectedAmount: Double = 0
    public var snackSpeed: UInt8 = 0

    // 확장 볼루스 상태
    public var squareStatus: UInt8 = 0
    public var squareTime: UInt16 = 0 // 설정 시간 (10~300분)
    public var squareInjectedTime: UInt16 = 0
    public var squareAmount: Double = 0
    public var squareInjectedAmount: Double = 0

    // 듀얼 볼루스 상태
    public var dualStatus: UInt8 = 0
    public var dualAmount: Double = 0
    public var dualInjectedAmount: Double = 0
    public var dualSquareTime: UInt16 = 0
    public var dualInjectedSquareTime: UInt16 = 0
    public var dualSquareAmount: Double = 0
    public var dualInjectedSquareAmount: Double = 0

    // 최근 주입 이력
    public var recentKind1: UInt8 = 0 // 1=식사, 2=간식, 3=확장, 4=듀얼
    public var recentTime1: UInt32 = 0
    public var recentAmount1: Double = 0
    public var recentKind2: UInt8 = 0
    public var recentTime2: UInt32 = 0
    public var recentAmount2: Double = 0

    // 오늘 주입 합계
    public var todayBasalAmount: Double = 0
    public var todayMealAmount: Double = 0
    public var todaySnackAmount: Double = 0

    // 현재 기저 프로파일 정보
    public var currentBasePattern: UInt8 = 0
    public var currentBaseHour: UInt8 = 0
    public var currentBaseTbBeforeAmount: Double = 0
    public var currentBaseTbAfterAmount: Double = 0

    // 24시간 기저 프로파일 (U/h)
    public var basalProfile: [Double] = Array(repeating: 0, count: 24)

    // 한도 설정
    public var maxBasalPerHour: Double = 0
    public var maxBasal: Double = 0 // maxBasalPerHour * 2.5
    public var maxBolus: Double = 0
    public var maxBolusPerDay: Double = 0

    // 사운드
    public var beepAndAlarm: UInt8 = 0
    public var alarmIntensity: UInt8 = 0

    // LCD
    public var lcdOnTimeSec: UInt8 = 0 // 1=30초, 2=40초, 3=50초

    // 언어
    public var selectedLanguage: UInt8 = 0 // 1=중국어, 2=한국어, 3=영어

    // basePauseStatus: 1=정지(서스펜드), 2=해제(동작중)
    public var isSuspended: Bool { basePauseStatus == 1 }
    // tbStatus: 1=임시기저 중, 2=임시기저 해제 (0 또는 2면 실행 안 함)
    public var isTempBasalRunning: Bool { tbStatus == 1 }

    public var firmwareVersion: String {
        "\(majorVersion).\(minorVersion)"
    }

    public var serialNumber: String {
        let countryChar = Character(UnicodeScalar(country))
        let typeChar = Character(UnicodeScalar(productType))
        return "\(countryChar)\(typeChar)\(makeYear)\(makeMonth)\(makeDay)\(lotNo)\(serialNo)"
    }
}

/// APS 전체 상태 응답 파싱 (182바이트 대량 패킷)
func parseBigAPSMainInfoResponse(_ data: Data) -> DiaconnPumpStatus? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)

    var status = DiaconnPumpStatus()
    var offset = 0

    func readByte() -> UInt8 {
        let v = DiaconnPacketDecoder.readByte(payload, offset: offset)
        offset += 1
        return v
    }

    func readShort() -> UInt16 {
        let v = DiaconnPacketDecoder.readShort(payload, offset: offset)
        offset += 2
        return v
    }

    func readInt() -> UInt32 {
        let v = DiaconnPacketDecoder.readInt(payload, offset: offset)
        offset += 4
        return v
    }

    // 결과 확인 (성공=16)
    let result = readByte()
    guard Int(result) == DiaconnPacketType.InquireResult.success.rawValue else { return nil }

    // 시스템 상태
    status.remainInsulin = Double(readShort()) / 100.0
    status.remainBattery = Int(readByte())
    status.basePattern = readByte()
    status.tbStatus = readByte()
    status.mealBolusStatus = readByte()
    status.snackBolusStatus = readByte()
    status.squareBolusStatus = readByte()
    status.dualBolusStatus = readByte()
    status.basePauseStatus = readByte()

    // 펌프 시간
    status.pumpYear = Int(readByte()) + 2000
    status.pumpMonth = Int(readByte())
    status.pumpDay = Int(readByte())
    status.pumpHour = Int(readByte())
    status.pumpMinute = Int(readByte())
    status.pumpSecond = Int(readByte())

    // 펌프 정보
    status.country = readByte()
    status.productType = readByte()
    status.makeYear = readByte()
    status.makeMonth = readByte()
    status.makeDay = readByte()
    status.lotNo = readByte()
    status.serialNo = readShort()
    status.majorVersion = readByte()
    status.minorVersion = readByte()

    // 로그 상태
    status.lastLogNum = readShort()
    status.wrappingCount = readByte()

    // 볼루스 속도
    status.bolusSpeed = readByte()

    // 임시 기저 상세
    status.tempBasalStatus = readByte()
    status.tempBasalTime = readByte()
    status.tempBasalRateRatio = readShort()
    status.tempBasalElapsedTime = readShort()

    // 기저 상태
    status.basalStatus = readByte()
    status.basalHour = readByte()
    status.basalAmount = Double(readShort()) / 100.0
    status.basalInjectedAmount = Double(readShort()) / 100.0

    // 간식 볼루스 상태
    status.snackStatus = readByte()
    status.snackAmount = Double(readShort()) / 100.0
    status.snackInjectedAmount = Double(readShort()) / 100.0
    status.snackSpeed = readByte()

    // 확장 볼루스 상태
    status.squareStatus = readByte()
    status.squareTime = readShort()
    status.squareInjectedTime = readShort()
    status.squareAmount = Double(readShort()) / 100.0
    status.squareInjectedAmount = Double(readShort()) / 100.0

    // 듀얼 볼루스 상태
    status.dualStatus = readByte()
    status.dualAmount = Double(readShort()) / 100.0
    status.dualInjectedAmount = Double(readShort()) / 100.0
    status.dualSquareTime = readShort()
    status.dualInjectedSquareTime = readShort()
    status.dualSquareAmount = Double(readShort()) / 100.0
    status.dualInjectedSquareAmount = Double(readShort()) / 100.0

    // 최근 주입 이력
    status.recentKind1 = readByte()
    status.recentTime1 = readInt()
    status.recentAmount1 = Double(readShort()) / 100.0
    status.recentKind2 = readByte()
    status.recentTime2 = readInt()
    status.recentAmount2 = Double(readShort()) / 100.0

    // 오늘 주입 합계
    status.todayBasalAmount = Double(readShort()) / 100.0
    status.todayMealAmount = Double(readShort()) / 100.0
    status.todaySnackAmount = Double(readShort()) / 100.0

    // 현재 기저 프로파일 정보
    status.currentBasePattern = readByte()
    status.currentBaseHour = readByte()
    status.currentBaseTbBeforeAmount = Double(readShort()) / 100.0
    status.currentBaseTbAfterAmount = Double(readShort()) / 100.0

    // 24시간 기저 프로파일
    for i in 0 ..< 24 {
        status.basalProfile[i] = Double(readShort()) / 100.0
    }

    // 한도 설정
    status.maxBasalPerHour = Double(readShort()) / 100.0
    status.maxBasal = status.maxBasalPerHour * 2.5

    _ = readByte() // mealLimitTime (사용하지 않음)
    status.maxBolus = Double(readShort()) / 100.0
    status.maxBolusPerDay = Double(readShort()) / 100.0

    // 사운드
    status.beepAndAlarm = readByte() - 1
    status.alarmIntensity = readByte() - 1

    // LCD
    status.lcdOnTimeSec = readByte()

    // 언어
    status.selectedLanguage = readByte()

    return status
}

// MARK: - 사운드 설정 (msgType: 0x11)

/// 사운드(알림) 설정
/// - Parameters:
///   - beepAndAlarm: 0=소리, 1=무음, 2=진동 (펌프 전송 시 +1)
///   - alarmIntensity: 알람 강도 (펌프 전송 시 +1)
func generateSoundSettingPacket(beepAndAlarm: UInt8, alarmIntensity: UInt8) -> Data {
    var payload = Data()
    payload.append(beepAndAlarm + 1)
    payload.append(alarmIntensity + 1)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.SOUND_SETTING,
        payload: payload
    )
}

/// 사운드 설정 응답 파싱 (msgType: 0x91)
struct SoundSettingResponse {
    let result: UInt8
    let otpNumber: UInt32
    var isSuccess: Bool { result == 0 }
}

func parseSoundSettingResponse(_ data: Data) -> SoundSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }
    return SoundSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - 시간 설정 (msgType: 0x0F)

/// 펌프 시간 설정
func generateTimeSettingPacket(date: Date) -> Data {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(in: TimeZone.current, from: date)

    var payload = Data()
    payload.append(UInt8((components.year ?? 2024) - 2000))
    payload.append(UInt8(components.month ?? 1))
    payload.append(UInt8(components.day ?? 1))
    payload.append(UInt8(components.hour ?? 0))
    payload.append(UInt8(components.minute ?? 0))
    payload.append(UInt8(components.second ?? 0))

    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.TIME_SETTING,
        payload: payload
    )
}

/// 시간 설정 응답 파싱 (msgType: 0x8F)
struct TimeSettingResponse {
    let result: UInt8
    let otpNumber: UInt32

    var isSuccess: Bool { result == 0 }
}

func parseTimeSettingResponse(_ data: Data) -> TimeSettingResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 5 else { return nil }

    return TimeSettingResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        otpNumber: DiaconnPacketDecoder.readInt(payload, offset: 1)
    )
}

// MARK: - 시간 조회 (msgType: 0x4F)

func generateTimeInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.TIME_INQUIRE)
}

// MARK: - 시리얼 번호 조회 (msgType: 0x53)

func generateSerialNumInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.SERIAL_NUM_INQUIRE)
}

struct SerialNumInquireResponse {
    let result: UInt8
    let country: UInt8
    let productType: UInt8
    let makeYear: UInt8
    let makeMonth: UInt8
    let makeDay: UInt8
    let lotNo: UInt8
    let serialNo: UInt16
    let majorVersion: UInt8
    let minorVersion: UInt8

    var isSuccess: Bool { result == 16 }

    var serialNumber: String {
        let c = Character(UnicodeScalar(country))
        let t = Character(UnicodeScalar(productType))
        return "\(c)\(t)\(makeYear)\(makeMonth)\(makeDay)\(lotNo)\(serialNo)"
    }

    var firmwareVersion: String {
        "\(majorVersion).\(minorVersion)"
    }
}

func parseSerialNumInquireResponse(_ data: Data) -> SerialNumInquireResponse? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 11 else { return nil }

    return SerialNumInquireResponse(
        result: DiaconnPacketDecoder.readByte(payload, offset: 0),
        country: DiaconnPacketDecoder.readByte(payload, offset: 1),
        productType: DiaconnPacketDecoder.readByte(payload, offset: 2),
        makeYear: DiaconnPacketDecoder.readByte(payload, offset: 3),
        makeMonth: DiaconnPacketDecoder.readByte(payload, offset: 4),
        makeDay: DiaconnPacketDecoder.readByte(payload, offset: 5),
        lotNo: DiaconnPacketDecoder.readByte(payload, offset: 6),
        serialNo: DiaconnPacketDecoder.readShort(payload, offset: 7),
        majorVersion: DiaconnPacketDecoder.readByte(payload, offset: 9),
        minorVersion: DiaconnPacketDecoder.readByte(payload, offset: 10)
    )
}

// MARK: - 로그 상태 조회 (msgType: 0x46)

func generateLogStatusInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.LOG_STATUS_INQUIRE)
}

// MARK: - 인카네이션 조회 (msgType: 0x45)

func generateIncarnationInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.INCARNATION_INQUIRE)
}

// MARK: - 임시 기저 상태 조회 (msgType: 0x4A)

func generateTempBasalInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.TEMP_BASAL_INQUIRE)
}

// MARK: - 대량 로그 조회 (msgType: 0x72, 응답: 0xB2, 182바이트)

/// 로그 이벤트 종류
public enum DiaconnLogKind: UInt8 {
    case mealBolus = 0x01
    case snackBolus = 0x02
    case squareBolus = 0x03
    case dualBolus = 0x04
    case basalChange = 0x05
    case tempBasalStart = 0x06
    case tempBasalEnd = 0x07
    case suspend = 0x08
    case resume = 0x09
    case alarm = 0x0A
    case unknown = 0xFF
}

/// 로그 항목 하나
public struct DiaconnLogEntry {
    public var logNum: UInt16
    public var wrapCount: UInt8
    public var logKind: DiaconnLogKind
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int
    /// 볼루스량 또는 기저량 (U)
    public var amount: Double
    /// 임시 기저 비율 (%) 또는 속도
    public var rate: Double
    /// 지속 시간 (분)
    public var durationMin: Int

    public var date: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )) ?? Date()
    }
}

/// BIG_LOG_INQUIRE 요청 패킷 생성
/// - Parameters:
///   - wrapCount: 조회 시작 위치의 wrapping count
///   - logNum: 조회 시작 로그 번호
func generateBigLogInquirePacket(wrapCount: UInt8, logNum: UInt16) -> Data {
    var payload = Data()
    payload.append(wrapCount)
    payload.appendShortLE(logNum)
    return DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.BIG_LOG_INQUIRE, payload: payload)
}

/// BIG_LOG_INQUIRE_RESPONSE (0xB2, 182바이트) 파싱
/// 응답 payload 구조 (AndroidAPS DiaconnG8BigLogInquireResponsePacket 기준):
///   offset 0     : result (1바이트, 16=success)
///   offset 1+    : 로그 항목 반복 (항목당 15바이트)
///     +0  logKind   (1)
///     +1  year      (1, +2000)
///     +2  month     (1)
///     +3  day       (1)
///     +4  hour      (1)
///     +5  minute    (1)
///     +6  second    (1)
///     +7  logNum    (2, UInt16 LE)
///     +9  wrapCount (1)
///     +10 amount    (2, UInt16 LE, /100 → U)
///     +12 rate      (2, UInt16 LE, /100 → U/h 또는 %)
///     +14 duration  (1, 분)
public func parseBigLogInquireResponse(_ data: Data) -> [DiaconnLogEntry]? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard !payload.isEmpty else { return nil }

    let result = DiaconnPacketDecoder.readByte(payload, offset: 0)
    guard Int(result) == DiaconnPacketType.InquireResult.success.rawValue else { return nil }

    let entrySize = 15
    let dataStart = 1
    let entryCount = (payload.count - dataStart) / entrySize

    var entries: [DiaconnLogEntry] = []

    for i in 0 ..< entryCount {
        let base = dataStart + i * entrySize
        guard base + entrySize <= payload.count else { break }

        let rawKind = DiaconnPacketDecoder.readByte(payload, offset: base + 0)
        let kind = DiaconnLogKind(rawValue: rawKind) ?? .unknown

        // 패딩(0xFF)으로 채워진 항목은 skip
        if rawKind == 0xFF { break }

        let entry = DiaconnLogEntry(
            logNum: DiaconnPacketDecoder.readShort(payload, offset: base + 7),
            wrapCount: DiaconnPacketDecoder.readByte(payload, offset: base + 9),
            logKind: kind,
            year: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 1)) + 2000,
            month: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 2)),
            day: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 3)),
            hour: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 4)),
            minute: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 5)),
            second: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 6)),
            amount: Double(DiaconnPacketDecoder.readShort(payload, offset: base + 10)) / 100.0,
            rate: Double(DiaconnPacketDecoder.readShort(payload, offset: base + 12)) / 100.0,
            durationMin: Int(DiaconnPacketDecoder.readByte(payload, offset: base + 14))
        )
        entries.append(entry)
    }

    return entries
}
