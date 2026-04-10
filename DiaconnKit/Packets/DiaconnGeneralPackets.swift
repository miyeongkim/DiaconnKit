import Foundation

// MARK: - APS full status inquiry (msgType: 0x54, response: 0x94, 182 bytes)

/// Generate APS full status inquiry packet
func generateBigAPSMainInfoInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.BIG_APS_MAIN_INFO_INQUIRE)
}

/// APS full status response data (182-byte big packet)
public struct DiaconnPumpStatus {
    // System status
    public var remainInsulin: Double = 0 // Remaining insulin (U)
    public var remainBattery: Int = 0 // Remaining battery (1~100%)
    public var basePattern: UInt8 = 0 // Current basal pattern (0~6)
    public var tbStatus: UInt8 = 0 // Temp basal status
    public var mealBolusStatus: UInt8 = 0 // Meal bolus status
    public var snackBolusStatus: UInt8 = 0 // Snack bolus status
    public var squareBolusStatus: UInt8 = 0 // Extended bolus status
    public var dualBolusStatus: UInt8 = 0 // Dual bolus status
    public var basePauseStatus: UInt8 = 0 // Basal pause status (1=paused, 2=released)

    // Pump time
    public var pumpYear: Int = 0
    public var pumpMonth: Int = 0
    public var pumpDay: Int = 0
    public var pumpHour: Int = 0
    public var pumpMinute: Int = 0
    public var pumpSecond: Int = 0

    // Pump info
    public var country: UInt8 = 0
    public var productType: UInt8 = 0
    public var makeYear: UInt8 = 0
    public var makeMonth: UInt8 = 0
    public var makeDay: UInt8 = 0
    public var lotNo: UInt8 = 0
    public var serialNo: UInt16 = 0
    public var majorVersion: UInt8 = 0
    public var minorVersion: UInt8 = 0

    // Log status
    public var lastLogNum: UInt16 = 0
    public var wrappingCount: UInt8 = 0

    // Bolus speed
    public var bolusSpeed: UInt8 = 0

    // Temp basal detail
    public var tempBasalStatus: UInt8 = 0
    public var tempBasalTime: UInt8 = 0
    public var tempBasalRateRatio: UInt16 = 0
    public var tempBasalElapsedTime: UInt16 = 0

    // Basal status
    public var basalStatus: UInt8 = 0
    public var basalHour: UInt8 = 0
    public var basalAmount: Double = 0 // Current hour basal amount (U/h)
    public var basalInjectedAmount: Double = 0 // Current hour injected amount

    // Snack bolus status
    public var snackStatus: UInt8 = 0
    public var snackAmount: Double = 0
    public var snackInjectedAmount: Double = 0
    public var snackSpeed: UInt8 = 0

    // Extended bolus status
    public var squareStatus: UInt8 = 0
    public var squareTime: UInt16 = 0 // Set duration (10~300 min)
    public var squareInjectedTime: UInt16 = 0
    public var squareAmount: Double = 0
    public var squareInjectedAmount: Double = 0

    // Dual bolus status
    public var dualStatus: UInt8 = 0
    public var dualAmount: Double = 0
    public var dualInjectedAmount: Double = 0
    public var dualSquareTime: UInt16 = 0
    public var dualInjectedSquareTime: UInt16 = 0
    public var dualSquareAmount: Double = 0
    public var dualInjectedSquareAmount: Double = 0

    // Recent injection history
    public var recentKind1: UInt8 = 0 // 1=meal, 2=snack, 3=extended, 4=dual
    public var recentTime1: UInt32 = 0
    public var recentAmount1: Double = 0
    public var recentKind2: UInt8 = 0
    public var recentTime2: UInt32 = 0
    public var recentAmount2: Double = 0

    // Today injection total
    public var todayBasalAmount: Double = 0
    public var todayMealAmount: Double = 0
    public var todaySnackAmount: Double = 0

