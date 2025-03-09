//
//  MDMMigrationStrategy.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 03/03/2025.
//

import Foundation

/// Represents a migration strategy from one MDM to another
@MainActor
class MDMMigrationStrategy {
    let sourceMDM: MDMVendorInfo
    let targetMDM: MDMVendorInfo
    let migrationSteps: [MigrationStep]
    
    private let logger = Logger.shared
    private let vendorHandler: MDMVendorHandlerProtocol
    private let migrationService: MigrationService
    private let privilegedService = PrivilegedService.shared
    
    init(sourceMDM: MDMVendorInfo, targetMDM: MDMVendorInfo) {
        self.sourceMDM = sourceMDM
        self.targetMDM = targetMDM
        self.vendorHandler = MDMVendorHandlerFactory.createHandler(for: sourceMDM)
        self.migrationService = MigrationService.shared
        
        // Create a custom migration pathway based on source and target MDMs
        self.migrationSteps = MDMMigrationStrategy.createMigrationSteps(from: sourceMDM, to: targetMDM)
        
        logger.info("Created migration strategy from \(sourceMDM.displayName) to \(targetMDM.displayName)")
    }
    
    /// Create appropriate migration steps based on source and target MDMs
    private static func createMigrationSteps(from sourceMDM: MDMVendorInfo, to targetMDM: MDMVendorInfo) -> [MigrationStep] {
        var steps: [MigrationStep] = []
        
        // Step 1: Prerequisites check
        steps.append(MigrationStep(
            id: "prerequisites",
            name: "Check Prerequisites",
            description: "Verifying system requirements",
            status: .notStarted,
            progress: 0,
            isBlocker: true
        ))
        
        // Step 2: Backup source MDM settings
        steps.append(MigrationStep(
            id: "backupSettings",
            name: "Backup \(sourceMDM.displayName) Settings",
            description: "Backing up current MDM settings",
            status: .notStarted,
            progress: 0,
            isBlocker: true
        ))
        
        // Step 3: Vendor-specific pre-migration tasks
        steps.append(MigrationStep(
            id: "preMigrationTasks",
            name: "\(sourceMDM.displayName) Pre-Migration",
            description: "Preparing for unenrollment",
            status: .notStarted,
            progress: 0,
            isBlocker: false
        ))
        
        // Step 4: Remove source MDM profiles
        steps.append(MigrationStep(
            id: "removeMDM",
            name: "Remove \(sourceMDM.displayName)",
            description: "Removing current MDM profiles",
            status: .notStarted,
            progress: 0,
            isBlocker: true
        ))
        
        // Step 5: Verify removal
        steps.append(MigrationStep(
            id: "verifyRemoval",
            name: "Verify Unenrollment",
            description: "Confirming MDM removal",
            status: .notStarted,
            progress: 0,
            isBlocker: true
        ))
        
        // Step 6: Update Company Portal (for Intune target)
        if targetMDM.isIntune {
            steps.append(MigrationStep(
                id: "updateCompanyPortal",
                name: "Update Company Portal",
                description: "Installing/updating Company Portal application",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ))
        }
        
        // Step 7: Enroll in target MDM
        steps.append(MigrationStep(
            id: "newMDMEnrollment",
            name: "Enroll in \(targetMDM.displayName)",
            description: "Enrolling in the new MDM solution",
            status: .notStarted,
            progress: 0,
            isBlocker: true
        ))
        
        // Step 8: Vendor-specific post-migration tasks
        steps.append(MigrationStep(
            id: "postMigrationTasks",
            name: "Post-Migration Tasks",
            description: "Finalizing configuration",
            status: .notStarted,
            progress: 0,
            isBlocker: false
        ))
        
        // Step 9: FileVault key rotation (optional)
        steps.append(MigrationStep(
            id: "fileVault",
            name: "FileVault Key",
            description: "Rotating FileVault recovery key",
            status: .notStarted,
            progress: 0,
            isBlocker: false
        ))
        
        // Step 10: Completion
        steps.append(MigrationStep(
            id: "completion",
            name: "Complete Migration",
            description: "Finalizing migration process",
            status: .notStarted,
            progress: 0,
            isBlocker: false
        ))
        
        return steps
    }
    
