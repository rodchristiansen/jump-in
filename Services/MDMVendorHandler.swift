//
//  MDMVendorHandler.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 03/03/2025.
//

import Foundation

/// Protocol for MDM vendor-specific handlers
protocol MDMVendorHandlerProtocol {
    /// The vendor info this handler is associated with
    var vendorInfo: MDMVendorInfo { get }
    
    /// Remove the MDM profiles and management
    func removeProfiles() async throws -> Bool
    
    /// Backup the MDM configuration before removal
    func backupConfiguration() async throws -> String?
    
    /// Perform any vendor-specific pre-migration tasks
    func performPreMigrationTasks() async throws
    
    /// Handle any vendor-specific post-migration tasks
    func performPostMigrationTasks() async throws
    
    /// Check if unenrollment was successful
    func verifyUnenrollment() async -> Bool
}

/// Factory for creating vendor-specific handlers
class MDMVendorHandlerFactory {
    private let logger = Logger.shared
    
    /// Create appropriate handler for the detected MDM vendor
    static func createHandler(for vendorInfo: MDMVendorInfo) -> MDMVendorHandlerProtocol {
        switch vendorInfo.identifier {
            case "jamf":
                return JamfVendorHandler(vendorInfo: vendorInfo)
            case "kandji":
                return KandjiVendorHandler(vendorInfo: vendorInfo)
            case "mosyle":
                return MosyleVendorHandler(vendorInfo: vendorInfo)
            case "workspace":
                return WorkspaceOneVendorHandler(vendorInfo: vendorInfo)
            case "intune", "microsoft":
                return IntuneVendorHandler(vendorInfo: vendorInfo)
            default:
                return GenericMDMVendorHandler(vendorInfo: vendorInfo)
        }
    }
}

/// Base implementation for vendor handlers
class BaseMDMVendorHandler: MDMVendorHandlerProtocol {
    let vendorInfo: MDMVendorInfo
    let privilegedService = PrivilegedService.shared
    let logger = Logger.shared
    let vendorRegistry = MDMVendorRegistry.shared
    
    init(vendorInfo: MDMVendorInfo) {
        self.vendorInfo = vendorInfo
        logger.info("Created handler for \(vendorInfo.displayName)")
    }
    
    func removeProfiles() async throws -> Bool {
        logger.info("Removing MDM profiles for \(vendorInfo.displayName)")
        
        // Get vendor-specific removal commands
        let removalCommands = vendorRegistry.getRemovalCommands(forVendor: vendorInfo.identifier)
        
        for command in removalCommands {
            do {
                let result = try await privilegedService.executeCommand(command, requireRoot: true)
                logger.info("Executed removal command: \(command), result: \(result)")
            } catch {
                logger.warning("Command failed: \(command), error: \(error.localizedDescription)")
                // Continue with next command even if this one failed
            }
        }
        
        // Verify removal
        return await verifyUnenrollment()
    }
    
    func backupConfiguration() async throws -> String? {
        logger.info("Backing up MDM configuration for \(vendorInfo.displayName)")
        
        // Create backup directory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupDir = "/Library/Application Support/JUMP-IN/Backups/\(vendorInfo.identifier)_\(timestamp)"
        
        do {
            // Create backup directory
            try await privilegedService.executeCommand("mkdir -p '\(backupDir)'", requireRoot: true)
            
            // Backup profiles
            try await privilegedService.executeCommand("profiles -P -o '\(backupDir)/profiles.plist'", requireRoot: true)
            
            // Backup MDM-specific info if known
            try await backupVendorSpecificData(to: backupDir)
            
            logger.info("MDM configuration backed up to \(backupDir)")
            return backupDir
        } catch {
            logger.error("Failed to backup configuration: \(error.localizedDescription)")
            return nil
        }
    }
    
    func backupVendorSpecificData(to backupDir: String) async throws {
        // Base implementation just saves the vendor info
        let vendorInfoJSON = """
        {
            "identifier": "\(vendorInfo.identifier)",
            "displayName": "\(vendorInfo.displayName)",
            "version": "\(vendorInfo.version ?? "unknown")",
            "managementType": "\(vendorInfo.managementType)"
        }
        """
        
        let infoPath = "\(backupDir)/vendor_info.json"
        try await privilegedService.executeCommand("echo '\(vendorInfoJSON)' > '\(infoPath)'", requireRoot: true)
    }
    
