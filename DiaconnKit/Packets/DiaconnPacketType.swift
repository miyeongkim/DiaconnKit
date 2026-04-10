import Foundation

/// Diaconn G8 protocol packet type and command code definitions
/// Based on AndroidAPS DiaconnG8Packet.kt
public enum DiaconnPacketType {
    // MARK: - Packet structure constants

    public static let MSG_LEN: Int = 20 // Standard packet length
    public static let MSG_LEN_BIG: Int = 182 // Big packet length
    public static let SOP: UInt8 = 0xEF // Standard packet start byte
    public static let SOP_BIG: UInt8 = 0xED // Big packet start byte
    public static let MSG_TYPE_LOC: Int = 1 // msgType position
    public static let MSG_SEQ_LOC: Int = 2 // Sequence number position
    public static let MSG_DATA_LOC: Int = 4 // Data start position
    public static let MSG_PAD: UInt8 = 0xFF // Padding byte
    public static let MSG_CON_END: UInt8 = 0x00 // Packet end
    public static let MSG_CON_CONTINUE: UInt8 = 0x01 // Packet continue

    // MARK: - Setting commands (App → Pump) / Setting responses (Pump → App)

    /// Basal pause/resume: status(1=pause, 2=release)
    public static let BASAL_PAUSE_SETTING: UInt8 = 0x03
    public static let BASAL_PAUSE_SETTING_RESPONSE: UInt8 = 0x83

    /// Bolus (snack) injection: amount(short, *100)
    public static let INJECTION_SNACK_SETTING: UInt8 = 0x07
    public static let INJECTION_SNACK_SETTING_RESPONSE: UInt8 = 0x87

    /// Meal bolus injection
    public static let INJECTION_MEAL_SETTING: UInt8 = 0x06
    public static let INJECTION_MEAL_SETTING_RESPONSE: UInt8 = 0x86

    /// Temp basal setting: status, time, injectRateRatio, tbDttm
    public static let TEMP_BASAL_SETTING: UInt8 = 0x0A
    public static let TEMP_BASAL_SETTING_RESPONSE: UInt8 = 0x8A

    /// Basal profile setting: pattern, group, amounts[6]
    public static let BASAL_SETTING: UInt8 = 0x0B
    public static let BASAL_SETTING_RESPONSE: UInt8 = 0x8B

    /// Extended bolus setting
    public static let INJECTION_EXTENDED_BOLUS_SETTING: UInt8 = 0x08
    public static let INJECTION_EXTENDED_BOLUS_SETTING_RESPONSE: UInt8 = 0x88

    /// Time setting: year, month, day, hour, minute, second
    public static let TIME_SETTING: UInt8 = 0x0F
    public static let TIME_SETTING_RESPONSE: UInt8 = 0x8F

    /// Bolus speed setting
    public static let BOLUS_SPEED_SETTING: UInt8 = 0x05
    public static let BOLUS_SPEED_SETTING_RESPONSE: UInt8 = 0x85

    /// Sound setting
    public static let SOUND_SETTING: UInt8 = 0x0D
    public static let SOUND_SETTING_RESPONSE: UInt8 = 0x8D

    /// Sound inquiry
    public static let SOUND_INQUIRE: UInt8 = 0x4D
    public static let SOUND_INQUIRE_RESPONSE: UInt8 = 0x8D

    /// Language setting
    public static let LANGUAGE_SETTING: UInt8 = 0x20
    public static let LANGUAGE_SETTING_RESPONSE: UInt8 = 0xA0

    /// Display timeout setting
    public static let DISPLAY_TIMEOUT_SETTING: UInt8 = 0x0E
    public static let DISPLAY_TIMEOUT_SETTING_RESPONSE: UInt8 = 0x8E

    /// Injection cancel: reqMsgType(byte)
    public static let INJECTION_CANCEL_SETTING: UInt8 = 0x2B
    public static let INJECTION_CANCEL_SETTING_RESPONSE: UInt8 = 0xAB

    /// App cancel setting
    public static let APP_CANCEL_SETTING: UInt8 = 0x29
    public static let APP_CANCEL_SETTING_RESPONSE: UInt8 = 0xA9

    /// App confirm setting
    public static let APP_CONFIRM_SETTING: UInt8 = 0x37
    public static let APP_CONFIRM_SETTING_RESPONSE: UInt8 = 0xB7

    // MARK: - Inquiry commands (App → Pump) / Inquiry responses (Pump → App)

