//
//  MigrationTypes.swift
//  macOS JUMP-IN
//

import Foundation

// MARK: - Migration Status
enum MigrationStatus: Equatable {
    case notStarted
    case inProgress(progress: Int)
    case completed
    case failed(Error)
    
    static func == (lhs: MigrationStatus, rhs: MigrationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
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
    
    var description: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .inProgress(let progress):
            return "In Progress (\(progress)%)"
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Migration Errors
enum MigrationError: LocalizedError {
    case prerequisitesFailed(String)
    case currentTenantRemovalFailed(String)
    case companyPortalInstallFailed(String)
    case configurationFailed(String)
    case helperToolError(String)
    case authorizationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .prerequisitesFailed(let reason):
            return "Prerequisites not met: \(reason)"
        case .currentTenantRemovalFailed(let reason):
            return "Failed to remove current tenant: \(reason)"
        case .companyPortalInstallFailed(let reason):
            return "Failed to install Company Portal: \(reason)"
        case .configurationFailed(let reason):
            return "Failed to configure settings: \(reason)"
        case .helperToolError(let reason):
            return "Helper tool error: \(reason)"
        case .authorizationFailed(let reason):
            return "Authorization failed: \(reason)"
        }
    }
}