    // Current basal profile info
    public var currentBasePattern: UInt8 = 0
    public var currentBaseHour: UInt8 = 0
    public var currentBaseTbBeforeAmount: Double = 0
    public var currentBaseTbAfterAmount: Double = 0

    // 24-hour basal profile (U/h)
    public var basalProfile: [Double] = Array(repeating: 0, count: 24)

    // Limit settings
    public var maxBasalPerHour: Double = 0
    public var maxBasal: Double = 0 // maxBasalPerHour * 2.5
    public var maxBolus: Double = 0
    public var maxBolusPerDay: Double = 0

    // Sound
    public var beepAndAlarm: UInt8 = 0
    public var alarmIntensity: UInt8 = 0

    // LCD
    public var lcdOnTimeSec: UInt8 = 0 // 1=30sec, 2=40sec, 3=50sec

    // Language
    public var selectedLanguage: UInt8 = 0 // 1=Chinese, 2=Korean, 3=English

    // basePauseStatus: 1=paused(suspended), 2=released(active)
    public var isSuspended: Bool { basePauseStatus == 1 }
    // tbStatus: 1=temp basal running, 2=temp basal off (0 or 2 means not running)
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

/// Parse APS full status response (182-byte big packet)
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

    // Check result (success=16)
    let result = readByte()
    guard Int(result) == DiaconnPacketType.InquireResult.success.rawValue else { return nil }

    // System status
    status.remainInsulin = Double(readShort()) / 100.0
    status.remainBattery = Int(readByte())
    status.basePattern = readByte()
    status.tbStatus = readByte()
    status.mealBolusStatus = readByte()
    status.snackBolusStatus = readByte()
    status.squareBolusStatus = readByte()
    status.dualBolusStatus = readByte()
    status.basePauseStatus = readByte()

    // Pump time
    status.pumpYear = Int(readByte()) + 2000
    status.pumpMonth = Int(readByte())
    status.pumpDay = Int(readByte())
    status.pumpHour = Int(readByte())
    status.pumpMinute = Int(readByte())
    status.pumpSecond = Int(readByte())

    // Pump info
    status.country = readByte()
    status.productType = readByte()
    status.makeYear = readByte()
    status.makeMonth = readByte()
    status.makeDay = readByte()
    status.lotNo = readByte()
    status.serialNo = readShort()
    status.majorVersion = readByte()
    status.minorVersion = readByte()

    // Log status
    status.lastLogNum = readShort()
    status.wrappingCount = readByte()

    // Bolus speed
    status.bolusSpeed = readByte()

    // Temp basal detail
    status.tempBasalStatus = readByte()
    status.tempBasalTime = readByte()
    status.tempBasalRateRatio = readShort()
    status.tempBasalElapsedTime = readShort()

    // Basal status
    status.basalStatus = readByte()
    status.basalHour = readByte()
    status.basalAmount = Double(readShort()) / 100.0
    status.basalInjectedAmount = Double(readShort()) / 100.0

    // Snack bolus status
    status.snackStatus = readByte()
    status.snackAmount = Double(readShort()) / 100.0
    status.snackInjectedAmount = Double(readShort()) / 100.0
    status.snackSpeed = readByte()

    // Extended bolus status
    status.squareStatus = readByte()
    status.squareTime = readShort()
    status.squareInjectedTime = readShort()
    status.squareAmount = Double(readShort()) / 100.0
    status.squareInjectedAmount = Double(readShort()) / 100.0

    // Dual bolus status
    status.dualStatus = readByte()
    status.dualAmount = Double(readShort()) / 100.0
    status.dualInjectedAmount = Double(readShort()) / 100.0
    status.dualSquareTime = readShort()
    status.dualInjectedSquareTime = readShort()
    status.dualSquareAmount = Double(readShort()) / 100.0
    status.dualInjectedSquareAmount = Double(readShort()) / 100.0

