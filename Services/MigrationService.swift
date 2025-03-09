import Foundation
import SwiftUI

@MainActor
final class MigrationService: ObservableObject {
    static let shared = MigrationService()
    
    private let helperToolManager = HelperToolServiceManager.shared
    private let notificationService = NotificationService.shared
    private let logger = Logger.shared
    
    @Published private(set) var currentStatus: MigrationStatus = .notStarted
    @Published private(set) var migrationState = MigrationState()
    @Published private(set) var currentStepDescription: String = ""
    @Published var currentTenant: String?
    private init() {
        Task {
            await detectCurrentTenant()
        }
    }
    
    private func detectCurrentTenant() async {
        do {
            let proxy = try helperToolManager.getHelperToolProxy()
            proxy.getCurrentTenant { [weak self] tenant in
                Task { @MainActor in
                    self?.currentTenant = tenant
                    if let tenant = tenant {
                        self?.logger.info("Detected current tenant: \(tenant)")
                    } else {
                        self?.logger.info("No current tenant detected")
                    }
                }
            }
        } catch {
            logger.error("Failed to detect current tenant: \(error.localizedDescription)")
        }
    }
    
    // Public method to update migration progress
    public func updateMigrationProgress(step: String, progress: Int) async throws {
        await MainActor.run {
            updateProgress(step: step, progress: progress)
        }
    }
    
    // MARK: - Main Migration Methods
    
    func startMigration() async throws {
        logger.info("Starting tenant migration process")
        currentStatus = .inProgress(progress: 0)
        
        do {
            // Check prerequisites
            try await checkPrerequisites()
            
            // Perform migration steps
            try await performMigrationSteps()
            
            // Complete migration
            await completeMigration()
            
        } catch {
            await handleMigrationError(error)
            throw error
        }
    }
    
    func checkPrerequisites() async throws {
        logger.info("Checking prerequisites")
        updateProgress(step: "Checking system requirements", progress: 10)
        
        // First, ensure helper tool is installed
        if !helperToolManager.isHelperToolInstalled {
            logger.info("Installing helper tool")
            try await helperToolManager.installHelperTool()
        }
        
        // Use helper tool to check requirements
        let intuneEnrolled = try await helperToolManager.checkIntuneEnrollment()
        let fileVaultEnabled = try await helperToolManager.checkFileVaultStatus()
        let gatekeeperEnabled = try await helperToolManager.checkGatekeeperStatus()
        
        // Update migration state
        migrationState.updatePrerequisites(
            isIntuneEnrolled: intuneEnrolled,
            isMacOSCompatible: true, // This is checked at app launch
            isFileVaultEnabled: fileVaultEnabled,
            isGatekeeperEnabled: gatekeeperEnabled
        )
        
        guard migrationState.prerequisites.allPrerequisitesMet else {
            let failures = migrationState.prerequisites.getFailedPrerequisites().joined(separator: ", ")
            logger.error("Prerequisites check failed: \(failures)")
            throw MigrationError.prerequisitesFailed(failures)
        }
        
        logger.info("Prerequisites check passed")
        updateProgress(step: "Prerequisites check completed", progress: 20)
    }
    
    // MARK: - Private Methods
    
    private func performMigrationSteps() async throws {
        // Step 1: Check Prerequisites
        updateProgress(step: "prerequisites", description: "Verifying system requirements", progress: 10)
        try await checkPrerequisites()
        migrationState.updateStepStatus(id: "prerequisites", status: .completed)
        
        // Step 2: Backup Settings
        updateProgress(step: "backupSettings", description: "Backing up current tenant settings", progress: 25)
        try await backupTenantSettings()
        migrationState.updateStepStatus(id: "backupSettings", status: .completed)
        
        // Step 3: Remove Current Tenant MDM Profile
        updateProgress(step: "removeMDM", description: "Removing current Intune tenant profile", progress: 40)
        try await helperToolManager.removeCurrentTenantProfile()
        migrationState.updateStepStatus(id: "removeMDM", status: .completed)
        
        // Step 4: Update Company Portal
        updateProgress(step: "updateCompanyPortal", description: "Updating Company Portal application", progress: 60)
        try await helperToolManager.updateCompanyPortal()
        migrationState.updateStepStatus(id: "updateCompanyPortal", status: .completed)
        
        // Step 5: Enroll in New Tenant
        updateProgress(step: "newTenantEnrollment", description: "Enrolling in the new Intune tenant", progress: 75)
        try await enrollInNewTenant()
        migrationState.updateStepStatus(id: "newTenantEnrollment", status: .completed)
        
        // Step 6: Rotate FileVault Key - CRITICAL STEP
            // updateProgress(step: "fileVault", description: "Rotating FileVault recovery key (critical step)", progress: 90)
            // do {
            //     try await helperToolManager.rotateFileVaultKey()
            //     logger.info("FileVault key rotation completed successfully")
            //     migrationState.updateStepStatus(id: "fileVault", status: .completed)
            // } catch {
            //     logger.error("FileVault key rotation failed: \(error.localizedDescription)")
            //     migrationState.updateStepStatus(id: "fileVault", status: .failed("FileVault rotation failed: \(error.localizedDescription)"))
            //     throw MigrationError.configurationFailed("FileVault key rotation is required for tenant migration")
            // }
            
            // Final Step: Complete
            updateProgress(step: "completion", description: "Finalizing tenant migration", progress: 100)
            migrationState.updateStepStatus(id: "completion", status: .completed)
        }
    
