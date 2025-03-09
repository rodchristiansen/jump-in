import Foundation

/// Errors that can occur during helper tool operations
@objc enum HelperToolError: Int, Error {
    case unknown = 0
    case operationFailed = 1
    case invalidResponse = 2
    case unauthorized = 3
    case installationFailed = 4
    case communicationError = 5
    case fileSystemError = 6
    case configurationError = 7
    case alreadyInProgress = 8
    case timeoutError = 9
    
    // Custom error with string
    private static let errorDomain = "com.IRL.jump-in.helper.error"
    
    // Add to the error creation extensions section
    static func timeoutError(_ description: String) -> NSError {
        return error(code: .timeoutError, description: description)
    }
    
    static func error(code: HelperToolError, description: String) -> NSError {
        return NSError(domain: errorDomain,
                      code: code.rawValue,
                      userInfo: [NSLocalizedDescriptionKey: description])
    }
}

// MARK: - Error Creation Extensions
extension HelperToolError {
    static func operationFailed(_ description: String) -> NSError {
        return error(code: .operationFailed, description: description)
    }
    
    static func invalidResponse(_ description: String = "Invalid response from helper tool") -> NSError {
        return error(code: .invalidResponse, description: description)
    }
    
    static func unauthorized(_ description: String = "Unauthorized to perform operation") -> NSError {
        return error(code: .unauthorized, description: description)
    }
    
    static func installationFailed(_ description: String) -> NSError {
        return error(code: .installationFailed, description: description)
    }
    
    static func communicationError(_ description: String) -> NSError {
        return error(code: .communicationError, description: description)
    }
    
    static func fileSystemError(_ description: String) -> NSError {
        return error(code: .fileSystemError, description: description)
    }
    
    static func configurationError(_ description: String) -> NSError {
        return error(code: .configurationError, description: description)
    }
}

// MARK: - LocalizedError Implementation
extension HelperToolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred"
        case .operationFailed:
            return "Operation failed"
        case .invalidResponse:
            return "Invalid response from helper tool"
        case .unauthorized:
            return "Unauthorized to perform operation"
        case .installationFailed:
            return "Helper tool installation failed"
        case .communicationError:
            return "Communication error with helper tool"
        case .fileSystemError:
            return "File system operation failed"
        case .configurationError:
            return "Configuration error"
        case .alreadyInProgress:
            return "Operation already in progress"
        case .timeoutError:
            return "Operation timed out"
        }
    }
}
