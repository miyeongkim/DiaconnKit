import Foundation
public import LoopKit

internal enum DiaconnBasalState: Int {
    case active = 0
    case suspended = 1
    case tempBasal = 2
}

internal enum DiaconnBolusState: Int {
    case noBolus = 0
    case initiating = 1
    case inProgress = 2
    case canceling = 3
}

public struct DiaconnPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue

    // MARK: - Connection

    internal var deviceName: String?
    public internal(set) var bleIdentifier: String?
    internal var isConnected: Bool = false
    internal var isOnBoarded: Bool = false

    // MARK: - Pump Status

    internal var lastStatusDate: Date
    public internal(set) var reservoirLevel: Double = 0 // 잔여 인슐린 (U)
    public internal(set) var batteryRemaining: Double = 0 // 배터리 (0.0~1.0)

    // MARK: - Pump Info

    internal var firmwareVersion: String?
    internal var serialNumber: String?
    internal var majorVersion: UInt8 = 0
    internal var minorVersion: UInt8 = 0

    // MARK: - Delivery State

    internal var isPumpSuspended: Bool = false // basePauseStatus == 1
    internal var isTempBasalInProgress: Bool = false
    internal var bolusState: DiaconnBolusState = .noBolus
    internal var basalDeliveryDate: Date = .now
    internal var basalDeliveryOrdinal: DiaconnBasalState = .active

    // MARK: - Insulin Delivery

    internal var insulinType: InsulinType?
    internal var basalSchedule: [Double] // 24시간 기저 프로파일 (U/h)
    internal var basalPattern: UInt8 = 1 // 현재 기저 패턴 (1~6)
    internal var currentBasalRate: Double = 0 // 현재 시간 기저량

    // MARK: - Temp Basal

    internal var tempBasalUnits: Double? // 임시 기저 U/h
    internal var tempBasalDuration: Double? // 임시 기저 지속시간 (초)
    internal var tempBasalRateRatio: UInt16 = 0
    internal var tempBasalElapsedTime: UInt16 = 0 // 경과 시간 (분)

    // MARK: - Bolus

    internal var lastBolusAmount: Double = 0
    internal var lastBolusDate: Date?
    internal var lastBolusAutomatic: Bool = false
    internal var deliveredUnits: Double?
    internal var totalUnits: Double?
    internal var maxBolus: Double = 0
    internal var maxBolusPerDay: Double = 0
    internal var bolusSpeed: UInt8 = 4 // 1~8
    internal var beepAndAlarm: UInt8 = 0 // 0=소리, 1=무음, 2=진동
    internal var alarmIntensity: UInt8 = 0

    // MARK: - Limits

    internal var maxBasalPerHour: Double = 0
    internal var maxBasal: Double = 0 // maxBasalPerHour * 2.5

    // MARK: - 오늘 주입 합계

    internal var todayBasalAmount: Double = 0
    internal var todayMealAmount: Double = 0
    internal var todaySnackAmount: Double = 0

    // MARK: - 로그 동기화 커서

    /// 펌프에서 마지막으로 보고된 로그 번호 (BigAPSMainInfo에서 갱신)
    internal var pumpLastLogNum: UInt16 = 0
    /// 펌프에서 마지막으로 보고된 wrapping count (BigAPSMainInfo에서 갱신)
    internal var pumpWrappingCount: UInt8 = 0
    /// 앱에서 마지막으로 처리(fetch)한 로그 번호 — 다음 sync는 이 번호 이후부터
    internal var storedLastLogNum: UInt16 = 0
    /// 앱에서 마지막으로 처리한 wrapping count
    internal var storedWrappingCount: UInt8 = 0
    /// 최초 연결 여부 — true면 현재 위치를 기준점으로만 저장하고 과거 로그는 skip
    internal var isFirstLogSync: Bool = true
    /// 로그 동기화 시점의 펌프 시리얼 — 다른 펌프 연결 감지용
    internal var syncedSerialNumber: String?

    // MARK: - OTP (2단계 커밋용)

    internal var lastOtpNumber: UInt32 = 0
    internal var lastOtpMsgType: UInt8 = 0

    // MARK: - Pump Time

    internal var pumpTime: Date?
    internal var pumpTimeSyncedAt: Date?

    // MARK: - User Settings

    internal var cannulaDate: Date?
    internal var reservoirDate: Date?

    // MARK: - Computed Properties

    internal var tempBasalEndsAt: Date {
        basalDeliveryDate + (tempBasalDuration ?? 0)
    }

    internal var basalDeliveryState: PumpManagerStatus.BasalDeliveryState {
        switch basalDeliveryOrdinal {
        case .active:
            return .active(basalDeliveryDate)
        case .suspended:
            return .suspended(basalDeliveryDate)
        case .tempBasal:
            return .tempBasal(
                DoseEntry(
                    type: .tempBasal,
                    startDate: basalDeliveryDate,
                    value: tempBasalUnits ?? 0,
                    unit: .unitsPerHour
                )
            )
        }
    }

    // MARK: - Init

    internal init(basalSchedule: [Double]? = nil) {
        lastStatusDate = Date().addingTimeInterval(-8 * 60 * 60)
        isConnected = false
        reservoirLevel = 0
        batteryRemaining = 0
        bolusState = .noBolus
        self.basalSchedule = basalSchedule ?? []
        basalDeliveryOrdinal = .active
    }

    public init(rawValue: RawValue) {
        lastStatusDate = rawValue["lastStatusDate"] as? Date ?? Date().addingTimeInterval(-8 * 60 * 60)
        deviceName = rawValue["deviceName"] as? String
        bleIdentifier = rawValue["bleIdentifier"] as? String
        isConnected = false
        isOnBoarded = rawValue["isOnBoarded"] as? Bool ?? false
        reservoirLevel = rawValue["reservoirLevel"] as? Double ?? 0
        batteryRemaining = rawValue["batteryRemaining"] as? Double ?? 0
        isPumpSuspended = rawValue["isPumpSuspended"] as? Bool ?? false
        isTempBasalInProgress = rawValue["isTempBasalInProgress"] as? Bool ?? false
        firmwareVersion = rawValue["firmwareVersion"] as? String
        serialNumber = rawValue["serialNumber"] as? String
        basalSchedule = rawValue["basalSchedule"] as? [Double] ?? []
        basalPattern = rawValue["basalPattern"] as? UInt8 ?? 1
        basalDeliveryDate = rawValue["basalDeliveryDate"] as? Date ?? .now
        tempBasalUnits = rawValue["tempBasalUnits"] as? Double
        tempBasalDuration = rawValue["tempBasalDuration"] as? Double
        lastBolusAmount = rawValue["lastBolusAmount"] as? Double ?? 0
        lastBolusDate = rawValue["lastBolusDate"] as? Date
        deliveredUnits = rawValue["deliveredUnits"] as? Double
        totalUnits = rawValue["totalUnits"] as? Double
        maxBolus = rawValue["maxBolus"] as? Double ?? 0
        maxBolusPerDay = rawValue["maxBolusPerDay"] as? Double ?? 0
        maxBasalPerHour = rawValue["maxBasalPerHour"] as? Double ?? 0
        maxBasal = rawValue["maxBasal"] as? Double ?? 0
        bolusSpeed = rawValue["bolusSpeed"] as? UInt8 ?? 4
        beepAndAlarm = rawValue["beepAndAlarm"] as? UInt8 ?? 0
        alarmIntensity = rawValue["alarmIntensity"] as? UInt8 ?? 0
        pumpTime = rawValue["pumpTime"] as? Date
        pumpTimeSyncedAt = rawValue["pumpTimeSyncedAt"] as? Date
        cannulaDate = rawValue["cannulaDate"] as? Date
        reservoirDate = rawValue["reservoirDate"] as? Date
        pumpLastLogNum = UInt16((rawValue["pumpLastLogNum"] as? Int) ?? 0)
        pumpWrappingCount = UInt8((rawValue["pumpWrappingCount"] as? Int) ?? 0)
        storedLastLogNum = UInt16((rawValue["storedLastLogNum"] as? Int) ?? 0)
        storedWrappingCount = UInt8((rawValue["storedWrappingCount"] as? Int) ?? 0)
        isFirstLogSync = rawValue["isFirstLogSync"] as? Bool ?? true
        syncedSerialNumber = rawValue["syncedSerialNumber"] as? String

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        }

        bolusState = .noBolus

        if let rawBasalOrdinal = rawValue["basalDeliveryOrdinal"] as? DiaconnBasalState.RawValue {
            basalDeliveryOrdinal = DiaconnBasalState(rawValue: rawBasalOrdinal) ?? .active
        } else {
            basalDeliveryOrdinal = .active
        }
    }

    public var rawValue: RawValue {
        var value: [String: Any] = [:]

        value["lastStatusDate"] = lastStatusDate
        value["deviceName"] = deviceName
        value["bleIdentifier"] = bleIdentifier
        value["isOnBoarded"] = isOnBoarded
        value["reservoirLevel"] = reservoirLevel
        value["batteryRemaining"] = batteryRemaining
        value["isPumpSuspended"] = isPumpSuspended
        value["isTempBasalInProgress"] = isTempBasalInProgress
        value["firmwareVersion"] = firmwareVersion
        value["serialNumber"] = serialNumber
        value["insulinType"] = insulinType?.rawValue
        value["basalSchedule"] = basalSchedule
        value["basalPattern"] = basalPattern
        value["basalDeliveryDate"] = basalDeliveryDate
        value["basalDeliveryOrdinal"] = basalDeliveryOrdinal.rawValue
        value["tempBasalUnits"] = tempBasalUnits
        value["tempBasalDuration"] = tempBasalDuration
        value["lastBolusAmount"] = lastBolusAmount
        value["lastBolusDate"] = lastBolusDate
        value["deliveredUnits"] = deliveredUnits
        value["totalUnits"] = totalUnits
        value["maxBolus"] = maxBolus
        value["maxBolusPerDay"] = maxBolusPerDay
        value["maxBasalPerHour"] = maxBasalPerHour
        value["maxBasal"] = maxBasal
        value["bolusSpeed"] = bolusSpeed
        value["beepAndAlarm"] = beepAndAlarm
        value["alarmIntensity"] = alarmIntensity
        value["pumpTime"] = pumpTime
        value["pumpTimeSyncedAt"] = pumpTimeSyncedAt
        value["cannulaDate"] = cannulaDate
        value["reservoirDate"] = reservoirDate
        value["pumpLastLogNum"] = Int(pumpLastLogNum)
        value["pumpWrappingCount"] = Int(pumpWrappingCount)
        value["storedLastLogNum"] = Int(storedLastLogNum)
        value["storedWrappingCount"] = Int(storedWrappingCount)
        value["isFirstLogSync"] = isFirstLogSync
        value["syncedSerialNumber"] = syncedSerialNumber

        return value
    }

    // MARK: - Update from Pump Status

    /// BigAPSMainInfoInquireResponse에서 받은 DiaconnPumpStatus로 상태 업데이트
    mutating func updateFromPumpStatus(_ pumpStatus: DiaconnPumpStatus) {
        lastStatusDate = Date()
        reservoirLevel = pumpStatus.remainInsulin
        batteryRemaining = Double(pumpStatus.remainBattery) / 100.0
        isPumpSuspended = pumpStatus.isSuspended
        isTempBasalInProgress = pumpStatus.isTempBasalRunning
        firmwareVersion = pumpStatus.firmwareVersion
        serialNumber = pumpStatus.serialNumber
        majorVersion = pumpStatus.majorVersion
        minorVersion = pumpStatus.minorVersion

        // 기저 프로파일
        basalPattern = pumpStatus.currentBasePattern
        basalSchedule = pumpStatus.basalProfile
        currentBasalRate = pumpStatus.basalAmount

        // 임시 기저
        tempBasalRateRatio = pumpStatus.tempBasalRateRatio
        tempBasalElapsedTime = pumpStatus.tempBasalElapsedTime

        // 한도
        maxBolus = pumpStatus.maxBolus
        maxBolusPerDay = pumpStatus.maxBolusPerDay
        maxBasalPerHour = pumpStatus.maxBasalPerHour
        maxBasal = pumpStatus.maxBasal
        bolusSpeed = pumpStatus.bolusSpeed
        beepAndAlarm = pumpStatus.beepAndAlarm
        alarmIntensity = pumpStatus.alarmIntensity

        // 오늘 주입 합계
        todayBasalAmount = pumpStatus.todayBasalAmount
        todayMealAmount = pumpStatus.todayMealAmount
        todaySnackAmount = pumpStatus.todaySnackAmount

        // 기저 상태 업데이트
        if isPumpSuspended {
            basalDeliveryOrdinal = .suspended
            basalDeliveryDate = Date()
        } else if isTempBasalInProgress {
            basalDeliveryOrdinal = .tempBasal
        } else {
            basalDeliveryOrdinal = .active
            basalDeliveryDate = Date()
        }

        // 펌프 현재 로그 위치 갱신 (새 로그 감지에 사용)
        let prevStoredLast = storedLastLogNum
        let prevStoredWrap = storedWrappingCount
        pumpLastLogNum = pumpStatus.lastLogNum
        pumpWrappingCount = pumpStatus.wrappingCount

        // 최초 연결 시: stored 커서도 현재 위치로 초기화 (과거 로그 skip)
        if isFirstLogSync {
            storedLastLogNum = pumpStatus.lastLogNum
            storedWrappingCount = pumpStatus.wrappingCount
        }
        NSLog(
            "[DiaconnKit] updateFromPumpStatus: pumpLast=\(pumpLastLogNum) pumpWrap=\(pumpWrappingCount) storedLast=\(prevStoredLast)→\(storedLastLogNum) storedWrap=\(prevStoredWrap)→\(storedWrappingCount) isFirst=\(isFirstLogSync)"
        )

        // 펌프 시간
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        if let date = calendar.date(from: DateComponents(
            year: pumpStatus.pumpYear,
            month: pumpStatus.pumpMonth,
            day: pumpStatus.pumpDay,
            hour: pumpStatus.pumpHour,
            minute: pumpStatus.pumpMinute,
            second: pumpStatus.pumpSecond
        )) {
            pumpTime = date
            pumpTimeSyncedAt = Date()
        }
    }

    // MARK: - Helpers

    internal func getFriendlyDeviceName() -> String {
        "Diaconn G8"
    }

    internal func getPumpImageName() -> String {
        "diacong8"
    }

    internal static func convertBasal(_ scheduleItems: [RepeatingScheduleValue<Double>]) -> [Double] {
        let basalIntervals: [TimeInterval] = Array(0 ..< 24).map { TimeInterval(60 * 60 * $0) }
        var output: [Double] = []

        var currentIndex = 0
        for i in 0 ..< 24 {
            if currentIndex >= scheduleItems.count {
                output.append(scheduleItems[currentIndex - 1].value)
            } else if scheduleItems[currentIndex].startTime != basalIntervals[i] {
                output.append(scheduleItems[currentIndex - 1].value)
            } else {
                output.append(scheduleItems[currentIndex].value)
                currentIndex += 1
            }
        }

        return output
    }
}

extension DiaconnPumpManagerState: CustomDebugStringConvertible {
    public var debugDescription: String {
        [
            "## DiaconnPumpManagerState - \(Date.now)",
            "* isOnboarded: \(isOnBoarded)",
            "* deviceName: \(deviceName ?? "<EMPTY>")",
            "* bleIdentifier: \(bleIdentifier ?? "<EMPTY>")",
            "* serialNumber: \(serialNumber ?? "<EMPTY>")",
            "* lastStatusDate: \(lastStatusDate)",
            "* reservoirLevel: \(reservoirLevel)U",
            "* batteryRemaining: \(Int(batteryRemaining * 100))%",
            "* isPumpSuspended: \(isPumpSuspended)",
            "* isTempBasalInProgress: \(isTempBasalInProgress)",
            "* bolusState: \(bolusState.rawValue)",
            "* basalDeliveryOrdinal: \(basalDeliveryOrdinal)",
            "* firmwareVersion: \(firmwareVersion ?? "<EMPTY>")",
            "* maxBolus: \(maxBolus)U",
            "* maxBasalPerHour: \(maxBasalPerHour)U/h"
        ].joined(separator: "\n")
    }
}
