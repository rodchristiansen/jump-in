import Foundation
import SwiftUI

/// Enum representing the overall state of migration
enum MigrationPhase: Equatable {
    case notStarted
    case checkingPrerequisites
    case prerequisitesFailed(String)
    case readyToMigrate
    case scheduled(Date)
    case inProgress(progress: Int)
    case completed
    case failed(Error)
    
    static func == (lhs: MigrationPhase, rhs: MigrationPhase) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
        case (.checkingPrerequisites, .checkingPrerequisites):
            return true
        case (.prerequisitesFailed(let lhsReason), .prerequisitesFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.readyToMigrate, .readyToMigrate):
            return true
        case (.scheduled(let lhsDate), .scheduled(let rhsDate)):
            return lhsDate == rhsDate
        case (.inProgress(let lhsProgress), .inProgress(let rhsProgress)):
            return lhsProgress == rhsProgress
        case (.completed, .completed):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Represents the detailed state of prerequisites
struct PrerequisiteState: Equatable {
    var isMDMEnrolled: Bool = false
    var mdmVendorInfo: MDMVendorInfo? = nil
    var isMacOSCompatible: Bool = false
    var isFileVaultEnabled: Bool = false
    var isGatekeeperEnabled: Bool = false
    
    // For backward compatibility
    var isIntuneEnrolled: Bool {
        return mdmVendorInfo?.isIntune == true
    }
    
    var allPrerequisitesMet: Bool {
        isMDMEnrolled &&
        isMacOSCompatible &&
        isFileVaultEnabled &&
        isGatekeeperEnabled
    }
    
    func getFailedPrerequisites() -> [String] {
        var failed: [String] = []
        
        if !isMDMEnrolled {
            failed.append("Device not enrolled in any MDM")
        }
        if !isMacOSCompatible { failed.append("macOS version not compatible") }
        if !isFileVaultEnabled { failed.append("FileVault not enabled") }
        if !isGatekeeperEnabled { failed.append("Gatekeeper not enabled") }
        
        return failed
    }
}

/// Represents a migration step with its status
struct MigrationStep: Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var status: StepStatus
    var progress: Double
    var isBlocker: Bool
    
    enum StepStatus: Equatable {
        case notStarted
        case inProgress
        case completed
        case failed(String)
        
        var description: String {
            switch self {
            case .notStarted: return "Not Started"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .failed(let reason): return "Failed: \(reason)"
            }
        }
    }
}

@MainActor
class MigrationState: ObservableObject {
    @Published private(set) var phase: MigrationPhase = .notStarted
    @Published private(set) var prerequisites = PrerequisiteState()
    @Published private(set) var steps: [MigrationStep] = []
    @Published private(set) var currentStepIndex: Int = 0
    @Published var selectedDeferralMinutes: Int?
    @Published var targetTenantName: String = ""
    @Published var sourceMDMVendor: MDMVendorInfo?
    @Published var targetMDMVendor: MDMVendorInfo?
    
    private let logger = Logger.shared
    
    init() {
        // Default target to Intune
        targetMDMVendor = MDMVendorInfo.intune
        setupDefaultMigrationSteps()
    }
    
