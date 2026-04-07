import Foundation

/// 디아콘 G8 프로토콜 패킷 타입 및 명령 코드 정의
/// AndroidAPS DiaconnG8Packet.kt 기반
public enum DiaconnPacketType {
    // MARK: - 패킷 구조 상수

    public static let MSG_LEN: Int = 20 // 표준 패킷 길이
    public static let MSG_LEN_BIG: Int = 182 // 대량 패킷 길이
    public static let SOP: UInt8 = 0xEF // 표준 패킷 시작 바이트
    public static let SOP_BIG: UInt8 = 0xED // 대량 패킷 시작 바이트
    public static let MSG_TYPE_LOC: Int = 1 // msgType 위치
    public static let MSG_SEQ_LOC: Int = 2 // 시퀀스 번호 위치
    public static let MSG_DATA_LOC: Int = 4 // 데이터 시작 위치
    public static let MSG_PAD: UInt8 = 0xFF // 패딩 바이트
    public static let MSG_CON_END: UInt8 = 0x00 // 패킷 종료
    public static let MSG_CON_CONTINUE: UInt8 = 0x01 // 패킷 계속

    // MARK: - 설정 명령 (App → Pump) / 설정 응답 (Pump → App)

    /// 기저 정지/재개: status(1=정지, 2=해제)
    public static let BASAL_PAUSE_SETTING: UInt8 = 0x03
    public static let BASAL_PAUSE_SETTING_RESPONSE: UInt8 = 0x83

    /// 볼루스(간식) 주입: amount(short, *100)
    public static let INJECTION_SNACK_SETTING: UInt8 = 0x07
    public static let INJECTION_SNACK_SETTING_RESPONSE: UInt8 = 0x87

    /// 식사 볼루스 주입
    public static let INJECTION_MEAL_SETTING: UInt8 = 0x06
    public static let INJECTION_MEAL_SETTING_RESPONSE: UInt8 = 0x86

    /// 임시 기저 설정: status, time, injectRateRatio, tbDttm
    public static let TEMP_BASAL_SETTING: UInt8 = 0x0A
    public static let TEMP_BASAL_SETTING_RESPONSE: UInt8 = 0x8A

    /// 기저 프로파일 설정: pattern, group, amounts[6]
    public static let BASAL_SETTING: UInt8 = 0x0B
    public static let BASAL_SETTING_RESPONSE: UInt8 = 0x8B

    /// 확장 볼루스 설정
    public static let INJECTION_EXTENDED_BOLUS_SETTING: UInt8 = 0x08
    public static let INJECTION_EXTENDED_BOLUS_SETTING_RESPONSE: UInt8 = 0x88

    /// 시간 설정: year, month, day, hour, minute, second
    public static let TIME_SETTING: UInt8 = 0x0F
    public static let TIME_SETTING_RESPONSE: UInt8 = 0x8F

    /// 볼루스 속도 설정
    public static let BOLUS_SPEED_SETTING: UInt8 = 0x05
    public static let BOLUS_SPEED_SETTING_RESPONSE: UInt8 = 0x85

    /// 음향 설정
    public static let SOUND_SETTING: UInt8 = 0x0D
    public static let SOUND_SETTING_RESPONSE: UInt8 = 0x8D

    /// 음향 조회
    public static let SOUND_INQUIRE: UInt8 = 0x4D
    public static let SOUND_INQUIRE_RESPONSE: UInt8 = 0x8D

    /// 언어 설정
    public static let LANGUAGE_SETTING: UInt8 = 0x20
    public static let LANGUAGE_SETTING_RESPONSE: UInt8 = 0xA0

    /// 디스플레이 타임아웃 설정
    public static let DISPLAY_TIMEOUT_SETTING: UInt8 = 0x0E
    public static let DISPLAY_TIMEOUT_SETTING_RESPONSE: UInt8 = 0x8E

    /// 주입 취소: reqMsgType(byte)
    public static let INJECTION_CANCEL_SETTING: UInt8 = 0x2B
    public static let INJECTION_CANCEL_SETTING_RESPONSE: UInt8 = 0xAB

    /// 앱 취소 설정
    public static let APP_CANCEL_SETTING: UInt8 = 0x29
    public static let APP_CANCEL_SETTING_RESPONSE: UInt8 = 0xA9

