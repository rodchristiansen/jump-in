import Foundation

/**
 Manager class for script-based migration operations.
 This is a standalone class that works with your existing architecture
 without needing to access private members.
 */
class ScriptMigrationManager {
    static let shared = ScriptMigrationManager()
    
    private let logger = Logger.shared
    private let mdmDetectionService = MDMDetectionService.shared
    
    // Enum representing operations that can be performed by the script
    enum ScriptOperation: String {
        case fullMigration = "--full-migration"
        case detectMDM = "--detect-mdm"
        case backupOnly = "--backup-only"
        case removeOnly = "--remove-only"
        case updateCompanyPortal = "--update-cp-only"
        case rotateFileVault = "--rotate-fv-only"
        case enrollTenant = "--enroll-only"
        case checkStatus = "--check-status"
    }
    
    /**
     Execute the migration script based on current privileges
     */
    func executeScriptSafely(operation: ScriptOperation, targetTenant: String? = nil, sourceMDM: String? = nil, useUI: Bool = false) async throws -> String {
        // Check if running with admin privileges
        if getuid() == 0 {
            // We have admin privileges, execute directly
            return try await executeScriptDirectly(operation: operation, targetTenant: targetTenant, sourceMDM: sourceMDM, useUI: useUI)
        } else {
            // Need elevated privileges
            return try await executeScriptWithPrivileges(operation: operation, targetTenant: targetTenant, sourceMDM: sourceMDM, useUI: useUI)
        }
    }
    
    /**
     Executes the tenant migration script directly (when already running with admin privileges)
     */
    func executeScriptDirectly(operation: ScriptOperation, targetTenant: String? = nil, sourceMDM: String? = nil, useUI: Bool = false) async throws -> String {
        logger.info("Executing migration script directly")
        
        // Skip if the script file doesn't exist in the bundle
        guard let scriptURL = Bundle.main.url(forResource: "tenant_migration", withExtension: "sh") else {
            throw NSError(domain: "ScriptMigrationManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Migration script not found in bundle"])
        }
        
        // Create a temporary directory for our script
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Copy the script to the temp directory
        let tempScriptURL = tempDir.appendingPathComponent("tenant_migration.sh")
        try FileManager.default.copyItem(at: scriptURL, to: tempScriptURL)
        
        // Set execute permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
        
        // Build the command to execute
        var arguments = [operation.rawValue]
        
        if !useUI {
            arguments.append("--no-ui")
        }
        
        if let tenant = targetTenant, !tenant.isEmpty {
            arguments.append("--target-tenant")
            arguments.append(tenant)
        }
        
        if let mdm = sourceMDM, !mdm.isEmpty {
            arguments.append("--source-mdm")
            arguments.append(mdm)
        }
        
        // Since we're already running with admin privileges, use the script directly
        let process = Process()
        process.executableURL = tempScriptURL
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the process
        try process.run()
        process.waitUntilExit()
        
        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
        
        // Check result
        if process.terminationStatus != 0 {
            logger.error("Script execution failed: \(errorOutput)")
            throw NSError(domain: "ScriptMigrationManager", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Script execution failed: \(errorOutput)"])
        }
        
        logger.info("Script execution completed successfully")
        return output
    }
    
    /**
     Executes the script with administrator privileges (when not already running as admin)
     */
    func executeScriptWithPrivileges(operation: ScriptOperation, targetTenant: String? = nil, sourceMDM: String? = nil, useUI: Bool = false, timeout: TimeInterval = 30) async throws -> String {
        logger.info("Executing migration script with privileges")
        
        // Create temp script
        let scriptContent = """
        #!/bin/bash
        
        # This is a wrapper script that will execute the migration script with administrator privileges
        
        # Path to the migration script in the app bundle
        SCRIPT_PATH="\(Bundle.main.bundlePath)/Contents/Resources/tenant_migration.sh"
        
        # If script doesn't exist in the bundle, exit
        if [ ! -f "$SCRIPT_PATH" ]; then
            echo "Migration script not found in bundle"
            exit 1
        fi
        
        # Copy to temp location
        TEMP_SCRIPT="/private/tmp/tenant_migration_\(UUID().uuidString).sh"
        cp "$SCRIPT_PATH" "$TEMP_SCRIPT"
        chmod 755 "$TEMP_SCRIPT"
        
        # Build command with all parameters
        CMD="$TEMP_SCRIPT \(operation.rawValue) \(useUI ? "" : "--no-ui")"
        
        # Add target tenant if provided
        if [ -n "\(targetTenant ?? "")" ]; then
            CMD="$CMD --target-tenant \"\(targetTenant ?? "")\""
        fi
        
        # Add source MDM if provided
        if [ -n "\(sourceMDM ?? "")" ]; then
            CMD="$CMD --source-mdm \"\(sourceMDM ?? "")\""
        fi
        
        # Execute the script with sudo
        sudo $CMD
        
        # Clean up
        rm -f "$TEMP_SCRIPT"
        """
        
        // Save to temp file
        let wrapperPath = "/private/tmp/migration_wrapper_\(UUID().uuidString).sh"
        try scriptContent.write(toFile: wrapperPath, atomically: true, encoding: .utf8)
        
        // Make executable
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["755", wrapperPath]
        try chmodProcess.run()
        chmodProcess.waitUntilExit()
        
        // Use Process instead of NSAppleScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(wrapperPath)\" with administrator privileges"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Add a timeout
        let timeoutTask = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                self.logger.error("Script execution timed out after \(timeout) seconds")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Cancel timeout task if process completed
            timeoutTask.cancel()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Clean up
            try? FileManager.default.removeItem(atPath: wrapperPath)
            
            if process.terminationStatus != 0 {
                if process.terminationStatus == 15 { // SIGTERM
                    throw NSError(domain: "ScriptMigrationManager", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "Script execution timed out"])
                } else {
                    throw NSError(domain: "ScriptMigrationManager", code: Int(process.terminationStatus),
                                 userInfo: [NSLocalizedDescriptionKey: "Script execution failed: \(errorOutput)"])
                }
            }
            