    // Recent injection history
    status.recentKind1 = readByte()
    status.recentTime1 = readInt()
    status.recentAmount1 = Double(readShort()) / 100.0
    status.recentKind2 = readByte()
    status.recentTime2 = readInt()
    status.recentAmount2 = Double(readShort()) / 100.0

    // Today injection total
    status.todayBasalAmount = Double(readShort()) / 100.0
    status.todayMealAmount = Double(readShort()) / 100.0
    status.todaySnackAmount = Double(readShort()) / 100.0

    // Current basal profile info
    status.currentBasePattern = readByte()
    status.currentBaseHour = readByte()
    status.currentBaseTbBeforeAmount = Double(readShort()) / 100.0
    status.currentBaseTbAfterAmount = Double(readShort()) / 100.0

    // 24-hour basal profile
    for i in 0 ..< 24 {
        status.basalProfile[i] = Double(readShort()) / 100.0
    }

    // Limit settings
    status.maxBasalPerHour = Double(readShort()) / 100.0
    status.maxBasal = status.maxBasalPerHour * 2.5

    _ = readByte() // mealLimitTime (unused)
    status.maxBolus = Double(readShort()) / 100.0
    status.maxBolusPerDay = Double(readShort()) / 100.0

    // Sound
    status.beepAndAlarm = readByte() - 1
    status.alarmIntensity = readByte() - 1

    // LCD
    status.lcdOnTimeSec = readByte()

    // Language
    status.selectedLanguage = readByte()

    return status
}

// MARK: - Sound setting (msgType: 0x11)

/// Sound (notification) setting
/// - Parameters:
///   - beepAndAlarm: 0=sound, 1=mute, 2=vibration (add +1 when sending to pump)
///   - alarmIntensity: alarm intensity (add +1 when sending to pump)
func generateSoundSettingPacket(beepAndAlarm: UInt8, alarmIntensity: UInt8) -> Data {
    var payload = Data()
    payload.append(beepAndAlarm + 1)
    payload.append(alarmIntensity + 1)
    return DiaconnPacketEncoder.encode(
        msgType: DiaconnPacketType.SOUND_SETTING,
        payload: payload
    )
}

/// Parse sound setting response (msgType: 0x91)
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

// MARK: - Time setting (msgType: 0x0F)

/// Set pump time
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

/// Parse time setting response (msgType: 0x8F)
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

// MARK: - Time inquiry (msgType: 0x4F)

func generateTimeInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.TIME_INQUIRE)
}

// MARK: - Serial number inquiry (msgType: 0x53)

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

// MARK: - Log status inquiry (msgType: 0x46)

func generateLogStatusInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.LOG_STATUS_INQUIRE)
}

// MARK: - Incarnation inquiry (msgType: 0x45)

func generateIncarnationInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.INCARNATION_INQUIRE)
}

// MARK: - Temp basal status inquiry (msgType: 0x4A)

func generateTempBasalInquirePacket() -> Data {
    DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.TEMP_BASAL_INQUIRE)
}

// MARK: - Log status inquiry (msgType: 0x56, response: 0x96)

/// Log status (lastLogNum, wrappingCount)
public struct DiaconnLogStatus {
    public var lastLogNum: UInt16 = 0
    public var wrappingCount: UInt8 = 0
}

/// Parse LogStatusInquire response: result(1) + lastLogNum(2 LE) + wrappingCount(1)
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

// MARK: - Big log inquiry (msgType: 0x72, response: 0xB2, 182 bytes)

