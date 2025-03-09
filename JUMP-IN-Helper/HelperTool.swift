//
//  HelperTool.swift
//  JUMP-IN Helper
//

import Foundation
import AppKit

@objc(HelperTool)
final class HelperTool: NSObject, HelperToolProtocol {
    private let version = "1.0"
    private let logger = Logger.shared
    private let backupPath = "/Library/Application Support/JUMP-IN/Backups"
    
    // MARK: - Tenant Operations
    
    func removeCurrentTenantProfile(withReply reply: @escaping (NSError?) -> Void) {
        logger.info("Attempting comprehensive profile removal with elevated privileges")
        
        let script = """
        /usr/bin/profiles list | grep -E '(Microsoft|Intune|windowsintune|mdm)' | while read line; do
            identifier=$(echo "$line" | sed -n 's/.*profileIdentifier: //p')
            if [ ! -z "$identifier" ]; then
                /usr/bin/profiles remove -identifier "$identifier"
            fi
        done
        
        # Aggressive removal fallback
        /usr/bin/profiles -D
        
        # Verify removal
        if /usr/bin/profiles list | grep -E '(Microsoft|Intune|windowsintune)'; then
            exit 1
        fi
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = ["execute-with-privileges", "/bin/bash", "-c", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorStr = String(data: errorData, encoding: .utf8) ?? ""
            
            logger.info("Profile removal output: \(output)")
            
            if task.terminationStatus == 0 {
                logger.info("All Microsoft profiles successfully removed")
                reply(nil)
            } else {
                logger.error("Profile removal failed: \(errorStr)")
                reply(HelperToolError.operationFailed(errorStr) as NSError)
            }
        } catch {
            logger.error("Profile removal process failed: \(error.localizedDescription)")
            reply(HelperToolError.operationFailed(error.localizedDescription) as NSError)
        }
    }
    
    private func extractProfileIdentifiers(from profilesList: String) -> [String] {
        let patterns = [
            "Microsoft.Intune",
            "Microsoft.Profiles",
            "windowsintune",
            "MDM",
            "com.microsoft"
        ]
        
        var identifiers: [String] = []
        
        for line in profilesList.components(separatedBy: .newlines) {
            for pattern in patterns {
                if line.contains(pattern) {
                    if let identifierMatch = line.range(of: "profileIdentifier: (.+)", options: .regularExpression) {
                        let identifier = String(line[identifierMatch])
                        identifiers.append(identifier)
                    }
                }
            }
        }
        
        return identifiers
    }
    
    private func removeProfile(identifier: String) -> (success: Bool, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["remove", "-identifier", identifier]
        
        do {
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus == 0, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    private func verifyProfileRemoval(reply: @escaping (NSError?) -> Void) {
        let verifyProcess = Process()
        verifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        verifyProcess.arguments = ["list"]
        
        do {
            let outputPipe = Pipe()
            verifyProcess.standardOutput = outputPipe
            try verifyProcess.run()
            verifyProcess.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let remainingProfiles = output.contains("Microsoft") ||
                                     output.contains("Intune") ||
                                     output.contains("MDM")
            
            if remainingProfiles {
                logger.warning("Profiles still present after removal attempts")
                reply(HelperToolError.operationFailed("Failed to remove all profiles") as NSError)
            } else {
                logger.info("All profiles successfully removed")
                reply(nil)
            }
        } catch {
            logger.error("Verification process failed: \(error)")
            reply(error as NSError)
        }
    }
    
    func backupTenantSettings(withReply reply: @escaping (String?, NSError?) -> Void) {
        logger.info("Starting backup of current tenant settings")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupDir = "\(backupPath)/\(timestamp)"
        
        do {
            try FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
            
            let profilesProcess = Process()
            profilesProcess.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
            profilesProcess.arguments = ["-P", "-o", "\(backupDir)/profiles.plist"]
            
            let outputPipe = Pipe()
            profilesProcess.standardOutput = outputPipe
            profilesProcess.standardError = outputPipe
            
            try profilesProcess.run()
            profilesProcess.waitUntilExit()
            
            if profilesProcess.terminationStatus == 0 {
                logger.info("Tenant settings backup successful at: \(backupDir)")
                reply(backupDir, nil)
            } else {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                logger.error("Failed to backup profiles: \(output)")
                reply(nil, HelperToolError.operationFailed("Failed to backup profiles: \(output)") as NSError)
            }
        } catch {
            logger.error("Error creating backup directory: \(error.localizedDescription)")
            reply(nil, HelperToolError.operationFailed(error.localizedDescription) as NSError)
        }
    }
    
    func updateCompanyPortal(withReply reply: @escaping (NSError?) -> Void) {
        logger.info("Updating Company Portal application")
        
        let downloadURL = "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/CompanyPortal-Installer.pkg"
        let tempPath = "/private/tmp/CompanyPortal-Installer.pkg"
        
        let downloadProcess = Process()
        downloadProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        downloadProcess.arguments = ["-L", downloadURL, "-o", tempPath]
        
        do {
            try downloadProcess.run()
            downloadProcess.waitUntilExit()
            
            if downloadProcess.terminationStatus == 0 {
                let installProcess = Process()
                installProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
                installProcess.arguments = ["-pkg", tempPath, "-target", "/"]
                
                let outputPipe = Pipe()
                installProcess.standardOutput = outputPipe
                installProcess.standardError = outputPipe
                
                try installProcess.run()
                installProcess.waitUntilExit()
                
                if installProcess.terminationStatus == 0 {
                    logger.info("Company Portal successfully updated")
                    reply(nil)
                } else {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    logger.error("Failed to install Company Portal: \(output)")
                    reply(HelperToolError.operationFailed("Failed to install Company Portal: \(output)") as NSError)
                }
                
                try? FileManager.default.removeItem(atPath: tempPath)
            } else {
                logger.error("Failed to download Company Portal installer")
                reply(HelperToolError.operationFailed("Failed to download Company Portal installer") as NSError)
            }
        } catch {
            logger.error("Error updating Company Portal: \(error.localizedDescription)")
            reply(HelperToolError.operationFailed(error.localizedDescription) as NSError)
        }
    }
    
    func enrollInNewTenant(targetTenant: String, withReply reply: @escaping (NSError?) -> Void) {
        logger.info("Starting enrollment in new Intune tenant: \(targetTenant)")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 30.0) {
            if !FileManager.default.fileExists(atPath: "/Applications/Company Portal.app") {
                self.updateCompanyPortal { error in
                    if let error = error {
                        self.logger.error("Failed to install Company Portal: \(error.localizedDescription)")
                        reply(error)
                    } else {
                        self.startEnrollment(targetTenant: targetTenant, reply: reply)
                    }
                }
            } else {
                self.startEnrollment(targetTenant: targetTenant, reply: reply)
            }
        }
    }
    
    private func startEnrollment(targetTenant: String, reply: @escaping (NSError?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["-N"]
        
        do {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                logger.info("Intune enrollment initiated successfully")
                
                let launchProcess = Process()
                launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                launchProcess.arguments = ["-a", "Company Portal"]
                
                try launchProcess.run()
                launchProcess.waitUntilExit()
                
                if launchProcess.terminationStatus == 0 {
                    logger.info("Company Portal launched for enrollment completion")
                    reply(nil)
                } else {
                    logger.error("Failed to launch Company Portal")
                    reply(HelperToolError.operationFailed("Failed to launch Company Portal") as NSError)
                }
            } else {
                logger.error("Failed to initiate MDM enrollment: \(output)")
                reply(HelperToolError.operationFailed("Failed to initiate MDM enrollment: \(output)") as NSError)
            }
        } catch {
            logger.error("Error during enrollment: \(error.localizedDescription)")
            reply(HelperToolError.operationFailed(error.localizedDescription) as NSError)
        }
    }
    
    func rotateFileVaultKey(withReply reply: @escaping (NSError?) -> Void) {
        logger.info("Starting FileVault key rotation - delegating to user context")
        
        // First check if FileVault is enabled
        let fdeProcess = Process()
        fdeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        fdeProcess.arguments = ["status"]
        
        do {
            let pipe = Pipe()
            fdeProcess.standardOutput = pipe
            
            try fdeProcess.run()
            fdeProcess.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if !output.contains("FileVault is On") {
                logger.warning("FileVault is not enabled, skipping key rotation")
                reply(nil)  // Not treating this as an error, just skipping
                return
            }
            
            logger.info("FileVault is enabled, proceeding with user context rotation")
        } catch {
            logger.error("Failed to check FileVault status: \(error.localizedDescription)")
            reply(HelperToolError.operationFailed("Failed to check FileVault status") as NSError)
            return
        }
        
        // Create a simple script that will execute in user context
        let tempScriptPath = "/private/tmp/fv_rotate_\(UUID().uuidString).sh"
        
        let scriptContent = """
        #!/bin/bash
        
        # Log function to write to both stdout and system log
        log() {
            echo "$1"
            /usr/bin/logger -t "JUMP-IN-FV" "$1"
        }
        
        log "Starting FileVault key rotation in user context"
        
        # Show information dialog to user
        /usr/bin/osascript -e 'display dialog "You will now be prompted for your login password to rotate your FileVault recovery key." buttons {"Continue"} default button "Continue" with icon note' || { 
            log "User declined initial prompt"
            echo "CANCELED: User canceled at initial prompt"
            exit 0
        }
        
        # Execute fdesetup directly - it will show the native macOS credential prompt
        log "Executing fdesetup changerecovery"
        OUTPUT=$(/usr/bin/fdesetup changerecovery -personal 2>&1)
        RESULT=$?
        
        log "fdesetup completed with status $RESULT"
        
        if [ $RESULT -ne 0 ]; then
            if [[ "$OUTPUT" == *"Error: User canceled"* ]]; then
                log "User canceled the operation"
                /usr/bin/osascript -e 'display dialog "FileVault key rotation was canceled." buttons {"OK"} default button "OK" with icon caution'
                echo "CANCELED: User canceled during password entry"
                exit 0
            else
                log "Rotation failed: $OUTPUT"
                /usr/bin/osascript -e 'display dialog "Failed to rotate FileVault key: '"$OUTPUT"'" buttons {"OK"} default button "OK" with icon stop'
                echo "ERROR: $OUTPUT"
                exit 1
            fi
        fi
        
        # Success - show the key to the user
        log "FileVault rotation successful"
        /usr/bin/osascript -e 'display dialog "Your new FileVault recovery key is:\\n\\n'"$OUTPUT"'\\n\\nPlease store this key in a safe place." buttons {"OK"} default button "OK" with icon caution'
        
        echo "SUCCESS: $OUTPUT"
        exit 0
        """
        
        do {
            // Write script to file with executable permissions
            try scriptContent.write(to: URL(fileURLWithPath: tempScriptPath), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)
            
            logger.info("Created FileVault rotation script at \(tempScriptPath)")
            
            // Find the current console user to run the script as
            let userProcess = Process()
            userProcess.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
            userProcess.arguments = ["-f", "%Su", "/dev/console"]
            let userPipe = Pipe()
            userProcess.standardOutput = userPipe
            try userProcess.run()
            userProcess.waitUntilExit()
            let userData = userPipe.fileHandleForReading.readDataToEndOfFile()
            let consoleUser = String(data: userData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            logger.info("Detected console user: \(consoleUser)")
            
            // Create a command that will run the script as the console user
            let runCommand: String
            if consoleUser.isEmpty {
                // No specific user detected, use standard approach
                runCommand = tempScriptPath
            } else {
                // Use launchctl asuser to run in user context
                let uid = try? self.getUserID(username: consoleUser)
                if let uid = uid {
                    runCommand = "/bin/launchctl asuser \(uid) \(tempScriptPath)"
                } else {
                    runCommand = tempScriptPath
                }
            }
            
            // Execute the script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", runCommand]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            logger.info("Executing FileVault rotation command: \(runCommand)")
            try process.run()
            
            // Set up timeout
            let timeoutQueue = DispatchQueue(label: "com.filevault.timeout")
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    self.logger.error("FileVault key rotation timed out after 180 seconds")
                    process.terminate()
                    DispatchQueue.main.async {
                        reply(HelperToolError.timeoutError("FileVault key rotation timed out") as NSError)
                    }
                }
            }
            timeoutQueue.asyncAfter(deadline: .now() + 180, execute: timeoutWorkItem)
            
            // Handle process completion
            process.terminationHandler = { proc in
                timeoutWorkItem.cancel()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                // Clean up
                try? FileManager.default.removeItem(atPath: tempScriptPath)
                
                self.logger.info("FileVault script completed with status: \(proc.terminationStatus)")
                self.logger.info("Output: \(output)")
                if !error.isEmpty {
                    self.logger.error("Error output: \(error)")
                }
                
                DispatchQueue.main.async {
                    if proc.terminationStatus != 0 && !output.contains("CANCELED:") {
                        self.logger.error("FileVault key rotation failed with status: \(proc.terminationStatus)")
                        reply(HelperToolError.operationFailed("FileVault key rotation failed: \(error.isEmpty ? "Unknown error" : error)") as NSError)
                        return
                    }
                    
                    if output.contains("CANCELED:") {
                        self.logger.info("FileVault key rotation was canceled by user")
                        reply(nil) // User cancellation is not treated as an error
                    } else if output.contains("ERROR:") {
                        let errorMessage = output.replacingOccurrences(of: "ERROR: ", with: "")
                        self.logger.error("FileVault key rotation error: \(errorMessage)")
                        reply(HelperToolError.operationFailed(errorMessage) as NSError)
                    } else if output.contains("SUCCESS:") {
                        self.logger.info("FileVault key rotation completed successfully")
                        reply(nil)
                    } else {
                        self.logger.warning("Unexpected output from FileVault script: \(output)")
                        
                        // If exit code is 0, assume success even with unexpected output
                        if proc.terminationStatus == 0 {
                            self.logger.info("Assuming success based on exit code 0")
                            reply(nil)
                        } else {
                            reply(HelperToolError.operationFailed("Unexpected result from FileVault rotation") as NSError)
                        }
                    }
                }
            }
        } catch {
            // Clean up
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            
            logger.error("Failed to create or execute FileVault rotation script: \(error.localizedDescription)")
            reply(HelperToolError.operationFailed("Failed to execute FileVault rotation: \(error.localizedDescription)") as NSError)
        }
    }

    // Helper method to get user ID from username
    private func getUserID(username: String) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        process.arguments = ["-u", username]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let uidString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let uid = Int(uidString) {
            return uid
        }
        
        throw NSError(domain: "HelperToolError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get UID for user \(username)"])
    }
    
    // MARK: - System Requirement Checks
    
    func checkIntuneEnrollment(withReply reply: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["list"]
        
        do {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let isEnrolled = output.contains("Microsoft Intune") ||
                             output.contains("MDM Profile") ||
                             output.contains("Microsoft.Profiles") ||
                             output.contains("Microsoft.Intune")
            
            logger.info("Intune enrollment check: \(isEnrolled)")
            reply(isEnrolled)
        } catch {
            logger.error("Error checking Intune enrollment: \(error.localizedDescription)")
            reply(false)
        }
    }
    
    func getCurrentTenant(withReply reply: @escaping (String?) -> Void) {
        logger.info("Detecting current tenant details")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["show"]
        
        do {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                logger.info("Profiles show output retrieved")
                
                if let range = output.range(of: "attribute: organization: (.+?)$", options: .regularExpression) {
                    let match = output[range]
                    if let orgRange = match.range(of: "organization: (.+)$", options: .regularExpression) {
                        let orgName = String(match[orgRange])
                            .replacingOccurrences(of: "organization: ", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        logger.info("Current tenant organization identified: \(orgName)")
                        reply(orgName)
                        return
                    }
                }
                
                if let range = output.range(of: "Microsoft Intune MDM .* - (.*@.*\\.com)") {
                    let match = output[range]
                    if let emailRange = match.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}") {
                        let tenantIdentifier = String(match[emailRange])
                        logger.info("Current tenant email identified: \(tenantIdentifier)")
                        reply(tenantIdentifier)
                        return
                    }
                }
                
                if let range = output.range(of: "Tenant ID: ([A-Za-z0-9-]+)") {
                    let match = output[range]
                    if let idRange = match.range(of: "[A-Za-z0-9-]{36}") {
                        let tenantId = String(match[idRange])
                        logger.info("Current tenant ID identified: \(tenantId)")
                        reply(tenantId)
                        return
                    }
                }
                
                if output.contains("Microsoft Intune") || output.contains("MDM Profile") {
                    logger.info("Microsoft Intune profile detected but couldn't identify tenant")
                    reply("Microsoft Intune")
                    return
                }
                
                logger.warning("Could not identify current tenant in profiles output")
                reply(nil)
            } else {
                logger.error("Failed to get profiles output")
                reply(nil)
            }
        } catch {
            logger.error("Error getting current tenant: \(error.localizedDescription)")
            reply(nil)
        }
    }
    
    func checkFileVaultStatus(withReply reply: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        
        do {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let isEnabled = output.contains("FileVault is On")
            logger.info("FileVault status: \(isEnabled)")
            reply(isEnabled)
        } catch {
            logger.error("Error checking FileVault status: \(error.localizedDescription)")
            reply(false)
        }
    }
    
    func checkGatekeeperStatus(withReply reply: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--status"]
        
        do {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let isEnabled = output.contains("assessments enabled")
            logger.info("Gatekeeper status: \(isEnabled)")
            reply(isEnabled)
        } catch {
            logger.error("Error checking Gatekeeper status: \(error.localizedDescription)")
            reply(false)
        }
    }
    
    // MARK: - Utility Methods
    
    func getVersionString(withReply reply: @escaping (String) -> Void) {
        reply(version)
    }
    
    func getCurrentUser(withReply reply: @escaping (String) -> Void) {
        let userName = NSUserName()
        reply(userName)
    }
    
    func checkToolVersion(version: String, withReply reply: @escaping (Bool) -> Void) {
        reply(version == self.version)
    }
}
