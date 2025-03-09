import Foundation
import AppKit

enum PrivilegedServiceError: Error {
    case scriptExecutionFailed(String)
    case commandFailed(String)
    case invalidResponse
    case notRunningAsRoot
    case privilegeElevationFailed
}

final class PrivilegedService {
    static let shared = PrivilegedService()
    private let logger = Logger.shared
    private let companyPortalURL = "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/CompanyPortal-Installer.pkg"
    
    var isRunningAsRoot: Bool {
        return getuid() == 0
    }
    
    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    // Removed the async Task call from here
    private init() {
        // Empty to avoid concurrency calls at static initialization
    }
    
    /// Call this from applicationDidFinishLaunching (or similar) to do the async setup
    func startService() {
        Task {
            await verifyPrivileges()
        }
    }
    
    private func verifyPrivileges() async {
        if !isRunningAsRoot {
            logger.info("Starting privilege verification...")
            
            #if DEBUG
            do {
                if try await requestPrivileges() {
                    logger.info("Successfully obtained privileges in debug mode")
                    return
                }
            } catch {
                logger.error("Failed to obtain privileges in debug mode: \(error.localizedDescription)")
            }
            #else
            // In production, check if we're root
            if !isRunningAsRoot {
                logger.error("Not running as root in production mode")
                return
            }
            #endif
            
            logger.error("Failed to obtain required privileges")
        } else {
            logger.info("✅ Already running with root privileges")
        }
    }
    
    func executeCommand(_ command: String, requireRoot: Bool = true, useAdmin: Bool = false) async throws -> String {
        // Log each command execution with clear parameters
        logger.info("Executing command: \(command)")
        logger.info("Parameters: requireRoot=\(requireRoot), useAdmin=\(useAdmin)")
        
        // Check for root requirement in production
        if requireRoot && !isRunningAsRoot && !isDebugBuild {
            logger.error("Root privileges required but not available")
            throw PrivilegedServiceError.notRunningAsRoot
        }
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Determine execution mode
        if isDebugBuild && !isRunningAsRoot && requireRoot {
            // In debug mode, use sudo or admin privileges
            if useAdmin {
                let script = """
                osascript -e 'do shell script "\(command.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges'
                """
                logger.info("Using admin privileges with osascript")
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
            } else {
                logger.info("Using sudo for privileges")
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-S", "/bin/bash", "-c", command]
            }
        } else {
            // Direct execution
            logger.info("Using direct execution")
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
        }
        
        do {
            logger.info("Starting process execution")
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            logger.info("Process exited with status: \(process.terminationStatus)")
            
            if !output.isEmpty {
                if output.count > 500 {
                    logger.info("Command output (truncated): \(output.prefix(500))...")
                } else {
                    logger.info("Command output: \(output)")
                }
            }
            
            if !error.isEmpty {
                logger.warning("Command stderr output: \(error)")
            }
            
            if process.terminationStatus != 0 {
                logger.error("Command failed with status \(process.terminationStatus): \(error)")
                throw PrivilegedServiceError.commandFailed(error)
            }
            
            return output
            
        } catch let error as PrivilegedServiceError {
            logger.error("Privileged service error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Command execution failed: \(error.localizedDescription)")
            throw PrivilegedServiceError.scriptExecutionFailed(error.localizedDescription)
        }
    }
    
    func requestPrivileges() async throws -> Bool {
        if isRunningAsRoot {
            return true
        }
        
        #if DEBUG
        // In debug mode, show authentication dialog
        do {
            let authenticated = try await showAuthenticationDialog()
            if authenticated {
                // Test privileges after authentication
                let result = try await executeCommand("echo 'privilege test'", requireRoot: true)
                return !result.isEmpty
            }
            return false
        } catch {
            logger.error("Failed to get privileges: \(error.localizedDescription)")
            return false
        }
        #else
        // In production, we should already be root
        return isRunningAsRoot
        #endif
    }
    
