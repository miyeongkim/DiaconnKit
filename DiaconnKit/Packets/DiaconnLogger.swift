import Foundation
import os.log

/// Diaconn G8 communication logging utility
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

    /// Create logger for category
    public init(category: String) {
        self.category = category
        logger = OSLog(subsystem: DiaconnLogger.subsystem, category: category)
    }

    /// Output log message (instance method)
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

    /// Debug log (for development)
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    /// Info log
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    /// Warning log
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    /// Error log
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    /// Log packet data as hexadecimal
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
