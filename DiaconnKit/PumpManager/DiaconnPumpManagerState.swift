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
    public internal(set) var reservoirLevel: Double = 0 // Remaining insulin (U)
    public internal(set) var batteryRemaining: Double = 0 // Battery (0.0~1.0)

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
    internal var basalSchedule: [Double] // 24-hour basal profile (U/h)
    internal var basalPattern: UInt8 = 1 // Current basal pattern (1~6)
    internal var currentBasalRate: Double = 0 // Current hour basal rate

    // MARK: - Temp Basal

    internal var tempBasalUnits: Double? // Temp basal U/h
    internal var tempBasalDuration: Double? // Temp basal duration (seconds)
    internal var tempBasalRateRatio: UInt16 = 0
    internal var tempBasalElapsedTime: UInt16 = 0 // Elapsed time (minutes)

    // MARK: - Bolus

    internal var lastBolusAmount: Double = 0
    internal var lastBolusDate: Date?
    internal var lastBolusAutomatic: Bool = false
    internal var deliveredUnits: Double?
    internal var totalUnits: Double?
    internal var maxBolus: Double = 0
    internal var maxBolusPerDay: Double = 0
    internal var bolusSpeed: UInt8 = 4 // 1~8
    internal var beepAndAlarm: UInt8 = 0 // 0=sound, 1=mute, 2=vibrate
    internal var alarmIntensity: UInt8 = 0

    // MARK: - Limits

    internal var maxBasalPerHour: Double = 0
    internal var maxBasal: Double = 0 // maxBasalPerHour * 2.5

    // MARK: - Today injection total

    internal var todayBasalAmount: Double = 0
    internal var todayMealAmount: Double = 0
    internal var todaySnackAmount: Double = 0

    // MARK: - Log sync cursor

    /// Last log number reported by pump (updated from BigAPSMainInfo)
    internal var pumpLastLogNum: UInt16 = 0
    /// Last wrapping count reported by pump (updated from BigAPSMainInfo)
    internal var pumpWrappingCount: UInt8 = 0
    /// Last log number processed (fetched) by app — next sync starts after this number
    internal var storedLastLogNum: UInt16 = 0
    /// Last wrapping count processed by app
    internal var storedWrappingCount: UInt8 = 0
    /// First connection flag — if true, save current position as baseline and skip past logs
    internal var isFirstLogSync: Bool = true
    /// Pump serial at log sync time — for detecting different pump connection
    internal var syncedSerialNumber: String?
    /// Pump incarnation number (0~65535) — for detecting factory reset
    internal var syncedIncarnation: UInt16 = 0

    // MARK: - OTP (for two-step commit)

    internal var lastOtpNumber: UInt32 = 0
    internal var lastOtpMsgType: UInt8 = 0

    // MARK: - Pump Time

    internal var pumpTime: Date?
    internal var pumpTimeSyncedAt: Date?
    internal var pumpTimeZone = TimeZone.current

    // MARK: - Cloud Sync

    internal var cloudLogSyncEnabled: Bool = false
    /// Incarnation number that was used in the last successful cloud sync query
    internal var cloudSyncedIncarnation: UInt16 = 0
    /// Last log position confirmed stored in cloud
    internal var cloudLastLogNum: Int = 0
    internal var cloudLastWrapCount: Int = 0
    /// Cloud sync in-progress flag (transient, not persisted)
    internal var isCloudSyncing: Bool = false
    internal var cloudSyncCurrentPage: Int = 0
    internal var cloudSyncTotalPages: Int = 0

    // MARK: - User Settings

    internal var cannulaDate: Date?
    internal var reservoirDate: Date?
    internal var batteryDate: Date?

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
            let elapsed = TimeInterval(tempBasalElapsedTime) * 60
            let totalDuration = tempBasalDuration ?? 0
            let tbStartDate = basalDeliveryDate.addingTimeInterval(-elapsed)
            let tbEndDate = tbStartDate.addingTimeInterval(totalDuration)
            return .tempBasal(
                DoseEntry(
                    type: .tempBasal,
                    startDate: tbStartDate,
                    endDate: tbEndDate,
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
        if let tzIdentifier = rawValue["pumpTimeZone"] as? String,
           let tz = TimeZone(identifier: tzIdentifier)
        {
            pumpTimeZone = tz
        }
        cannulaDate = rawValue["cannulaDate"] as? Date
        reservoirDate = rawValue["reservoirDate"] as? Date
        batteryDate = rawValue["batteryDate"] as? Date
        pumpLastLogNum = UInt16((rawValue["pumpLastLogNum"] as? Int) ?? 0)
        pumpWrappingCount = UInt8((rawValue["pumpWrappingCount"] as? Int) ?? 0)
        storedLastLogNum = UInt16((rawValue["storedLastLogNum"] as? Int) ?? 0)
        storedWrappingCount = UInt8((rawValue["storedWrappingCount"] as? Int) ?? 0)
        isFirstLogSync = rawValue["isFirstLogSync"] as? Bool ?? true
        syncedSerialNumber = rawValue["syncedSerialNumber"] as? String
        syncedIncarnation = UInt16((rawValue["syncedIncarnation"] as? Int) ?? 0)
        cloudLogSyncEnabled = rawValue["cloudLogSyncEnabled"] as? Bool ?? false
        cloudSyncedIncarnation = UInt16((rawValue["cloudSyncedIncarnation"] as? Int) ?? 0)
        cloudLastLogNum = rawValue["cloudLastLogNum"] as? Int ?? 0
        cloudLastWrapCount = rawValue["cloudLastWrapCount"] as? Int ?? 0

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
        value["pumpTimeZone"] = pumpTimeZone.identifier
        value["cannulaDate"] = cannulaDate
        value["reservoirDate"] = reservoirDate
        value["batteryDate"] = batteryDate
        value["pumpLastLogNum"] = Int(pumpLastLogNum)
        value["pumpWrappingCount"] = Int(pumpWrappingCount)
        value["storedLastLogNum"] = Int(storedLastLogNum)
        value["storedWrappingCount"] = Int(storedWrappingCount)
        value["isFirstLogSync"] = isFirstLogSync
        value["syncedSerialNumber"] = syncedSerialNumber
        value["syncedIncarnation"] = Int(syncedIncarnation)
        value["cloudLogSyncEnabled"] = cloudLogSyncEnabled
        value["cloudSyncedIncarnation"] = Int(cloudSyncedIncarnation)
        value["cloudLastLogNum"] = cloudLastLogNum
        value["cloudLastWrapCount"] = cloudLastWrapCount

        return value
    }

    // MARK: - Update from Pump Status

    /// Update state from DiaconnPumpStatus received via BigAPSMainInfoInquireResponse
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

        // Basal profile
        basalPattern = pumpStatus.currentBasePattern
        basalSchedule = pumpStatus.basalProfile
        currentBasalRate = pumpStatus.basalAmount

        // Temp basal
        tempBasalRateRatio = pumpStatus.tempBasalRateRatio
        tempBasalElapsedTime = pumpStatus.tempBasalElapsedTime
        tempBasalDuration = Double(pumpStatus.tempBasalTime) * 15 * 60 // 1 unit = 15 min → seconds

        // Limits
        maxBolus = pumpStatus.maxBolus
        maxBolusPerDay = pumpStatus.maxBolusPerDay
        maxBasalPerHour = pumpStatus.maxBasalPerHour
        maxBasal = pumpStatus.maxBasal
        bolusSpeed = pumpStatus.bolusSpeed
        beepAndAlarm = pumpStatus.beepAndAlarm
        alarmIntensity = pumpStatus.alarmIntensity

        // Today injection total
        todayBasalAmount = pumpStatus.todayBasalAmount
        todayMealAmount = pumpStatus.todayMealAmount
        todaySnackAmount = pumpStatus.todaySnackAmount

        // Update basal status
        if isPumpSuspended {
            basalDeliveryOrdinal = .suspended
            basalDeliveryDate = Date()
        } else if isTempBasalInProgress {
            basalDeliveryOrdinal = .tempBasal
            basalDeliveryDate = Date()
            // Calculate current TBR rate from pump
            let ratio = Int(tempBasalRateRatio)
            if ratio >= 50000 {
                tempBasalUnits = currentBasalRate * Double(ratio - 50000) / 100.0
            } else if ratio >= 1000 {
                tempBasalUnits = Double(ratio - 1000) / 100.0
            }
            NSLog(
                "[DiaconnKit] TBR status: ratio=\(tempBasalRateRatio) → units=\(tempBasalUnits ?? -1) U/h, duration=\(tempBasalDuration ?? -1)s, elapsed=\(tempBasalElapsedTime)min"
            )
        } else {
            basalDeliveryOrdinal = .active
            basalDeliveryDate = Date()
            tempBasalUnits = nil
        }

        // Update pump current log position (used for new log detection)
        let prevStoredLast = storedLastLogNum
        let prevStoredWrap = storedWrappingCount
        pumpLastLogNum = pumpStatus.lastLogNum
        pumpWrappingCount = pumpStatus.wrappingCount

        // First connection: initialize stored cursor to current position (skip past logs)
        if isFirstLogSync {
            storedLastLogNum = pumpStatus.lastLogNum
            storedWrappingCount = pumpStatus.wrappingCount
        }
        NSLog(
            "[DiaconnKit] updateFromPumpStatus: pumpLast=\(pumpLastLogNum) pumpWrap=\(pumpWrappingCount) storedLast=\(prevStoredLast)→\(storedLastLogNum) storedWrap=\(prevStoredWrap)→\(storedWrappingCount) isFirst=\(isFirstLogSync)"
        )

        // Pump time
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pumpTimeZone
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
            "* incarnation: \(syncedIncarnation)",
            "* maxBolus: \(maxBolus)U",
            "* maxBasalPerHour: \(maxBasalPerHour)U/h"
        ].joined(separator: "\n")
    }
}