            logger.info("Script execution with privileges completed")
            return output
        } catch {
            // Clean up on error
            try? FileManager.default.removeItem(atPath: wrapperPath)
            throw error
        }
    }
    
    /**
     Detect MDM vendor using script
     */
    func detectMDMVendor() async throws -> String {
        // 1. Run profiles show
        let output = try await executeScriptSafely(operation: .detectMDM)

        // 2. Check for "No configuration profiles installed"
        if output.contains("No configuration profiles installed") {
            return "none"
        }

        // 3. Otherwise, parse only lines with `profileIdentifier:`
        let lines = output.components(separatedBy: .newlines)
        for line in lines where line.contains("profileIdentifier:") {
            if line.range(of: "(Microsoft|Intune|Tenant)", options: .regularExpression) != nil {
                return "com.microsoft.intune" // or any suitable identifier
            }
        }
        return "none"
    }
    
    
    /**
     Enhanced profile removal using the script
     */
    func removeProfilesWithScript() async throws {
        // First detect MDM vendor
        let mdmVendor = await mdmDetectionService.detectPrimaryMDM()
        
        _ = try await executeScriptSafely(
            operation: .removeOnly,
            sourceMDM: mdmVendor.identifier
        )
    }
    
    /**
     Enhanced FileVault key rotation using the script
     */
    func rotateFileVaultKeyWithScript() async throws {
        _ = try await executeScriptSafely(operation: .rotateFileVault, useUI: true)
    }
    
    /**
     Enhanced enrollment in new tenant using the script
     */
    func enrollInNewTenant(targetTenant: String) async throws {
        guard !targetTenant.isEmpty else {
            throw NSError(domain: "ScriptMigrationManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Target tenant name is required"])
        }
        
        _ = try await executeScriptSafely(operation: .enrollTenant, targetTenant: targetTenant, useUI: true)
    }
    
    /**
     Backup tenant settings using the script
     */
    func backupTenantSettings() async throws -> String? {
        // First detect MDM vendor
        let mdmVendor = await mdmDetectionService.detectPrimaryMDM()
        
        let output = try await executeScriptSafely(
            operation: .backupOnly,
            sourceMDM: mdmVendor.identifier
        )
        
        // Extract backup path from output
        if let range = output.range(of: "Profiles backed up to: (.+)$", options: .regularExpression) {
            let backupPath = String(output[range]).replacingOccurrences(of: "Profiles backed up to: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return backupPath
        }
        
        return nil
    }
    
    /**
     Update Company Portal using the script
     */
    func updateCompanyPortal() async throws {
        _ = try await executeScriptSafely(operation: .updateCompanyPortal)
    }
    
    /**
     Performs a complete MDM migration using the script-based approach
     */
    func performScriptBasedMigration(targetTenant: String) async throws {
        guard !targetTenant.isEmpty else {
            throw NSError(domain: "ScriptMigrationManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Target tenant name is required"])
        }
        
        // First detect MDM vendor
        let mdmVendor = await mdmDetectionService.detectPrimaryMDM()
        
        // Execute the script with source MDM info
        _ = try await executeScriptSafely(
            operation: .fullMigration,
            targetTenant: targetTenant,
            sourceMDM: mdmVendor.identifier,
            useUI: true
        )
    }
}
