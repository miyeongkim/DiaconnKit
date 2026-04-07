import Foundation
import os.log

/// 디아콘 G8 통신 로깅 유틸리티
public class DiaconnLogger {
    private static let subsystem = "com.diaconn.DiaconnKit"
    private let logger: OSLog
    private let category: String

    public enum Level {
        case debug
        case info
        case warning
        case error
    }

    /// 카테고리별 로거 생성
    public init(category: String) {
        self.category = category
        logger = OSLog(subsystem: DiaconnLogger.subsystem, category: category)
    }

    /// 로그 메시지 출력 (인스턴스 메서드)
    public func log(_ level: Level, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let prefix = "[\(fileName):\(line)] \(function)"

        switch level {
        case .debug:
            os_log("%{public}@ DEBUG: %{public}@", log: logger, type: .debug, prefix, message)
        case .info:
            os_log("%{public}@ INFO: %{public}@", log: logger, type: .info, prefix, message)
        case .warning:
            os_log("%{public}@ WARNING: %{public}@", log: logger, type: .default, prefix, message)
        case .error:
            os_log("%{public}@ ERROR: %{public}@", log: logger, type: .error, prefix, message)
        }
    }

    /// 디버그 로그 (개발용)
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    /// 정보 로그
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    /// 경고 로그
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    /// 에러 로그
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    /// 패킷 데이터를 16진수로 로깅
    public func logPacket(
        _ direction: String,
        _ data: Data,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        debug("\(direction): \(hex)", file: file, function: function, line: line)
    }
}
