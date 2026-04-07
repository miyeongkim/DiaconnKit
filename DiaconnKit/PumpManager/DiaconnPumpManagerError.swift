import Foundation

public enum DiaconnPumpManagerError: Error, LocalizedError {
    case notConnected
    case pumpSuspended
    case bolusInProgress
    case communicationFailure
    case settingFailed(DiaconnPacketType.SettingResult)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Pump is not connected"
        case .pumpSuspended:
            return "Pump is suspended"
        case .bolusInProgress:
            return "A bolus is already in progress"
        case .communicationFailure:
            return "Communication with pump failed"
        case let .settingFailed(result):
            return settingResultDescription(result)
        case let .unknown(message):
            return "Unknown error: \(message)"
        }
    }

    private func settingResultDescription(_ result: DiaconnPacketType.SettingResult) -> String {
        switch result {
        case .success: return "Success"
        case .crcError: return "Packet CRC error"
        case .parameterError: return "Parameter error"
        case .protocolError: return "Protocol specification error"
        case .eatingTimeout: return "Eating timeout, not injectable"
        case .unknownError: return "Unknown error"
        case .basalHourlyLimitExceeded: return "Basal hourly limit exceeded"
        case .otherOperationInProgress: return "Other operation in progress"
        case .anotherBolusInProgress: return "Another bolus in progress"
        case .basalReleaseRequired: return "Basal release is required"
        case .otpMismatch: return "OTP number did not match"
        case .lowBattery: return "Low battery, injection not possible"
        case .lowInsulin: return "Low insulin, injection not possible"
        case .singleLimitExceeded: return "Single injection limit exceeded"
        case .dailyLimitExceeded: return "Daily injection limit exceeded"
        case .basalSettingRequired: return "Basal setting must be completed first"
        case .lgsRunning: return "LGS running, injection restricted"
        case .lgsAlreadyOn: return "LGS is already ON"
        case .lgsAlreadyOff: return "LGS is already OFF"
        case .tempBasalAlreadyRunning: return "Temp basal is already running"
        case .tempBasalNotRunning: return "Temp basal is not running"
        }
    }
}
