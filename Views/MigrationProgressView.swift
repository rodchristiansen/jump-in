import SwiftUI

struct MigrationProgressView: View {
    @ObservedObject var migrationService = MigrationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTerminalOutput = false
    @State private var terminalOutput = ""
    @State private var useScriptBasedMigration = false
    @State private var showConfigurationReport = false
    @State private var configurationReport = ""
    
    // Local state to force completion UI when needed
    @State private var forceCompletionUI = false
    
    private let logger = Logger.shared
    private let mdmDetectionService = MDMDetectionService.shared
    
    // Show completion UI
    private var showCompletionUI: Bool {
        if case .completed = migrationService.currentStatus {
            return true
        }
        if case .inProgress(let progress) = migrationService.currentStatus, progress >= 100 {
            return true  // Override - show completion UI at 100%
        }
        return forceCompletionUI
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            // Title changes based on progress
            Text(showCompletionUI ? "MDM Migration Complete" : "MDM Migration in Progress")
                .font(.system(size: 24, weight: .medium))
            
            // MDM vendor info
            if let sourceMDM = migrationService.migrationState.sourceMDMVendor {
                Text("Migrating from: \(sourceMDM.displayName)")
                    .foregroundColor(.secondary)
                
                if let version = sourceMDM.version {
                    Text("Version: \(version)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            if let targetMDM = migrationService.migrationState.targetMDMVendor {
                Text("Migrating to: \(targetMDM.displayName)")
                    .foregroundColor(.blue)
                
                if !migrationService.migrationState.targetTenantName.isEmpty && targetMDM.isIntune {
                    Text("Tenant: \(migrationService.migrationState.targetTenantName)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
            
            // Main content - different based on completion status
            if showCompletionUI {
                completionView  // Show completion content
                Spacer()
            } else {
                progressView    // Show progress content
            }
            
            // Buttons section
            if showCompletionUI {
                // Completion buttons
                VStack(spacing: 15) {
                    Button("FileVault Setup") {
                        do {
                            // Locate the "reissue key.sh" script in app's Resources
                            guard let resourceURL = Bundle.main.url(forResource: "reissue key", withExtension: "sh") else {
                                let alert = NSAlert()
                                alert.messageText = "Script Not Found"
                                alert.informativeText = "Unable to locate 'reissue key.sh' in the app's Resources folder."
                                alert.alertStyle = .critical
                                alert.runModal()
                                return
                            }

                            // Define the temporary destination path: /tmp/reissue_key.sh
                            let tempURL = URL(fileURLWithPath: "/tmp/reissue_key.sh")

                            // If the file already exists in /tmp, remove it
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try FileManager.default.removeItem(at: tempURL)
                            }

                            // Copy the script from Resources to /tmp
                            try FileManager.default.copyItem(at: resourceURL, to: tempURL)
                            
                            // Make the script executable
                            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

                            // Notify the user about next steps
                            let alert = NSAlert()
                            alert.messageText = "Script Ready for Execution"
                            alert.informativeText = """
                            For security reasons, please execute this script manually from the Terminal:

                            /tmp/reissue_key.sh
                            
                            This script will rotate your FileVault recovery key to complete the migration process.
                            """
                            alert.alertStyle = .informational
                            alert.runModal()

                        } catch {
                            // Handle any file operation errors
                            let alert = NSAlert()
                            alert.messageText = "Copy Failed"
                            alert.informativeText = "An error occurred while copying the script: \(error.localizedDescription)"
                            alert.alertStyle = .critical
                            alert.runModal()
                            
                            // Log the error
                            logger.error("Failed to copy FileVault script: \(error.localizedDescription)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .frame(width: 200)
                    
                    Button("View Logs") {
                        showTerminalOutput = true
                        loadProfilesOutput()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 10)
            } else {
                // Progress buttons
                HStack {
                    Button("View Logs") {
                        showTerminalOutput = true
                        loadProfilesOutput()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    
                    Button("Export Config") {
                        Task {
                            await generateConfigurationReport()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button("Restart App") {
                        restartApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    
                    if case .inProgress(let progress) = migrationService.currentStatus, progress >= 30 && progress <= 50 {
                        Button("Force Profile Removal") {
                            Task {
                                try? await executeForceProfileRemoval()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            
            // Bottom message
            Text(showCompletionUI
                ? "Migration completed successfully"
                : "Please do not restart your Mac during the migration process")
                .font(.system(size: 13))
                .foregroundColor(showCompletionUI ? .green : .secondary)
                .padding(.bottom, 20)
        }
        .padding()
        .frame(width: 600, height: 550)
        .onAppear {
            logger.info("MigrationProgressView appeared with status: \(migrationService.currentStatus)")
            
            if case .inProgress(let progress) = migrationService.currentStatus, progress >= 100 {
                // If progress is 100%, set our local state to show completion UI
                logger.info("Progress is 100%, forcing completion UI")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    forceCompletionUI = true
                }
            }
        }
        .onChange(of: progressValue) { newValue in
            if newValue >= 100 {
                // When progress hits 100%, force completion UI
                logger.info("Progress changed to 100%, forcing completion UI")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    forceCompletionUI = true
                }
            }
        }
        .sheet(isPresented: $showTerminalOutput) {
            VStack {
                Text("System Profiles")
                    .font(.headline)
                    .padding()
                
                ScrollView {
                    Text(terminalOutput)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                
                Button("Close") {
                    showTerminalOutput = false
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .frame(width: 500, height: 400)
        }
        .sheet(isPresented: $showConfigurationReport) {
            VStack {
                Text("MDM Configuration Report")
                    .font(.headline)
                    .padding()
                
                ScrollView {
                    Text(configurationReport)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                
                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(configurationReport, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Close") {
                        showConfigurationReport = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(width: 700, height: 500)
        }
    }
    
    // MARK: - Content Views
    
    private var completionView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Migration Complete!")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.green)
            
            // Add success information
            VStack(alignment: .leading, spacing: 10) {
                Text("Your Mac has been successfully migrated to the new tenant.")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 5)
                
                Text("You can now restart your Mac to apply all changes.")
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            .padding(.vertical, 5)
        }
        .padding(.horizontal)
    }
    
    private var progressView: some View {
        VStack {
            // Progress information
            VStack(alignment: .leading, spacing: 15) {
                Text(migrationService.currentStepDescription)
                    .font(.system(size: 16, weight: .regular))
                
                // Progress Bar
                ProgressView(value: Double(progressValue), total: 100)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 6)
                    .animation(.easeInOut, value: progressValue)
                
                Text("In Progress (\(progressValue)%)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Steps List
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(migrationService.migrationState.steps) { step in
                        migrationStepView(step: step)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var progressValue: Int {
        if case .inProgress(let progress) = migrationService.currentStatus {
            return progress
        } else if case .completed = migrationService.currentStatus {
            return 100
        }
        return 0
    }
    
    private func loadProfilesOutput() {
        // Get the latest logs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["list"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            terminalOutput = String(data: outputData, encoding: .utf8) ?? "No output"
        } catch {
            terminalOutput = "Error: \(error.localizedDescription)"
        }
    }
    
    private func migrationStepView(step: MigrationStep) -> some View {
        HStack(spacing: 15) {
            // Status Icon
            Circle()
                .fill(statusColor(for: step))
                .frame(width: 20, height: 20)
                .overlay {
                    if isStepCompleted(step) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else if isCurrentStep(step) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white)
                    }
                }
            
            // Step Info
            VStack(alignment: .leading, spacing: 4) {
                Text(step.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isCurrentStep(step) || isStepCompleted(step) ? .primary : .secondary)
                Text(step.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .opacity(isStepCompleted(step) || isCurrentStep(step) ? 1.0 : 0.6)
    }
    
    private func statusColor(for step: MigrationStep) -> Color {
        if isStepCompleted(step) {
            return .green
        } else if isCurrentStep(step) {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    private func isStepCompleted(_ step: MigrationStep) -> Bool {
        if showCompletionUI || step.status == .completed {
            return true
        }
        return false
    }
    
    private func isCurrentStep(_ step: MigrationStep) -> Bool {
        if showCompletionUI {
            return false
        }
        return step.id == migrationService.migrationState.currentStep?.id
    }
    
    private func restartApp() {
        // Force quit and restart the current app
        let appPath = Bundle.main.bundlePath
        let restartScript = """
        do shell script "sleep 1 && open '\(appPath)'" &
        """
        
        NSAppleScript(source: restartScript)?.executeAndReturnError(nil)
        NSApplication.shared.terminate(nil)
    }
    
    private func launchAppInFileVaultMode() {
        // Launch app with --filevault-only flag as normal user (not admin)
        let appPath = Bundle.main.bundlePath
        let executableName = Bundle.main.executableURL?.lastPathComponent ?? "JUMP-IN"
        
        logger.info("Launching app in FileVault-only mode")
        
        let launchScript = """
        do shell script "open '\(appPath)/Contents/MacOS/\(executableName)' --args --filevault-only" &
        """
        
        var error: NSDictionary?
        if let result = NSAppleScript(source: launchScript)?.executeAndReturnError(&error) {
            logger.info("Launched app in FileVault-only mode")
            NSApplication.shared.terminate(nil)
        } else if let error = error {
            logger.error("Failed to launch in FileVault mode: \(error)")
            
            // Fallback to regular open
            let fallbackScript = """
            do shell script "open '\(appPath)' --args --filevault-only" &
            """
            NSAppleScript(source: fallbackScript)?.executeAndReturnError(nil)
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - Original methods (kept for compatibility)
    
    private func executeForceProfileRemoval() async throws {
        if useScriptBasedMigration {
            try await scriptBasedProfileRemoval()
        } else {
            // First get MDM vendor info
            let mdmVendorInfo = await mdmDetectionService.detectPrimaryMDM()
            
            if mdmVendorInfo.identifier != "none" {
                logger.info("Forcing profile removal for: \(mdmVendorInfo.displayName)")
                
                // Create a vendor-specific handler
                let handler = MDMVendorHandlerFactory.createHandler(for: mdmVendorInfo)
                
                // Execute profile removal
                if try await handler.removeProfiles() {
                    logger.info("Successfully forced removal of \(mdmVendorInfo.displayName) profiles")
                } else {
                    logger.warning("Vendor-specific forced removal failed, trying generic approach")
                    
                    // Create a shell script that will remove profiles
                    let script = """
                    #!/bin/bash
                    /usr/bin/profiles -P | grep -E 'profileIdentifier: ' | sed 's/.*profileIdentifier: //' | while read profile; do
                        echo "Removing profile: $profile"
                        /usr/bin/profiles remove -identifier "$profile"
                    done
                    
                    # If profiles still remain, try more aggressive approach
                    if /usr/bin/profiles list | grep -q -E 'MDM|Profile'; then
                        echo "Attempting more aggressive profile removal..."
                        /usr/bin/profiles -D
                    fi
                    """
                    
                    // Save script to temporary file
                    let tempScriptPath = "/private/tmp/remove_profiles.sh"
                    try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
                    
                    // Make script executable
                    let chmodProcess = Process()
                    chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                    chmodProcess.arguments = ["+x", tempScriptPath]
                    try chmodProcess.run()
                    chmodProcess.waitUntilExit()
                    
                    // Run the script with admin privileges
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = ["-e", "do shell script \"\(tempScriptPath)\" with administrator privileges"]
                    
                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    
                    logger.info("Force profile removal result: \(output)")
                    
                    // Clean up
                    try? FileManager.default.removeItem(atPath: tempScriptPath)
                }
                
                // Attempt to update progress
                let currentProgress = progressValue
                try? await MigrationService.shared.updateMigrationProgress(
                    step: "Profile removal forced for \(mdmVendorInfo.displayName)",
                    progress: currentProgress
                )
                
                // Show confirmation
                let alert = NSAlert()
                alert.messageText = "Profile Removal Attempted"
                alert.informativeText = "Attempted to force remove \(mdmVendorInfo.displayName) profiles. Please check logs for details."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } else {
                logger.warning("No MDM detected, nothing to remove")
                
                let alert = NSAlert()
                alert.messageText = "No MDM Detected"
                alert.informativeText = "No MDM solution was detected on this device."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func scriptBasedProfileRemoval() async throws {
        // Create a ScriptMigrationManager to handle the profile removal
        let scriptManager = ScriptMigrationManager.shared
        
        do {
            // Use the script to remove profiles
            try await scriptManager.removeProfilesWithScript()
            
            // Update progress
            let currentProgress = progressValue
            try? await MigrationService.shared.updateMigrationProgress(step: "Profile removal completed via script", progress: currentProgress)
            
            // Show success message
            let alert = NSAlert()
            alert.messageText = "Profile Removal Complete"
            alert.informativeText = "Profiles have been successfully removed using the enhanced script method."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            logger.error("Script-based profile removal failed: \(error.localizedDescription)")
            
            let alert = NSAlert()
            alert.messageText = "Profile Removal Failed"
            alert.informativeText = "Failed to remove profiles using the enhanced script method: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func generateConfigurationReport() async {
        do {
            // Detect MDM vendor
            let mdmVendorInfo = await mdmDetectionService.detectPrimaryMDM()
            
            if mdmVendorInfo.identifier != "none" {
                // Use ConfigurationMapper to generate report
                let mapper = ConfigurationMapper.shared
                let report = try await mapper.generateConfigurationReport(sourceVendor: mdmVendorInfo)
                
                await MainActor.run {
                    configurationReport = report
                    showConfigurationReport = true
                }
            } else {
                await MainActor.run {
                    configurationReport = "# No MDM Configuration Found\n\nNo MDM solution was detected on this device."
                    showConfigurationReport = true
                }
            }
        } catch {
            logger.error("Failed to generate configuration report: \(error.localizedDescription)")
            
            await MainActor.run {
                configurationReport = "# Error Generating Report\n\nFailed to generate MDM configuration report: \(error.localizedDescription)"
                showConfigurationReport = true
            }
        }
    }
}
