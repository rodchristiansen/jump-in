import Foundation

class PrivilegedTaskManager {
    static let shared = PrivilegedTaskManager()
    private let logger = Logger.shared
    
    private init() {}
    
    func executeWithPrivileges(command: String, args: [String] = []) async throws -> String {
        // Check if already running as root
        if getuid() == 0 {
            return try await executeCommand(command, args: args)
        }
        
        // Use authenticated execution
        return try await executeWithAuthentication(command: command, args: args)
    }
    
    private func executeCommand(_ command: String, args: [String]) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "PrivilegedTaskManager",
                         code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        return output
    }
    
    private func executeWithAuthentication(command: String, args: [String]) async throws -> String {
        // Build the full command
        let fullCommand = ([command] + args).joined(separator: " ")
        let escapedCommand = fullCommand.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Use Process to run osascript more reliably
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escapedCommand)\" with administrator privileges"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "PrivilegedTaskManager",
                         code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        return output
    }
}
