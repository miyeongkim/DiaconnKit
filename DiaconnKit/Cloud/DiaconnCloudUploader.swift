import Foundation

class DiaconnCloudUploader {
    static let baseURL = "https://api.diaconn.com/aaps/"
    static let apiKey = "D7B3DA9FA8229D5253F3D75E1E2B1BA4"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getPumpLastNo(pumpUid: String, pumpVersion: String, incarnationNum: Int) async throws -> Int64 {
        guard var components = URLComponents(string: Self.baseURL + "v1/pumplog/last_no") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "pump_uid", value: pumpUid),
            URLQueryItem(name: "pump_version", value: pumpVersion),
            URLQueryItem(name: "incarnation_num", value: String(incarnationNum))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.apiKey, forHTTPHeaderField: "api-key")

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(DiaconnLastNoResponse.self, from: data)
        guard response.ok else { return -1 }
        return response.info?.pumplog_no ?? -1
    }

    func uploadPumpLogs(dto: DiaconnPumpLogDto) async throws -> Bool {
        guard let url = URL(string: Self.baseURL + "v1/pumplog/save") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = try JSONEncoder().encode(dto)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(DiaconnApiResponse.self, from: data)
        return response.ok
    }
}