    /// Full status inquiry (APS big packet)
    public static let BIG_APS_MAIN_INFO_INQUIRE: UInt8 = 0x54
    public static let BIG_APS_MAIN_INFO_INQUIRE_RESPONSE: UInt8 = 0x94

    /// General full status inquiry
    public static let BIG_MAIN_INFO_INQUIRE: UInt8 = 0x73
    public static let BIG_MAIN_INFO_INQUIRE_RESPONSE: UInt8 = 0xB3

    /// Time inquiry
    public static let TIME_INQUIRE: UInt8 = 0x4F
    public static let TIME_INQUIRE_RESPONSE: UInt8 = 0x8F

    /// Temp basal status inquiry
    public static let TEMP_BASAL_INQUIRE: UInt8 = 0x4A
    public static let TEMP_BASAL_INQUIRE_RESPONSE: UInt8 = 0x8A

    /// Bolus speed inquiry
    public static let BOLUS_SPEED_INQUIRE: UInt8 = 0x45
    public static let BOLUS_SPEED_INQUIRE_RESPONSE: UInt8 = 0x85

    /// Serial number inquiry
    public static let SERIAL_NUM_INQUIRE: UInt8 = 0x6E
    public static let SERIAL_NUM_INQUIRE_RESPONSE: UInt8 = 0xAE

    /// Incarnation number inquiry
    public static let INCARNATION_INQUIRE: UInt8 = 0x7A
    public static let INCARNATION_INQUIRE_RESPONSE: UInt8 = 0xBA

    /// Log status inquiry
    public static let LOG_STATUS_INQUIRE: UInt8 = 0x56
    public static let LOG_STATUS_INQUIRE_RESPONSE: UInt8 = 0x96

    /// Big log inquiry
    public static let BIG_LOG_INQUIRE: UInt8 = 0x72
    public static let BIG_LOG_INQUIRE_RESPONSE: UInt8 = 0xB2

    // MARK: - Report packets (Pump → App, unsolicited)

    /// Bolus progress report
    public static let INJECTION_PROGRESS_REPORT: UInt8 = 0xEA

    /// Confirm report
    public static let CONFIRM_REPORT: UInt8 = 0xE8

    /// Basal injection report
    public static let INJECTION_BASAL_REPORT: UInt8 = 0xE7

    /// Temp basal report
    public static let TEMP_BASAL_REPORT: UInt8 = 0xCA

    /// Basal setting report
    public static let BASAL_SETTING_REPORT: UInt8 = 0xCB

    /// Basal pause report
    public static let BASAL_PAUSE_REPORT: UInt8 = 0xC3

    /// Snack bolus result report
    public static let INJECTION_SNACK_RESULT_REPORT: UInt8 = 0xE4

    /// Extended bolus result report
    public static let INJECTION_EXTENDED_BOLUS_RESULT_REPORT: UInt8 = 0xE5

    /// Battery shortage report
    public static let BATTERY_SHORTAGE_REPORT: UInt8 = 0xD7

    /// Injection block report
    public static let INJECTION_BLOCK_REPORT: UInt8 = 0xD8

    /// Insulin shortage report
    public static let INSULIN_LACK_REPORT: UInt8 = 0xD9

    /// Bolus speed setting report
    public static let BOLUS_SPEED_SETTING_REPORT: UInt8 = 0xC5

    /// Sound setting report
    public static let SOUND_SETTING_REPORT: UInt8 = 0xCD

    /// Time report
    public static let TIME_REPORT: UInt8 = 0xCF

    /// Reject report
    public static let REJECT_REPORT: UInt8 = 0xE2

    // MARK: - Setting response result codes

    public enum SettingResult: Int {
        case success = 0
        case crcError = 1
        case parameterError = 2
        case protocolError = 3
        case eatingTimeout = 4
        case unknownError = 5
        case basalHourlyLimitExceeded = 6
        case otherOperationInProgress = 7
        case anotherBolusInProgress = 8
        case basalReleaseRequired = 9
        case otpMismatch = 10
        case lowBattery = 11
        case lowInsulin = 12
        case singleLimitExceeded = 13
        case dailyLimitExceeded = 14
        case basalSettingRequired = 15
        case lgsRunning = 32
        case lgsAlreadyOn = 33
        case lgsAlreadyOff = 34
        case tempBasalAlreadyRunning = 35
        case tempBasalNotRunning = 36
    }

    // MARK: - Inquiry response result codes

    public enum InquireResult: Int {
        case success = 16
        case crcError = 17
        case parameterError = 18
        case protocolError = 19
        case unknownError = 21
    }
}