    /// 앱 확인 설정
    public static let APP_CONFIRM_SETTING: UInt8 = 0x37
    public static let APP_CONFIRM_SETTING_RESPONSE: UInt8 = 0xB7

    // MARK: - 조회 명령 (App → Pump) / 조회 응답 (Pump → App)

    /// 전체 상태 조회 (APS용 대형 패킷)
    public static let BIG_APS_MAIN_INFO_INQUIRE: UInt8 = 0x54
    public static let BIG_APS_MAIN_INFO_INQUIRE_RESPONSE: UInt8 = 0x94

    /// 일반 전체 상태 조회
    public static let BIG_MAIN_INFO_INQUIRE: UInt8 = 0x73
    public static let BIG_MAIN_INFO_INQUIRE_RESPONSE: UInt8 = 0xB3

    /// 시간 조회
    public static let TIME_INQUIRE: UInt8 = 0x4F
    public static let TIME_INQUIRE_RESPONSE: UInt8 = 0x8F

    /// 임시 기저 상태 조회
    public static let TEMP_BASAL_INQUIRE: UInt8 = 0x4A
    public static let TEMP_BASAL_INQUIRE_RESPONSE: UInt8 = 0x8A

    /// 볼루스 속도 조회
    public static let BOLUS_SPEED_INQUIRE: UInt8 = 0x45
    public static let BOLUS_SPEED_INQUIRE_RESPONSE: UInt8 = 0x85

    /// 시리얼 번호 조회
    public static let SERIAL_NUM_INQUIRE: UInt8 = 0x6E
    public static let SERIAL_NUM_INQUIRE_RESPONSE: UInt8 = 0xAE

    /// 인카네이션 번호 조회
    public static let INCARNATION_INQUIRE: UInt8 = 0x7A
    public static let INCARNATION_INQUIRE_RESPONSE: UInt8 = 0xBA

    /// 로그 상태 조회
    public static let LOG_STATUS_INQUIRE: UInt8 = 0x56
    public static let LOG_STATUS_INQUIRE_RESPONSE: UInt8 = 0x96

    /// 대량 로그 조회
    public static let BIG_LOG_INQUIRE: UInt8 = 0x72
    public static let BIG_LOG_INQUIRE_RESPONSE: UInt8 = 0xB2

    // MARK: - 보고 패킷 (Pump → App, 비요청)

    /// 볼루스 진행률 보고
    public static let INJECTION_PROGRESS_REPORT: UInt8 = 0xEA

    /// 확인 보고
    public static let CONFIRM_REPORT: UInt8 = 0xE8

    /// 기저 주입 보고
    public static let INJECTION_BASAL_REPORT: UInt8 = 0xE7

    /// 임시 기저 보고
    public static let TEMP_BASAL_REPORT: UInt8 = 0xCA

    /// 기저 설정 보고
    public static let BASAL_SETTING_REPORT: UInt8 = 0xCB

    /// 기저 정지 보고
    public static let BASAL_PAUSE_REPORT: UInt8 = 0xC3

    /// 간식 볼루스 결과 보고
    public static let INJECTION_SNACK_RESULT_REPORT: UInt8 = 0xE4

    /// 확장 볼루스 결과 보고
    public static let INJECTION_EXTENDED_BOLUS_RESULT_REPORT: UInt8 = 0xE5

    /// 주입 막힘 보고
    public static let INJECTION_BLOCK_REPORT: UInt8 = 0xD8

    /// 인슐린 부족 보고
    public static let INSULIN_LACK_REPORT: UInt8 = 0xD9

    /// 볼루스 속도 설정 보고
    public static let BOLUS_SPEED_SETTING_REPORT: UInt8 = 0xC5

    /// 음향 설정 보고
    public static let SOUND_SETTING_REPORT: UInt8 = 0xCD

    /// 시간 보고
    public static let TIME_REPORT: UInt8 = 0xCF

    /// 거부 보고
    public static let REJECT_REPORT: UInt8 = 0xE2

    // MARK: - 설정 응답 결과 코드

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

    // MARK: - 조회 응답 결과 코드

    public enum InquireResult: Int {
        case success = 16
        case crcError = 17
        case parameterError = 18
        case protocolError = 19
        case unknownError = 21
    }
}