    private func backupTenantSettings() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let proxy = try helperToolManager.getHelperToolProxy()
                    proxy.backupTenantSettings { backupPath, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            self.logger.info("Tenant settings backed up to: \(backupPath ?? "unknown location")")
                            continuation.resume()
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func enrollInNewTenant() async throws {
        guard !migrationState.targetTenantName.isEmpty else {
            logger.error("Target tenant name is empty")
            throw MigrationError.configurationFailed("Target tenant name is required")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let proxy = try helperToolManager.getHelperToolProxy()
                    proxy.enrollInNewTenant(targetTenant: migrationState.targetTenantName) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            self.logger.info("Enrollment in new tenant initiated")
                            continuation.resume()
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func updateProgress(step: String, description: String, progress: Int) {
        currentStatus = .inProgress(progress: progress)
        currentStepDescription = description
        
        // Update step status in MigrationState
        migrationState.updateStepStatus(id: step, status: .inProgress)
        migrationState.updateProgress(progress: progress, stepDescription: description)
    }
    
    private func completeMigration() async {
        // Important: Log completion steps
        logger.info("=== BEGINNING MIGRATION COMPLETION ===")
        
        // Update progress in UI
        await MainActor.run {
            updateProgress(step: "Migration completed successfully", progress: 100)
            currentStatus = .completed
            
            // Force UI update
            objectWillChange.send()
            logger.info("Updated UI status to completed")
        }
        
        logger.info("Tenant migration completed successfully")
        
        // Add a brief delay to ensure UI updates
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        do {
            // Show notification
            try await notificationService.showMigrationCompleteNotification(success: true)
            logger.info("Displayed migration completion notification")
            
            // Show completion dialog
            await showCompletionAlert()
            logger.info("Displayed completion alert dialog")
        } catch {
            logger.error("Failed to show completion notification: \(error.localizedDescription)")
        }
        
        logger.info("=== MIGRATION COMPLETION FINISHED ===")
    }
    
    private func handleMigrationError(_ error: Error) async {
        currentStatus = .failed(error)
        logger.error("Migration failed: \(error.localizedDescription)")
        
        do {
            try await notificationService.showMigrationCompleteNotification(success: false)
        } catch {
            logger.error("Failed to show error notification: \(error.localizedDescription)")
        }
    }
    
    private func updateProgress(step: String, progress: Int) {
        currentStatus = .inProgress(progress: progress)
        currentStepDescription = step
        logger.info("\(step): \(progress)%")
        
        // Update migration state
        migrationState.updateProgress(progress: progress, stepDescription: step)
    }
    
    private func showCompletionAlert() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Tenant Migration Complete"
            alert.informativeText = """
            The migration to the new Microsoft Intune tenant has been completed successfully.
            
            Next Steps:
            1. Restart your Mac to apply all changes
            2. After restart, launch Company Portal
            3. Sign in with the new tenant account to complete the setup
            
            Would you like to restart now?
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Restart Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // User chose to restart
                let restartScript = """
                do shell script "shutdown -r now" with administrator privileges
                """
                
                var error: NSDictionary?
                if NSAppleScript(source: restartScript)?.executeAndReturnError(&error) == nil {
                    self.logger.error("Failed to initiate restart")
                }
            }
        }
    }
}