    func performPreMigrationTasks() async throws {
        logger.info("Performing pre-migration tasks for \(vendorInfo.displayName)")
        // Base implementation does nothing
    }
    
    func performPostMigrationTasks() async throws {
        logger.info("Performing post-migration tasks for \(vendorInfo.displayName)")
        // Base implementation does nothing
    }
    
    func verifyUnenrollment() async -> Bool {
        logger.info("Verifying unenrollment from \(vendorInfo.displayName)")
        
        do {
            // Check if any profiles matching this vendor remain
            let profilesOutput = try await privilegedService.executeCommand("profiles list", requireRoot: true)
            
            for identifier in vendorInfo.profileIdentifiers {
                if profilesOutput.contains(identifier) {
                    logger.warning("MDM profile still present: \(identifier)")
                    return false
                }
            }
            
            // Check if any MDM agent processes are still running
            if let vendorDef = vendorRegistry.getVendor(identifier: vendorInfo.identifier) {
                for agentPath in vendorDef.agentPaths {
                    if FileManager.default.fileExists(atPath: agentPath) {
                        logger.warning("MDM agent still present: \(agentPath)")
                        return false
                    }
                }
            }
            
            logger.info("Verification successful - no MDM profiles or agents detected")
            return true
        } catch {
            logger.error("Failed to verify unenrollment: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Vendor-Specific Handlers

/// Handler for Jamf Pro
class JamfVendorHandler: BaseMDMVendorHandler {
    override func removeProfiles() async throws -> Bool {
        logger.info("Removing Jamf Pro MDM enrollment")
        
        // First try the jamf binary removeFramework if available
        let jamfPaths = ["/usr/local/bin/jamf", "/usr/local/jamf/bin/jamf"]
        var jamfBinaryFound = false
        
        for path in jamfPaths where FileManager.default.fileExists(atPath: path) {
            jamfBinaryFound = true
            do {
                try await privilegedService.executeCommand("\(path) removeFramework", requireRoot: true)
                logger.info("Successfully executed jamf removeFramework")
            } catch {
                logger.warning("jamf removeFramework failed: \(error.localizedDescription)")
            }
            
            // Also try removing MDM enrollment specifically
            do {
                try await privilegedService.executeCommand("\(path) removeMdmProfile", requireRoot: true)
                logger.info("Successfully executed jamf removeMdmProfile")
            } catch {
                logger.warning("jamf removeMdmProfile failed: \(error.localizedDescription)")
            }
        }
        
        // If jamf binary not found or removal failed, try generic approach
        if !jamfBinaryFound {
            logger.warning("Jamf binary not found, using generic profile removal")
            try await super.removeProfiles()
        }
        
        // Remove any Jamf LaunchDaemons
        try? await privilegedService.executeCommand("rm -f /Library/LaunchDaemons/com.jamf*.plist", requireRoot: true)
        
        // Clean up Jamf directories
        try? await privilegedService.executeCommand("rm -rf /Library/Application\\ Support/JAMF", requireRoot: true)
        try? await privilegedService.executeCommand("rm -rf /usr/local/jamf", requireRoot: true)
        
        return await verifyUnenrollment()
    }
    
    override func backupVendorSpecificData(to backupDir: String) async throws {
        // Backup Jamf plist configuration
        if FileManager.default.fileExists(atPath: "/Library/Preferences/com.jamfsoftware.jamf.plist") {
            try await privilegedService.executeCommand("cp /Library/Preferences/com.jamfsoftware.jamf.plist '\(backupDir)/jamf_config.plist'", requireRoot: true)
        }
        
        // Backup Jamf binary version
        let jamfPaths = ["/usr/local/bin/jamf", "/usr/local/jamf/bin/jamf"]
        for path in jamfPaths where FileManager.default.fileExists(atPath: path) {
            try await privilegedService.executeCommand("\(path) version > '\(backupDir)/jamf_version.txt'", requireRoot: true)
            break
        }
        
        // Call super implementation for basic vendor info
        try await super.backupVendorSpecificData(to: backupDir)
    }
    
    override func verifyUnenrollment() async -> Bool {
        // Check if Jamf binary is still present
        let jamfPaths = ["/usr/local/bin/jamf", "/usr/local/jamf/bin/jamf"]
        for path in jamfPaths where FileManager.default.fileExists(atPath: path) {
            logger.warning("Jamf binary still present at \(path)")
            return false
        }
        
        // Check if Jamf directories still exist
        if FileManager.default.fileExists(atPath: "/Library/Application Support/JAMF") ||
           FileManager.default.fileExists(atPath: "/usr/local/jamf") {
            logger.warning("Jamf directories still present")
            return false
        }
        
        // Check MDM profiles using parent implementation
        return await super.verifyUnenrollment()
    }
}

/// Handler for Kandji MDM
class KandjiVendorHandler: BaseMDMVendorHandler {
    override func removeProfiles() async throws -> Bool {
        logger.info("Removing Kandji MDM enrollment")
        
        // Remove Kandji profiles first
        for identifier in vendorInfo.profileIdentifiers {
            try? await privilegedService.executeCommand("profiles remove -identifier '\(identifier)'", requireRoot: true)
        }
        
        // Stop Kandji services
        try? await privilegedService.executeCommand("launchctl unload /Library/LaunchDaemons/io.kandji.*.plist", requireRoot: true)
        
        // Remove Kandji agent
        try? await privilegedService.executeCommand("rm -rf /Library/Kandji", requireRoot: true)
        
        // Use generic profile removal as a final step
        try await super.removeProfiles()
        
        return await verifyUnenrollment()
    }
    
    override func backupVendorSpecificData(to backupDir: String) async throws {
        // Backup Kandji agent configuration
        if FileManager.default.fileExists(atPath: "/Library/Kandji") {
            try await privilegedService.executeCommand("mkdir -p '\(backupDir)/kandji'", requireRoot: true)
            try await privilegedService.executeCommand("cp -r /Library/Kandji/config* '\(backupDir)/kandji/' 2>/dev/null || true", requireRoot: true)
        }
        
        // Backup Kandji launch daemons
        try await privilegedService.executeCommand("mkdir -p '\(backupDir)/launchdaemons'", requireRoot: true)
        try await privilegedService.executeCommand("cp /Library/LaunchDaemons/io.kandji.*.plist '\(backupDir)/launchdaemons/' 2>/dev/null || true", requireRoot: true)
        
        // Call super implementation
        try await super.backupVendorSpecificData(to: backupDir)
    }
}

/// Handler for Mosyle MDM
class MosyleVendorHandler: BaseMDMVendorHandler {
    override func removeProfiles() async throws -> Bool {
        logger.info("Removing Mosyle MDM enrollment")
        
        // Remove Mosyle profiles
        for identifier in vendorInfo.profileIdentifiers {
            try? await privilegedService.executeCommand("profiles remove -identifier '\(identifier)'", requireRoot: true)
        }
        
        // Stop Mosyle services
        try? await privilegedService.executeCommand("launchctl unload /Library/LaunchDaemons/com.mosyle.*.plist", requireRoot: true)
        
        // Remove Mosyle directories
        try? await privilegedService.executeCommand("rm -rf /Library/Application\\ Support/Mosyle", requireRoot: true)
        try? await privilegedService.executeCommand("rm -rf /Library/Mosyle", requireRoot: true)
        
        // Use generic profile removal as a final step
        try await super.removeProfiles()
        
        return await verifyUnenrollment()
    }
}

/// Handler for VMware Workspace ONE
class WorkspaceOneVendorHandler: BaseMDMVendorHandler {
    override func removeProfiles() async throws -> Bool {
        logger.info("Removing VMware Workspace ONE enrollment")
        
        // Check for Hub app
        if FileManager.default.fileExists(atPath: "/Applications/Workspace ONE Intelligent Hub.app") {
            // Try using Hub to unenroll
            try? await privilegedService.executeCommand("open -a '/Applications/Workspace ONE Intelligent Hub.app' --args -unenroll", requireRoot: false)
            
            // Wait for unenrollment process to complete
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        }
        
        // Remove AirWatch/Workspace profiles
        for identifier in vendorInfo.profileIdentifiers {
            try? await privilegedService.executeCommand("profiles remove -identifier '\(identifier)'", requireRoot: true)
        }
        
        // Stop AirWatch/Workspace services
        try? await privilegedService.executeCommand("launchctl unload /Library/LaunchDaemons/com.air-watch.*.plist", requireRoot: true)
        try? await privilegedService.executeCommand("launchctl unload /Library/LaunchDaemons/com.vmware.*.plist", requireRoot: true)
        
        // Remove AirWatch/Workspace directories
        try? await privilegedService.executeCommand("rm -rf /Library/Application\\ Support/AirWatch", requireRoot: true)
        try? await privilegedService.executeCommand("rm -rf /Library/Application\\ Support/VMware", requireRoot: true)
        
        // Generic profile removal as fallback
        try await super.removeProfiles()
        
        return await verifyUnenrollment()
    }
    
    override func verifyUnenrollment() async -> Bool {
        logger.info("Verifying VMware Workspace ONE unenrollment")
        
        do {
            // Check if any AirWatch or VMware identifiers remain in profiles
            let profilesOutput = try await privilegedService.executeCommand("profiles list", requireRoot: true)
            
            let airwatchPatterns = [
                "AirWatch",
                "Airwatch",
                "com.airwatch",
                "com.air-watch",
                "VMware",
                "Workspace ONE",
                "Intelligent Hub"
            ]
            
            for pattern in airwatchPatterns {
                if profilesOutput.contains(pattern) {
                    logger.warning("Workspace ONE profile still present: \(pattern)")
                    return false
                }
            }
            
            // Check enrollment status for Airwatch server
            let enrollmentOutput = try await privilegedService.executeCommand("profiles status -type enrollment", requireRoot: true)
            if enrollmentOutput.contains("awmdm.com") {
                logger.warning("Still enrolled in Workspace ONE (awmdm.com server)")
                return false
            }
            
            // Check for AirWatch directories and apps
            let airwatchPaths = [
                "/Applications/Workspace ONE Intelligent Hub.app",
                "/Applications/VMware AirWatch Agent.app",
                "/Library/Application Support/AirWatch",
                "/Library/Application Support/VMware"
            ]
            
            for path in airwatchPaths where FileManager.default.fileExists(atPath: path) {
                logger.warning("Workspace ONE component still present: \(path)")
                return false
            }
            
            logger.info("Workspace ONE unenrollment verification successful")
            return true
        } catch {
            logger.error("Failed to verify Workspace ONE unenrollment: \(error.localizedDescription)")
            return false
        }
    }
}

/// Handler for Microsoft Intune
class IntuneVendorHandler: BaseMDMVendorHandler {
    override func removeProfiles() async throws -> Bool {
        logger.info("Removing Microsoft Intune enrollment")
        
        // Remove Intune profiles
        for identifier in vendorInfo.profileIdentifiers {
            try? await privilegedService.executeCommand("profiles remove -identifier '\(identifier)'", requireRoot: true)
        }
        
        // Try using privileged service
        do {
            try await privilegedService.executeCommand("profiles -D", requireRoot: true)
            logger.info("Successfully removed profiles with aggressive approach")
        } catch {
            logger.warning("Failed to remove profiles: \(error.localizedDescription)")
        }
        
        return await verifyUnenrollment()
    }
    
    override func verifyUnenrollment() async -> Bool {
        do {
            let profilesOutput = try await privilegedService.executeCommand("profiles list", requireRoot: true)
            
            let intunePatterns = [
                "Microsoft.Intune",
                "Microsoft.Profiles",
                "com.microsoft.enterprise",
                "com.microsoft.intune"
            ]
            
            for pattern in intunePatterns {
                if profilesOutput.contains(pattern) {
                    logger.warning("Intune profile still present: \(pattern)")
                    return false
                }
            }
            
            logger.info("Verification successful - no Intune profiles detected")
            return true
        } catch {
            logger.error("Failed to verify Intune unenrollment: \(error.localizedDescription)")
            return false
        }
    }
}

/// Generic handler for other MDM vendors
class GenericMDMVendorHandler: BaseMDMVendorHandler {
    // Uses the base implementation
}