    private func showAuthenticationDialog() async throws -> Bool {
        let script = """
        do shell script "echo 'Authentication successful'" with administrator privileges with prompt "Tenant Switch requires administrator privileges to perform the migration."
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script),
           appleScript.executeAndReturnError(&error) != nil {
            return true
        } else if let error = error {
            logger.error("Authentication failed: \(error)")
            throw PrivilegedServiceError.privilegeElevationFailed
        }
        return false
    }
    
    func testPrivileges() async throws -> Bool {
        do {
            let whoami = try await executeCommand("whoami", requireRoot: false)
            let currentUser = whoami.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Running as user: \(currentUser)")
            return currentUser == "root"
        } catch {
            logger.error("Privilege test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func getCurrentUser() async throws -> String {
        let output = try await executeCommand("whoami", requireRoot: false)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func getCurrentTenant() async throws -> String? {
        let output = try await executeCommand("profiles list | grep -E '(Microsoft|Intune|Tenant)'", requireRoot: true)
        
        // Check for tenant identifier in profile descriptions
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for email domain patterns
            if let range = line.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) {
                let tenantEmail = String(line[range])
                logger.info("Detected tenant email: \(tenantEmail)")
                return tenantEmail
            }
            // Look for tenant ID pattern
            if let range = line.range(of: "Tenant ID: ([a-zA-Z0-9-]+)", options: .regularExpression) {
                if let idRange = line[range].range(of: "[a-zA-Z0-9-]{36}", options: .regularExpression) {
                    let tenantId = String(line[range][idRange])
                    logger.info("Detected tenant ID: \(tenantId)")
                    return tenantId
                }
                let tenantInfo = String(line[range])
                logger.info("Detected tenant info: \(tenantInfo)")
                return tenantInfo
            }
            // Organization name
            if line.contains("Microsoft Intune MDM") && line.contains("- ") {
                if let orgRange = line.range(of: "- ([^-]+)$", options: .regularExpression) {
                    let orgName = line[orgRange].trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "- ", with: "")
                    logger.info("Detected organization: \(orgName)")
                    return orgName
                }
            }
        }
        
        return nil
    }
    
    func removeCurrentTenantProfile() async throws {
        logger.info("Starting current tenant profile removal")
        
        // Get current tenant for logging
        if let tenant = try? await getCurrentTenant() {
            logger.info("Removing tenant profile: \(tenant)")
        }
        
        // One-liner command to remove all profiles
        let removeCommand = "profiles list | awk '/profileIdentifier:/ {print $2}' | xargs -I {} profiles remove -identifier {}"
        try await executeCommand(removeCommand, requireRoot: true)
        
        // Wait for profile removal
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify
        let profilesOutput = try await executeCommand("profiles list", requireRoot: true)
        if profilesOutput.contains("Microsoft") || profilesOutput.contains("Intune") {
            logger.error("Intune profile still present after removal")
            throw PrivilegedServiceError.commandFailed("Intune profile still present after removal attempt")
        }
        
        logger.info("Current tenant profile successfully removed")
    }
    
    func installCompanyPortal() async throws {
        logger.info("Checking Company Portal installation")
        
        // Check if already installed
        let exists = try await executeCommand("test -d '/Applications/Company Portal.app' && echo 'yes' || echo 'no'", requireRoot: false)
        if exists.contains("yes") {
            logger.info("Company Portal is already installed")
            return
        }
        
        logger.info("Downloading and installing Company Portal")
        
        let installCommand = """
        curl -L '\(companyPortalURL)' -o /private/tmp/CompanyPortal.pkg && \
        installer -pkg /private/tmp/CompanyPortal.pkg -target / && \
        rm /private/tmp/CompanyPortal.pkg
        """
        
        try await executeCommand(installCommand, requireRoot: true)
        
        // Verify
        let verifyInstall = try await executeCommand("test -d '/Applications/Company Portal.app' && echo 'yes' || echo 'no'", requireRoot: false)
        if !verifyInstall.contains("yes") {
            logger.error("Company Portal installation verification failed")
            throw PrivilegedServiceError.commandFailed("Company Portal installation verification failed")
        }
        
        logger.info("Company Portal successfully installed")
    }
    

    
    func enrollInIntune() async throws {
        logger.info("Starting Intune enrollment")
        
        // First ensure Company Portal is installed
        if !FileManager.default.fileExists(atPath: "/Applications/Company Portal.app") {
            try await installCompanyPortal()
        }
        
        // Wait for 30 seconds before enrollment (as recommended)
        logger.info("Waiting 30 seconds before starting enrollment...")
        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
        
        // Execute enrollment
        let enrollResult = try await executeCommand("profiles -N", requireRoot: true)
        logger.info("Enrollment command result: \(enrollResult)")
        
        // Launch Company Portal
        try await executeCommand("open -a 'Company Portal'", requireRoot: false)
        logger.info("Company Portal launched for enrollment completion")
        
        // Wait for enrollment
        var enrolled = false
        var retryCount = 0
        let maxRetries = 60 // 1 minute total
        
        while !enrolled && retryCount < maxRetries {
            let profilesOutput = try await executeCommand("profiles show -all", requireRoot: true)
            if profilesOutput.contains("Microsoft.Profiles.") || profilesOutput.contains("Microsoft.Profiles.MDM") {
                enrolled = true
                break
            }
            
            retryCount += 1
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        if !enrolled {
            logger.warning("Enrollment verification timed out - continuing without confirmation")
        } else {
            logger.info("Intune enrollment completed successfully")
        }
    }
    
    func enrollInNewTenant(targetTenant: String) async throws {
        logger.info("Starting enrollment in new Intune tenant: \(targetTenant)")
        
        // Ensure Company Portal is installed
        if !FileManager.default.fileExists(atPath: "/Applications/Company Portal.app") {
            try await installCompanyPortal()
        }
        
        // Execute enrollment using profiles command
        try await enrollInIntune()
        
        logger.info("Tenant enrollment completed for: \(targetTenant)")
    }
    
    func backupTenantSettings() async throws -> String {
        logger.info("Backing up current tenant settings")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupDir = "/Library/Application Support/JUMP-IN/Backups/\(timestamp)"
        
        // Create backup directory
        try await executeCommand("mkdir -p '\(backupDir)'", requireRoot: true)
        
        // Export profiles
        try await executeCommand("profiles -P -o '\(backupDir)/profiles.plist'", requireRoot: true)
        
        // Export MDM enrollment info if available
        _ = try? await executeCommand("profiles -e '\(backupDir)/mdm_enrollment.plist'", requireRoot: true)
        
        // Save current tenant info
        if let tenant = try? await getCurrentTenant() {
            let tenantInfoCommand = """
            echo "Current tenant: \(tenant)" > '\(backupDir)/tenant_info.txt'
            date >> '\(backupDir)/tenant_info.txt'
            """
            try await executeCommand(tenantInfoCommand, requireRoot: true)
        }
        
        logger.info("Tenant settings backed up to: \(backupDir)")
        return backupDir
    }
}
