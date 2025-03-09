import Foundation
import AppKit

class SecureFileVaultManager {
    static let shared = SecureFileVaultManager()
    private let logger = Logger.shared
    
    enum FileVaultError: Error, LocalizedError {
        case fileVaultNotEnabled
        case rotationFailed(String)
        case userCancelled
        case scriptExecutionFailed(String)
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .fileVaultNotEnabled:
                return "FileVault is not enabled on this system"
            case .rotationFailed(let reason):
                return "FileVault key rotation failed: \(reason)"
            case .userCancelled:
                return "FileVault key rotation was cancelled by the user"
            case .scriptExecutionFailed(let reason):
                return "Failed to execute FileVault script: \(reason)"
            case .timeout:
                return "FileVault rotation timed out"
            }
        }
    }
    
    private init() {}
    
    func rotateFileVaultKey() async throws {
        logger.info("Starting FileVault key rotation using AppleScript")
        
        // First check if FileVault is enabled
        guard try await isFileVaultEnabled() else {
            logger.warning("FileVault not enabled, skipping key rotation")
            throw FileVaultError.fileVaultNotEnabled
        }
        
        // AppleScript to show initial prompt
        let initialPromptScript = """
        display dialog "You will now be prompted for your login password to rotate your FileVault recovery key." buttons {"Continue"} default button "Continue" with icon note
        """
        
        // Execute initial prompt
        var error: NSDictionary?
        guard NSAppleScript(source: initialPromptScript)?.executeAndReturnError(&error) != nil else {
            if let error = error {
                logger.warning("User declined initial prompt: \(error)")
            }
            throw FileVaultError.userCancelled
        }
        
        // AppleScript to execute fdesetup with admin privileges
        let fdeSetupScript = """
        do shell script "fdesetup changerecovery -personal" with administrator privileges
        """
        
        // Execute fdesetup
        var scriptError: NSDictionary?
        let scriptResult = NSAppleScript(source: fdeSetupScript)?.executeAndReturnError(&scriptError)
        
        if let scriptError = scriptError {
            let errorMessage = scriptError["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            logger.error("FileVault rotation failed: \(errorMessage)")
            
            // Show error dialog
            let errorScript = """
            display dialog "Failed to rotate FileVault key: \(errorMessage)" buttons {"OK"} default button "OK" with icon stop
            """
            NSAppleScript(source: errorScript)?.executeAndReturnError(nil)
            
            throw FileVaultError.rotationFailed(errorMessage)
        }
        
        if let result = scriptResult?.stringValue, !result.isEmpty {
            // Show success dialog with recovery key
            let successScript = """
            display dialog "Your new FileVault recovery key is:\\n\\n\(result)\\n\\nPlease store this key in a safe place." buttons {"OK"} default button "OK" with icon caution
            """
            NSAppleScript(source: successScript)?.executeAndReturnError(nil)
            
            logger.info("FileVault key rotation completed successfully")
        } else {
            logger.warning("No recovery key returned but operation succeeded")
        }
    }
    
    func isFileVaultEnabled() async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.contains("FileVault is On")
    }
}