/// Log event kinds (based on AndroidAPS PumpLogUtil.getKind — lower 6 bits of typeAndKind byte)
public enum DiaconnLogKind: UInt8 {
    case resetSys = 0x01 // System reset (battery replacement, etc.)
    case suspend = 0x03 // Suspend start
    case suspendRelease = 0x04 // Suspend release
    case mealBolusSuccess = 0x08 // Meal bolus success
    case mealBolusFail = 0x09 // Meal bolus fail
    case normalBolusSuccess = 0x0A // Normal bolus success
    case normalBolusFail = 0x0B // Normal bolus fail
    case squareBolusSet = 0x0C // Square bolus set
    case squareBolusSuccess = 0x0D // Square bolus success
    case squareBolusFail = 0x0E // Square bolus fail
    case dualBolusSet = 0x0F // Dual bolus set
    case dualBolusSuccess = 0x10 // Dual bolus success
    case dualBolusFail = 0x11 // Dual bolus fail
    case tbStart = 0x12 // Temp basal start
    case tbStop = 0x13 // Temp basal stop
    case changeTube = 0x18 // Tube change (priming)
    case changeInjector = 0x1A // Injector change (insulin replacement)
    case changeNeedle = 0x1C // Needle change (cannula replacement)
    case alarmBattery = 0x28 // Low battery alarm
    case alarmBlock = 0x29 // Injection blockage alarm
    case alarmShortAge = 0x2A // Low insulin alarm
    case hourBasal = 0x2C // Hourly basal injection amount
    case dualNormal = 0x35 // Dual (normal) injection amount
    case unknown = 0xFF
}

/// Single log entry (based on AndroidAPS BigLogInquireResponsePacket structure)
public struct DiaconnLogEntry {
    public var logNum: UInt16
    public var wrapCount: UInt8
    public var logKind: DiaconnLogKind
    /// logData[0-3]: 4-byte LE Unix timestamp (UTC)
    public var date: Date
    /// Actual injected amount (U) — injectAmount / 100
    public var injectAmount: Double
    /// Set amount (U) — setAmount / 100
    public var setAmount: Double
    /// Temp basal rate/ratio raw value (getTbInjectRateRatio)
    /// - <  50000: absolute mode -> (value - 1000) / 100.0 U/h
    /// - >= 50000: percent mode -> (value - 50000) % of basal amount
    public var tbRateRatio: UInt16
    /// Temp basal time unit (1 unit = 15 min)
    public var tbTime: Int
    /// Square/dual bolus injection time unit (1 unit = 10 min), meal/normal is direct minutes
    public var injectTimeUnit: Int
}

/// Generate BIG_LOG_INQUIRE request packet
/// payload: start(2 LE) + end(2 LE) + delay(1)
func generateBigLogInquirePacket(start: UInt16, end: UInt16, delay: UInt8 = 100) -> Data {
    var payload = Data()
    payload.appendShortLE(start)
    payload.appendShortLE(end)
    payload.append(delay)
    return DiaconnPacketEncoder.encode(msgType: DiaconnPacketType.BIG_LOG_INQUIRE, payload: payload)
}

/// Parse BIG_LOG_INQUIRE_RESPONSE (0xB2, 182 bytes)
/// Payload structure (based on AndroidAPS BigLogInquireResponsePacket):
///   [0]   result (1 byte, 16=success)
///   [1]   logLength (1 byte, number of log entries)
///   [2..] repeated log entries (15 bytes each):
///     +0  wrapCount  (1)
///     +1  logNum     (2, LE)
///     +3  logData    (12): [0-3]=LE Unix timestamp, [4]=type(2b)+kind(6b), [5-11]=per-log fields
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
    // Pump stores local time as Unix timestamp — subtract timezone offset once
    let tzOffset = TimeInterval(TimeZone.current.secondsFromGMT())

    for i in 0 ..< logLength {
        let base = dataStart + i * entrySize
        guard base + entrySize <= payload.count else { break }

        let wrapCount = payload[base]
        let logNum = DiaconnPacketDecoder.readShort(payload, offset: base + 1)

        let d = base + 3

        let tsRaw = UInt32(payload[d])
            | (UInt32(payload[d + 1]) << 8)
            | (UInt32(payload[d + 2]) << 16)
            | (UInt32(payload[d + 3]) << 24)
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw) - tzOffset)

        // [4]: type(upper 2 bits) + kind(lower 6 bits)
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
            // tbTime: 1 unit = 15 min, tbRateRatio: absolute or percent encoding
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