    /// Execute the migration strategy
    func executeMigration() async throws {
        logger.info("Starting migration from \(sourceMDM.displayName) to \(targetMDM.displayName)")
        
        // Step 1: Check Prerequisites
        try await executeStep(id: "prerequisites") {
            try await checkPrerequisites()
        }
        
        // Step 2: Backup Settings
        try await executeStep(id: "backupSettings") {
            try await backupSettings()
        }
        
        // Step 3: Pre-Migration Tasks
        try await executeStep(id: "preMigrationTasks") {
            try await vendorHandler.performPreMigrationTasks()
        }
        
        // Step 4: Remove MDM
        try await executeStep(id: "removeMDM") {
            _ = try await vendorHandler.removeProfiles()
        }
        
        // Step 5: Verify Removal
        try await executeStep(id: "verifyRemoval") {
            let isRemoved = try await vendorHandler.verifyUnenrollment()
            if !isRemoved {
                throw MigrationError.currentTenantRemovalFailed("Failed to verify MDM removal")
            }
        }
        
        // Step 6: Update Company Portal (if Intune is target)
        if targetMDM.isIntune {
            try await executeStep(id: "updateCompanyPortal") {
                // Use PrivilegedService for Company Portal installation
                try await privilegedService.installCompanyPortal()
            }
        }
        
        // Step 7: Enroll in new MDM
        try await executeStep(id: "newMDMEnrollment") {
            if targetMDM.isIntune {
                // Capture targetTenantName from main actor context
                let targetTenant = migrationService.migrationState.targetTenantName
                
                if targetTenant.isEmpty {
                    throw MigrationError.configurationFailed("Target Intune tenant name is required")
                }
                
                // Use PrivilegedService for enrollment
                try await privilegedService.enrollInNewTenant(targetTenant: targetTenant)
            } else {
                // Generic enrollment guidance for other MDMs would go here
                // Currently only supporting Intune as target
                throw MigrationError.configurationFailed("Only Microsoft Intune is supported as target MDM")
            }
        }
        
        // Step 8: Post-Migration Tasks
        try await executeStep(id: "postMigrationTasks") {
            try await vendorHandler.performPostMigrationTasks()
        }
        
        // Step 9: FileVault Key Rotation - removed in favor of post-migration relaunch
                try await executeStep(id: "completion") {
                    // Finalize migration and prepare for FileVault rotation relaunch
                    logger.info("Migration from \(sourceMDM.displayName) to \(targetMDM.displayName) completed successfully")
                    logger.info("FileVault key rotation will be handled in a separate process after relaunch")
                }

        
        // Step 10: Complete migration
        try await executeStep(id: "completion") {
            // Nothing to do here, just mark as complete
            logger.info("Migration from \(sourceMDM.displayName) to \(targetMDM.displayName) completed successfully")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Execute a migration step with proper progress tracking
    private func executeStep(id: String, action: () async throws -> Void) async throws {
        logger.info("Executing migration step: \(id)")
        
        // Find the step index
        guard let stepIndex = migrationSteps.firstIndex(where: { $0.id == id }) else {
            logger.error("Unknown step ID: \(id)")
            return
        }
        
        // Calculate progress values
        let totalSteps = migrationSteps.count
        let startProgress = Int((Double(stepIndex) / Double(totalSteps)) * 100)
        let endProgress = Int((Double(stepIndex + 1) / Double(totalSteps)) * 100)
        
        // Update step status
        try await migrationService.updateMigrationProgress(
            step: migrationSteps[stepIndex].description,
            progress: startProgress
        )
        
        // Mark step as in progress
        migrationService.migrationState.updateStepStatus(id: id, status: .inProgress)
        
        do {
            // Execute the step action
            try await action()
            
            // Mark step as completed
            try await migrationService.updateMigrationProgress(
                step: migrationSteps[stepIndex].description,
                progress: endProgress
            )
            
            migrationService.migrationState.updateStepStatus(id: id, status: .completed)
            
            logger.info("Step completed: \(id)")
        } catch {
            // Mark step as failed
            migrationService.migrationState.updateStepStatus(
                id: id,
                status: .failed(error.localizedDescription)
            )
            
            logger.error("Step failed: \(id) - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Verify prerequisites for migration
    private func checkPrerequisites() async throws {
        logger.info("Checking prerequisites for migration")
        
        // Check system requirements
        let systemRequirements = SystemRequirements()
        let status = await systemRequirements.performAllChecks()
        
        // Update migration state
        migrationService.migrationState.updatePrerequisites(
            isMDMEnrolled: true, // We're migrating from another MDM, so this check is not relevant
            mdmVendorInfo: sourceMDM,
            isMacOSCompatible: status.isMacOSCompatible,
            isFileVaultEnabled: status.isFileVaultEnabled,
            isGatekeeperEnabled: status.isGatekeeperEnabled
        )
        
        guard status.isMacOSCompatible else {
            throw MigrationError.prerequisitesFailed("macOS version not compatible")
        }
        
        // FileVault is recommended but not required
        if !status.isFileVaultEnabled {
            logger.warning("FileVault is not enabled - recommended for secure migration")
        }
        
        guard status.isGatekeeperEnabled else {
            throw MigrationError.prerequisitesFailed("Gatekeeper not enabled")
        }
        
        // Additional MDM-specific prerequisite checks
        if targetMDM.isIntune && migrationService.migrationState.targetTenantName.isEmpty {
            throw MigrationError.prerequisitesFailed("Target Intune tenant name is required")
        }
        
        logger.info("All prerequisites verified for migration")
    }
    
    /// Backup current MDM settings
    private func backupSettings() async throws {
        logger.info("Backing up \(sourceMDM.displayName) settings")
        
        if let backupPath = try await vendorHandler.backupConfiguration() {
            logger.info("MDM settings backed up to: \(backupPath)")
        } else {
            logger.warning("Failed to backup MDM settings, continuing anyway")
        }
    }
    
    /// Check if FileVault is enabled
    private func isFileVaultEnabled() async throws -> Bool {
        do {
            let output = try await privilegedService.executeCommand("/usr/bin/fdesetup status", requireRoot: true)
            return output.contains("FileVault is On")
        } catch {
            logger.error("Failed to check FileVault status: \(error.localizedDescription)")
            return false
        }
    }
}