    func updateStepStatus(id: String, status: MigrationStep.StepStatus) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            steps[index].status = status
            if status == .completed && index < steps.count - 1 {
                currentStepIndex = index + 1
            }
        }
    }
    
    // Setup migration steps based on source and target MDM vendors
    func setupMigrationSteps(sourceMDM: MDMVendorInfo? = nil, targetMDM: MDMVendorInfo? = nil) {
        // Update vendor info
        if let sourceMDM = sourceMDM {
            self.sourceMDMVendor = sourceMDM
        }
        
        if let targetMDM = targetMDM {
            self.targetMDMVendor = targetMDM
        } else if self.targetMDMVendor == nil {
            // Default to Intune if no target specified
            self.targetMDMVendor = MDMVendorInfo.intune
        }
        
        // Get source and target names for step descriptions
        let sourceName = sourceMDMVendor?.displayName ?? "Current MDM"
        let targetName = targetMDMVendor?.displayName ?? "Microsoft Intune"
        
        steps = [
            MigrationStep(
                id: "prerequisites",
                name: "Check Prerequisites",
                description: "Verifying system requirements",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "backupSettings",
                name: "Backup \(sourceName) Settings",
                description: "Backing up current MDM settings",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "preMigrationTasks",
                name: "\(sourceName) Pre-Migration",
                description: "Preparing for unenrollment",
                status: .notStarted,
                progress: 0,
                isBlocker: false
            ),
            MigrationStep(
                id: "removeMDM",
                name: "Remove \(sourceName)",
                description: "Removing current MDM management profiles",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "verifyRemoval",
                name: "Verify Unenrollment",
                description: "Confirming MDM removal",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            )
        ]
        
        // Add Company Portal step only for Intune target
        if targetMDMVendor?.isIntune == true {
            steps.append(
                MigrationStep(
                    id: "updateCompanyPortal",
                    name: "Update Company Portal",
                    description: "Installing/updating Company Portal application",
                    status: .notStarted,
                    progress: 0,
                    isBlocker: true
                )
            )
        }
        
        // Add enrollment step
        steps.append(
            MigrationStep(
                id: "newMDMEnrollment",
                name: "Enroll in \(targetName)",
                description: "Enrolling in the new MDM solution",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            )
        )
        
        // Add remaining steps
        steps.append(contentsOf: [
            MigrationStep(
                id: "postMigrationTasks",
                name: "Post-Migration Tasks",
                description: "Finalizing configuration",
                status: .notStarted,
                progress: 0,
                isBlocker: false
            ),
            //MigrationStep(
               // id: "fileVault",
               // name: "FileVault Key",
               // description: "Rotating FileVault recovery key",
               // status: .notStarted,
               // progress: 0,
               // isBlocker: false
            //),
            MigrationStep(
                id: "completion",
                name: "Complete Migration",
                description: "Finalizing migration process",
                status: .notStarted,
                progress: 0,
                isBlocker: false
            )
        ])
        
        logger.info("Setup migration steps from \(sourceName) to \(targetName)")
    }
    
    // Backward compatibility method to set up the original steps
    private func setupDefaultMigrationSteps() {
        steps = [
            MigrationStep(
                id: "prerequisites",
                name: "Check Prerequisites",
                description: "Verifying system requirements",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "backupSettings",
                name: "Backup Settings",
                description: "Backing up current tenant settings",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "removeMDM",
                name: "Remove Current Tenant",
                description: "Removing current Intune management profile",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "updateCompanyPortal",
                name: "Update Company Portal",
                description: "Updating Company Portal application",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            MigrationStep(
                id: "newTenantEnrollment",
                name: "New Tenant Enrollment",
                description: "Enrolling in the new Intune tenant",
                status: .notStarted,
                progress: 0,
                isBlocker: true
            ),
            //MigrationStep(
               // id: "fileVault",
              //  name: "FileVault Key",
               // description: "Rotating FileVault recovery key",
              //  status: .notStarted,
               // progress: 0,
               // isBlocker: false
            //),
            MigrationStep(
                id: "completion",
                name: "Complete Migration",
                description: "Finalizing tenant migration process",
                status: .notStarted,
                progress: 0,
                isBlocker: false
            )
        ]
    }
    
    func updateProgress(progress: Int, stepDescription: String) {
        logger.info("Updating progress: \(stepDescription) - \(progress)%")
        phase = .inProgress(progress: progress)
        
        // Update current step
        if currentStepIndex < steps.count {
            steps[currentStepIndex].progress = Double(progress)
            steps[currentStepIndex].status = .inProgress
            
            // Mark step as completed if 100%
            if progress == 100 {
                steps[currentStepIndex].status = .completed
                if currentStepIndex < steps.count - 1 {
                    currentStepIndex += 1
                }
            }
        }
    }
    
    func updatePrerequisites(
        isMDMEnrolled: Bool? = nil,
        mdmVendorInfo: MDMVendorInfo? = nil,
        isMacOSCompatible: Bool? = nil,
        isFileVaultEnabled: Bool? = nil,
        isGatekeeperEnabled: Bool? = nil
    ) {
        if let isMDMEnrolled = isMDMEnrolled {
            prerequisites.isMDMEnrolled = isMDMEnrolled
        }
        
        if let mdmVendorInfo = mdmVendorInfo {
            prerequisites.mdmVendorInfo = mdmVendorInfo
            sourceMDMVendor = mdmVendorInfo
            
            // Update migration steps based on detected MDM
            setupMigrationSteps(sourceMDM: mdmVendorInfo)
        }
        
        if let isMacOSCompatible = isMacOSCompatible {
            prerequisites.isMacOSCompatible = isMacOSCompatible
        }
        
        if let isFileVaultEnabled = isFileVaultEnabled {
            prerequisites.isFileVaultEnabled = isFileVaultEnabled
        }
        
        if let isGatekeeperEnabled = isGatekeeperEnabled {
            prerequisites.isGatekeeperEnabled = isGatekeeperEnabled
        }
        
        logger.info("Prerequisites updated: \(prerequisites)")
        
        if prerequisites.allPrerequisitesMet {
            phase = .readyToMigrate
        } else {
            let failedItems = prerequisites.getFailedPrerequisites().joined(separator: ", ")
            phase = .prerequisitesFailed(failedItems)
        }
    }
    
    // For backward compatibility - updates using Intune-specific terminology
    func updatePrerequisites(
        isIntuneEnrolled: Bool? = nil,
        isMacOSCompatible: Bool? = nil,
        isFileVaultEnabled: Bool? = nil,
        isGatekeeperEnabled: Bool? = nil
    ) {
        if let isIntuneEnrolled = isIntuneEnrolled {
            prerequisites.isMDMEnrolled = isIntuneEnrolled
            
            // If Intune is detected, set vendor info
            if isIntuneEnrolled && prerequisites.mdmVendorInfo == nil {
                let intuneVendor = MDMVendorInfo.intune
                prerequisites.mdmVendorInfo = intuneVendor
                sourceMDMVendor = intuneVendor
            }
        }
        
        if let isMacOSCompatible = isMacOSCompatible {
            prerequisites.isMacOSCompatible = isMacOSCompatible
        }
        
        if let isFileVaultEnabled = isFileVaultEnabled {
            prerequisites.isFileVaultEnabled = isFileVaultEnabled
        }
        
        if let isGatekeeperEnabled = isGatekeeperEnabled {
            prerequisites.isGatekeeperEnabled = isGatekeeperEnabled
        }
        
        logger.info("Prerequisites updated (legacy method): \(prerequisites)")
        
        if prerequisites.allPrerequisitesMet {
            phase = .readyToMigrate
        } else {
            let failedItems = prerequisites.getFailedPrerequisites().joined(separator: ", ")
            phase = .prerequisitesFailed(failedItems)
        }
    }
    
    private func calculateOverallProgress() -> Int {
        let completedSteps = steps.filter { $0.status == .completed }.count
        let totalSteps = steps.count
        return Int((Double(completedSteps) / Double(totalSteps)) * 100)
    }
    
    var currentStep: MigrationStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    
    var isInProgress: Bool {
        if case .inProgress = phase { return true }
        return false
    }
    
    var canProceed: Bool {
        prerequisites.allPrerequisitesMet && !isInProgress
    }
    
    // Get source MDM name for display
    var sourceMDMName: String {
        sourceMDMVendor?.displayName ?? "Current MDM"
    }
    
    // Get target MDM name for display
    var targetMDMName: String {
        targetMDMVendor?.displayName ?? "Microsoft Intune"
    }
    
    func reset() {
        phase = .notStarted
        prerequisites = PrerequisiteState()
        currentStepIndex = 0
        selectedDeferralMinutes = nil
        targetTenantName = ""
        sourceMDMVendor = nil
        setupDefaultMigrationSteps()
        logger.info("Migration state reset")
    }
}
