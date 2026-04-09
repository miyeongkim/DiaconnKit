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

// MARK: - 로그 상태 조회 (msgType: 0x56, 응답: 0x96)

/// 로그 상태 (lastLogNum, wrappingCount)
public struct DiaconnLogStatus {
    public var lastLogNum: UInt16 = 0
    public var wrappingCount: UInt8 = 0
}

/// LogStatusInquire 응답 파싱: result(1) + lastLogNum(2 LE) + wrappingCount(1)
public func parseLogStatusResponse(_ data: Data) -> DiaconnLogStatus? {
    guard DiaconnPacketDecoder.validatePacket(data) == 0 else { return nil }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 4 else { return nil }

    let result = payload[0]
    guard Int(result) == DiaconnPacketType.InquireResult.success.rawValue else { return nil }

    var status = DiaconnLogStatus()
    status.lastLogNum = DiaconnPacketDecoder.readShort(payload, offset: 1)
    status.wrappingCount = payload[3]
    return status
}

// MARK: - 대량 로그 조회 (msgType: 0x72, 응답: 0xB2, 182바이트)

/// 로그 이벤트 종류 (AndroidAPS PumpLogUtil.getKind 기준 — typeAndKind 바이트의 하위 6비트)
public enum DiaconnLogKind: UInt8 {
    case resetSys = 0x01 // 시스템 리셋 (배터리 교체 등)
    case suspend = 0x03 // 일시정지 시작
    case suspendRelease = 0x04 // 일시정지 해제
    case mealBolusSuccess = 0x08 // 식사주입 성공
    case mealBolusFail = 0x09 // 식사주입 실패
    case normalBolusSuccess = 0x0A // 일반주입 성공
    case normalBolusFail = 0x0B // 일반주입 실패
    case squareBolusSet = 0x0C // 스퀘어주입 설정
    case squareBolusSuccess = 0x0D // 스퀘어주입 성공
    case squareBolusFail = 0x0E // 스퀘어주입 실패
    case dualBolusSet = 0x0F // 듀얼주입 설정
    case dualBolusSuccess = 0x10 // 듀얼주입 성공
    case dualBolusFail = 0x11 // 듀얼주입 실패
    case tbStart = 0x12 // 임시기저 시작
    case tbStop = 0x13 // 임시기저 중지
    case changeTube = 0x18 // 튜브 교체 (프라이밍)
    case changeInjector = 0x1A // 주사기 교체 (인슐린 교체)
    case changeNeedle = 0x1C // 바늘 교체 (캐뉼라 교체)
    case alarmBattery = 0x28 // 배터리 부족 알람
    case alarmBlock = 0x29 // 주입 막힘 알람
    case alarmShortAge = 0x2A // 인슐린 부족 알람
    case hourBasal = 0x2C // 1시간 기저 주입량
    case dualNormal = 0x35 // 듀얼(일반) 주입량
    case unknown = 0xFF
}

/// 로그 항목 하나 (AndroidAPS BigLogInquireResponsePacket 구조 기준)
public struct DiaconnLogEntry {
    public var logNum: UInt16
    public var wrapCount: UInt8
    public var logKind: DiaconnLogKind
    /// logData[0-3]: 4바이트 LE Unix timestamp (UTC)
    public var date: Date
    /// 실제 주입량 (U) — injectAmount / 100
    public var injectAmount: Double
    /// 설정 주입량 (U) — setAmount / 100
    public var setAmount: Double
    /// 임시기저 rate/ratio 원시값 (getTbInjectRateRatio)
    /// - <  50000: 절대값 모드 → (값 - 1000) / 100.0 U/h
    /// - >= 50000: 퍼센트 모드 → (값 - 50000) % of 기저량
    public var tbRateRatio: UInt16
    /// 임시기저 시간 단위 (1단위 = 15분)
    public var tbTime: Int
    /// 스퀘어/듀얼 볼루스 주입시간 단위 (1단위 = 10분), 식사/일반은 직접 분
    public var injectTimeUnit: Int
}

/// BIG_LOG_INQUIRE 요청 패킷 생성
/// payload: start(2 LE) + end(2 LE) + delay(1)
func generateBigLogInquirePacket(start: UInt16, end: UInt16, delay: UInt8 = 100) -> Data {
    var payload = Data()
    payload.appendShortLE(start)
    payload.appendShortLE(end)
    payload.append(delay)
    return DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.BIG_LOG_INQUIRE, payload: payload)
}

