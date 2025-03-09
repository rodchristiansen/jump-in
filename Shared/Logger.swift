//
//  Logger.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 19/02/2025.
//

import Foundation
import os.log

/// A simple logging utility for the macOS Tenant migration application
final class Logger {
    // Shared singleton instance
    static let shared = Logger()
    
    // OSLog subsystem and category
    private let subsystem = "com.IRL.jump-in"
    private let osLog: OSLog
    
    // Log levels
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    // File for log persistence
    private let logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.IRL.jump-in.logger", qos: .utility)
    
    private init() {
        // Create OSLog
        osLog = OSLog(subsystem: subsystem, category: "JUMP-IN")
        
        // Configure date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Setup log file
        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let logDir = appSupportDir.appendingPathComponent("JUMP-IN/Logs")
            
            do {
                try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
                let dateString = ISO8601DateFormatter().string(from: Date())
                logFileURL = logDir.appendingPathComponent("JUMP-IN_\(dateString).log")
            } catch {
                print("Failed to create log directory: \(error)")
                logFileURL = nil
            }
        } else {
            logFileURL = nil
        }
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, file: file, function: function, line: line)
    }
    
    // MARK: - Helper Methods
    
    private func log(_ message: String, level: Level, file: String, function: String, line: Int) {
        // Get filename without path
        let filename = (file as NSString).lastPathComponent
        
        // Format log entry
        let formattedMessage = "\(level.rawValue): \(filename):\(line) - \(function) - \(message)"
        
        // Log to OSLog
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        
        // Also log to file for persistence
        logToFile(formattedMessage)
        
        #if DEBUG
        // Print to console in debug builds
        print(formattedMessage)
        #endif
    }
    
    private func logToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }
        
        logQueue.async {
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] \(message)\n"
            
            if let data = logEntry.data(using: .utf8) {
                if self.fileManager.fileExists(atPath: logFileURL.path) {
                    // Append to existing file
                    if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    // Create new file
                    try? data.write(to: logFileURL)
                }
            }
        }
    }
    
    // Get log file contents for debugging
    func getLogFileContents() -> String? {
        guard let logFileURL = logFileURL else { return nil }
        
        do {
            return try String(contentsOf: logFileURL, encoding: .utf8)
        } catch {
            return "Failed to read log file: \(error)"
        }
    }
}
