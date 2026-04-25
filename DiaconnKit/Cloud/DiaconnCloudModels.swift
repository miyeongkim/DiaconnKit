import Foundation

struct DiaconnLastNoResponse: Decodable {
    let ok: Bool
    let info: DiaconnLastNoInfo?
}

struct DiaconnLastNoInfo: Decodable {
    let pumplog_no: Int64
}

struct DiaconnApiResponse: Decodable {
    let ok: Bool
}

struct DiaconnPumpLogDto: Encodable {
    let app_uid: String
    let app_version: String
    let pump_uid: String
    let pump_version: String
    let incarnation_num: Int
    let pumplog_info: [DiaconnPumpLog]
}

struct DiaconnPumpLog: Encodable {
    let pumplog_no: Int64
    let pumplog_wrapping_count: Int
    let pumplog_data: String
    let act_type: String
}