/// BIG_LOG_INQUIRE_RESPONSE (0xB2, 182바이트) 파싱
/// payload 구조 (AndroidAPS BigLogInquireResponsePacket 기준):
///   [0]   result (1바이트, 16=success)
///   [1]   logLength (1바이트, 로그 갯수)
///   [2..] 로그 항목 반복 (항목당 15바이트):
///     +0  wrapCount  (1)
///     +1  logNum     (2, LE)
///     +3  logData    (12): [0-3]=LE Unix timestamp, [4]=type(2b)+kind(6b), [5-11]=로그별 필드
public func parseBigLogInquireResponse(_ data: Data) -> [DiaconnLogEntry]? {
    let validationResult = DiaconnPacketDecoder.validatePacket(data)
    guard validationResult == 0 else {
        NSLog(
            "[DiaconnKit] parseBigLogInquireResponse: validatePacket failed defect=\(validationResult) dataLen=\(data.count) sop=\(data.isEmpty ? 0 : data[0])"
        )
        return nil
    }
    let payload = DiaconnPacketDecoder.getPayload(data)
    guard payload.count >= 2 else {
        NSLog("[DiaconnKit] parseBigLogInquireResponse: payload too short (\(payload.count))")
        return nil
    }

    let result = payload[0]
    guard Int(result) == DiaconnPacketType.InquireResult.success.rawValue else {
        NSLog(
            "[DiaconnKit] parseBigLogInquireResponse: result=\(result) expected=\(DiaconnPacketType.InquireResult.success.rawValue)"
        )
        return nil
    }

    let logLength = Int(payload[1])
    guard logLength > 0 else { return [] }

    let entrySize = 15
    let dataStart = 2
    var entries: [DiaconnLogEntry] = []

    for i in 0 ..< logLength {
        let base = dataStart + i * entrySize
        guard base + entrySize <= payload.count else { break }

        let wrapCount = payload[base]
        let logNum = DiaconnPacketDecoder.readShort(payload, offset: base + 1)

        let d = base + 3

        // [0-3]: 4바이트 LE timestamp (펌프 로컬 시간 기준 epoch)
        let tsRaw = UInt32(payload[d])
            | (UInt32(payload[d + 1]) << 8)
            | (UInt32(payload[d + 2]) << 16)
            | (UInt32(payload[d + 3]) << 24)
        // 펌프는 로컬 시간으로 timestamp를 저장 → timezone offset을 빼서 UTC로 변환
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw) - TimeInterval(TimeZone.current.secondsFromGMT()))

        // [4]: type(상위2비트) + kind(하위6비트)
        let rawKind = payload[d + 4] & 0x3F
        let kind = DiaconnLogKind(rawValue: rawKind) ?? .unknown

        var injectAmount: Double = 0
        var setAmount: Double = 0
        var tbRateRatio: UInt16 = 0
        var tbTime: Int = 0
        var injectTimeUnit: Int = 0

        switch kind {
        case .mealBolusFail,
             .mealBolusSuccess,
             .normalBolusFail,
             .normalBolusSuccess:
            setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            injectAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 7)) / 100.0
            injectTimeUnit = Int(payload[d + 9])

        case .squareBolusSet:
            setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            injectAmount = setAmount
            injectTimeUnit = Int(payload[d + 7])

        case .squareBolusFail,
             .squareBolusSuccess:
            injectAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            injectTimeUnit = Int(payload[d + 7])

        case .dualBolusSet:
            injectAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 7)) / 100.0
            injectTimeUnit = Int(payload[d + 9])

        case .dualNormal:
            setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            injectAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 7)) / 100.0
            injectTimeUnit = Int(payload[d + 9])

        case .dualBolusFail,
             .dualBolusSuccess:
            injectAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 5)) / 100.0
            setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: d + 7)) / 100.0
            injectTimeUnit = Int(payload[d + 9])

        case .tbStart:
            // tbTime: 1단위=15분, tbRateRatio: 절대값 or 퍼센트 인코딩
            tbTime = Int(payload[d + 5])
            tbRateRatio = DiaconnPacketDecoder.readShort(payload, offset: d + 6)

        case .tbStop:
            tbRateRatio = DiaconnPacketDecoder.readShort(payload, offset: d + 5)

        case .alarmBattery,
             .alarmBlock,
             .alarmShortAge,
             .changeInjector,
             .changeNeedle,
             .changeTube,
             .hourBasal,
             .resetSys,
             .suspend,
             .suspendRelease:
            break

        default:
            continue
        }

        let entry = DiaconnLogEntry(
            logNum: logNum,
            wrapCount: wrapCount,
            logKind: kind,
            date: date,
            injectAmount: injectAmount,
            setAmount: setAmount,
            tbRateRatio: tbRateRatio,
            tbTime: tbTime,
            injectTimeUnit: injectTimeUnit
        )
        NSLog(
            "[DiaconnKit] LOG #\(logNum)(wrap=\(wrapCount)) kind=\(kind)(0x\(String(format: "%02X", rawKind))) date=\(date) injectAmount=\(injectAmount) setAmount=\(setAmount) tbRateRatio=\(tbRateRatio) tbTime=\(tbTime) injectTimeUnit=\(injectTimeUnit)"
        )
        entries.append(entry)
    }

    NSLog("[DiaconnKit] parseBigLogInquireResponse: parsed \(entries.count)/\(logLength) entries")
    return entries
}
