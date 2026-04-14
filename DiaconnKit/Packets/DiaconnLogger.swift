import Foundation
import os.log

/// Diaconn G8 communication logging utility
/// Logs to both OSLog and file (documents/diaconnkit/diaconn_log.txt)
public class DiaconnLogger {
    private static let subsystem = "com.diaconn.DiaconnKit"
    private let logger: OSLog
    private let category: String
    private let fileManager = FileManager.default

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
            writeToFile("\(prefix): \(message)", "INFO")
        case .warning:
            os_log("%{public}@ WARNING: %{public}@", log: logger, type: .default, prefix, message)
            writeToFile("\(prefix): \(message)", "WARNING")
        case .error:
            os_log("%{public}@ ERROR: %{public}@", log: logger, type: .error, prefix, message)
            writeToFile("\(prefix): \(message)", "ERROR")
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
        debug(
            "\(direction): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))",
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - File Logging

    private func writeToFile(_ msg: String, _ level: String) {
        if !fileManager.fileExists(atPath: logDir) {
            try? fileManager.createDirectory(
                atPath: logDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())

        if !fileManager.fileExists(atPath: logFilePath) {
            fileManager.createFile(atPath: logFilePath, contents: nil, attributes: [.creationDate: startOfDay])
        } else if let attributes = try? fileManager.attributesOfItem(atPath: logFilePath),
                  let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
        {
            try? fileManager.removeItem(atPath: logFilePrevPath)
            try? fileManager.moveItem(atPath: logFilePath, toPath: logFilePrevPath)
            fileManager.createFile(atPath: logFilePath, contents: nil, attributes: [.creationDate: startOfDay])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let logEntry = "[\(dateFormatter.string(from: Date())) \(level)] \(msg)\n"

        if let data = logEntry.data(using: .utf8),
           let handle = FileHandle(forWritingAtPath: logFilePath)
        {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    private var logDir: String {
        documentsDirectory.appendingPathComponent("diaconnkit").path
    }

    private var logFilePath: String {
        documentsDirectory.appendingPathComponent("diaconnkit/diaconn_log.txt").path
    }

    private var logFilePrevPath: String {
        documentsDirectory.appendingPathComponent("diaconnkit/diaconn_log_prev.txt").path
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Log Sharing

    public func getDebugLogs() -> [URL] {
        var items: [URL] = []
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("diaconn_share", isDirectory: true)
        try? fileManager.removeItem(at: tempDir)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for path in [logFilePath, logFilePrevPath] {
            if fileManager.fileExists(atPath: path) {
                let sourceURL = URL(fileURLWithPath: path)
                let destURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
                try? fileManager.copyItem(at: sourceURL, to: destURL)
                items.append(destURL)
            }
        }
        return items
    }
}
