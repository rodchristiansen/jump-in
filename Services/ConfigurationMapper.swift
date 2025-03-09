//
//  ConfigurationMapper.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 03/03/2025.
//

import Foundation

/// Maps configuration profiles between different MDM vendors
class ConfigurationMapper {
    static let shared = ConfigurationMapper()
    
    private let logger = Logger.shared
    private let privilegedService = PrivilegedService.shared
    
    /// Configuration category types
    enum ConfigCategory: String, CaseIterable {
        case security = "Security"
        case network = "Network"
        case restrictions = "Restrictions"
        case applications = "Applications"
        case certificates = "Certificates"
        case compliance = "Compliance"
        case updates = "Updates"
        case other = "Other"
    }
    
    /// Configuration profile information
    struct ProfileInfo {
        let identifier: String
        let displayName: String
        let organization: String?
        let description: String?
        let category: ConfigCategory
        let payload: [String: Any]?
        let isInstalled: Bool
        let sourceVendor: String
    }
    
    private init() {}
    
    /// Generate a report of current MDM configurations
    func generateConfigurationReport(sourceVendor: MDMVendorInfo) async throws -> String {
        logger.info("Generating configuration report for \(sourceVendor.displayName)")
        
        // Get all profiles
        let profiles = try await getInstalledProfiles(sourceVendor: sourceVendor)
        
        // Generate a markdown report
        var report = """
        # MDM Configuration Report
        
        ## Source MDM: \(sourceVendor.displayName)
        Generated on: \(Date().formatted())
        
        """
        
        // Group profiles by category
        let profilesByCategory = Dictionary(grouping: profiles) { $0.category }
        
        // Add summary section
        report += "\n## Summary\n\n"
        report += "Total profiles: \(profiles.count)\n\n"
        
        report += "| Category | Profile Count |\n"
        report += "| -------- | ------------- |\n"
        
        for category in ConfigCategory.allCases {
            let count = profilesByCategory[category]?.count ?? 0
            if count > 0 {
                report += "| \(category.rawValue) | \(count) |\n"
            }
        }
        
        // Add details for each category
        for category in ConfigCategory.allCases {
            if let categoryProfiles = profilesByCategory[category], !categoryProfiles.isEmpty {
                report += "\n## \(category.rawValue) Profiles\n\n"
                
                for profile in categoryProfiles {
                    report += "### \(profile.displayName)\n\n"
                    report += "- **Identifier**: `\(profile.identifier)`\n"
                    
                    if let organization = profile.organization {
                        report += "- **Organization**: \(organization)\n"
                    }
                    
                    if let description = profile.description, !description.isEmpty {
                        report += "- **Description**: \(description)\n"
                    }
                    
                    report += "- **Installed**: \(profile.isInstalled ? "Yes" : "No")\n\n"
                    
                    // Add payload information if available
                    if let payload = profile.payload {
                        report += "#### Key Settings\n\n"
                        
                        let keySettings = extractKeySettings(from: payload, category: category)
                        if !keySettings.isEmpty {
                            for (key, value) in keySettings {
                                report += "- **\(key)**: \(value)\n"
                            }
                        } else {
                            report += "No key settings extracted\n"
                        }
                    }
                    
                    report += "\n---\n\n"
                }
            }
        }
        
        return report
    }
    
    /// Create Intune equivalents report for future reference
    func generateIntuneEquivalentsReport(sourceVendor: MDMVendorInfo) async throws -> String {
        logger.info("Generating Intune equivalents report for \(sourceVendor.displayName)")
        
        // Get all profiles
        let profiles = try await getInstalledProfiles(sourceVendor: sourceVendor)
        
        // Generate markdown report
        var report = """
        # Intune Migration Reference Guide
        
        ## Source MDM: \(sourceVendor.displayName)
        This guide helps you recreate your \(sourceVendor.displayName) configurations in Microsoft Intune.
        
        """
        
        // Group profiles by category
        let profilesByCategory = Dictionary(grouping: profiles) { $0.category }
        
        for category in ConfigCategory.allCases {
            if let categoryProfiles = profilesByCategory[category], !categoryProfiles.isEmpty {
                report += "\n## \(category.rawValue) Configurations\n\n"
                
                // Add Intune equivalent information based on category
                switch category {
                case .security:
                    report += """
                    Intune equivalent: **Endpoint security** > **Security baselines** or **Security policies**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .network:
                    report += """
                    Intune equivalent: **Devices** > **Configuration profiles** > **Create profile** > **Templates** > **Wi-Fi or VPN**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .restrictions:
                    report += """
                    Intune equivalent: **Devices** > **Configuration profiles** > **Create profile** > **Templates** > **Restrictions**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .applications:
                    report += """
                    Intune equivalent: **Apps** > **macOS apps** > **Add**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .certificates:
                    report += """
                    Intune equivalent: **Devices** > **Configuration profiles** > **Create profile** > **Templates** > **Certificates**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .compliance:
                    report += """
                    Intune equivalent: **Devices** > **Compliance policies** > **Create Policy** > **macOS**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .updates:
                    report += """
                    Intune equivalent: **Devices** > **Configuration profiles** > **Create profile** > **Templates** > **Software updates**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                case .other:
                    report += """
                    Intune equivalent: **Devices** > **Configuration profiles** > **Create profile** > **Templates** > **Custom**
                    
                    Key settings from your \(sourceVendor.displayName) profiles:
                    
                    """
                }
                
                // List profiles in this category
                for profile in categoryProfiles {
                    report += "\n### \(profile.displayName)\n\n"
                    
                    // Extract key settings from payload
                    if let payload = profile.payload {
                        let keySettings = extractKeySettings(from: payload, category: category)
                        
                        // Suggest Intune equivalent settings
                        report += "Intune equivalent settings:\n\n"
                        
                        if !keySettings.isEmpty {
                            for (key, value) in keySettings {
                                let intuneEquivalent = mapToIntuneEquivalent(key: key, value: value, category: category)
                                report += "- **\(key)**: \(value)\n"
                                report += "  - *Intune setting*: \(intuneEquivalent)\n"
                            }
                        } else {
                            report += "No key settings extracted. Consider using a custom profile in Intune.\n"
                        }
                    } else {
                        report += "No payload information available.\n"
                    }
                    
                    report += "\n---\n\n"
                }
            }
        }
        
        return report
    }
    
    /// Get all installed configuration profiles
    private func getInstalledProfiles(sourceVendor: MDMVendorInfo) async throws -> [ProfileInfo] {
        logger.info("Getting installed profiles for \(sourceVendor.displayName)")
        
        var profiles: [ProfileInfo] = []
        
        // Export profiles to plist for parsing
        let tempPlistPath = "/private/tmp/profiles_export_\(UUID().uuidString).plist"
        
        do {
            try await privilegedService.executeCommand("/usr/bin/profiles -P -o '\(tempPlistPath)'", requireRoot: true)
            
            // Read the plist
            if FileManager.default.fileExists(atPath: tempPlistPath) {
                let profilesData = try Data(contentsOf: URL(fileURLWithPath: tempPlistPath))
                
                if let plist = try PropertyListSerialization.propertyList(from: profilesData, options: [], format: nil) as? [String: Any],
                   let items = plist["_items"] as? [[String: Any]] {
                    
                    for item in items {
                        // Check if this profile belongs to the source vendor
                        let identifier = item["profileIdentifier"] as? String ?? ""
                        
                        var belongsToVendor = false
                        for pattern in sourceVendor.profileIdentifiers {
                            if identifier.contains(pattern) {
                                belongsToVendor = true
                                break
                            }
                        }
                        
                        // If no specific vendor patterns match but we have a generic MDM, include other profiles
                        if !belongsToVendor && sourceVendor.identifier == "unknown_mdm" {
                            belongsToVendor = true
                        }
                        
                        if belongsToVendor {
                            let displayName = item["profileDisplayName"] as? String ?? "Unknown Profile"
                            let organization = item["profileOrganization"] as? String
                            let description = item["profileDescription"] as? String
                            let isInstalled = item["profileInstalled"] as? Bool ?? true
                            let payload = item["profilePayloads"] as? [String: Any]
                            
                            // Determine category based on profile content
                            let category = determineCategory(
                                identifier: identifier,
                                displayName: displayName,
                                payload: payload
                            )
                            
                            profiles.append(ProfileInfo(
                                identifier: identifier,
                                displayName: displayName,
                                organization: organization,
                                description: description,
                                category: category,
                                payload: payload,
                                isInstalled: isInstalled,
                                sourceVendor: sourceVendor.identifier
                            ))
                        }
                    }
                }
                
                // Clean up
                try? FileManager.default.removeItem(atPath: tempPlistPath)
            }
        } catch {
            logger.error("Failed to get profiles: \(error.localizedDescription)")
            throw error
        }
        
        return profiles
    }
    
    /// Determine the category of a profile based on its content
    private func determineCategory(identifier: String, displayName: String, payload: [String: Any]?) -> ConfigCategory {
        let name = displayName.lowercased()
        let id = identifier.lowercased()
        
        // Check common patterns in names and identifiers
        if name.contains("security") || name.contains("secure") || id.contains("security") {
            return .security
        }
        
        if name.contains("wifi") || name.contains("vpn") || name.contains("network") ||
           id.contains("wifi") || id.contains("vpn") || id.contains("network") {
            return .network
        }
        
        if name.contains("restrict") || name.contains("limit") || name.contains("prevent") ||
           id.contains("restrict") || id.contains("limit") {
            return .restrictions
        }
        
        if name.contains("app") || name.contains("application") || name.contains("software") ||
           id.contains("app") || id.contains("application") {
            return .applications
        }
        
        if name.contains("cert") || name.contains("certificate") || name.contains("identity") ||
           id.contains("cert") || id.contains("identity") || id.contains("pkcs") {
            return .certificates
        }
        
        if name.contains("compliance") || name.contains("conform") ||
           id.contains("compliance") || id.contains("conform") {
            return .compliance
        }
        
        if name.contains("update") || name.contains("upgrade") || name.contains("patch") ||
           id.contains("update") || id.contains("upgrade") {
            return .updates
        }
        
        // Check payload content if available
        if let payload = payload {
            let payloadKeys = payload.keys.map { $0.lowercased() }
            
            if payloadKeys.contains(where: { $0.contains("security") || $0.contains("privacy") }) {
                return .security
            }
            
            if payloadKeys.contains(where: { $0.contains("wifi") || $0.contains("vpn") || $0.contains("network") }) {
                return .network
            }
            
            if payloadKeys.contains(where: { $0.contains("restrict") || $0.contains("limit") }) {
                return .restrictions
            }
            
            if payloadKeys.contains(where: { $0.contains("app") || $0.contains("application") }) {
                return .applications
            }
            
            if payloadKeys.contains(where: { $0.contains("cert") || $0.contains("identity") }) {
                return .certificates
            }
            
            if payloadKeys.contains(where: { $0.contains("compliance") }) {
                return .compliance
            }
            
            if payloadKeys.contains(where: { $0.contains("update") || $0.contains("software") }) {
                return .updates
            }
        }
        
        // Default to other
        return .other
    }
    
    /// Extract key settings from a profile payload
    private func extractKeySettings(from payload: [String: Any], category: ConfigCategory) -> [String: String] {
        var settings: [String: String] = [:]
        
        // Extract top-level settings first
        for (key, value) in payload {
            if !shouldIgnoreKey(key) {
                settings[key] = formatValue(value)
            }
        }
        
        // Look for nested payloads
        if let payloadContent = payload["PayloadContent"] as? [[String: Any]] {
            for content in payloadContent {
                // Extract type-specific settings based on payload type
                if let payloadType = content["PayloadType"] as? String {
                    let typeSpecificSettings = extractTypeSpecificSettings(from: content, payloadType: payloadType, category: category)
                    settings.merge(typeSpecificSettings) { (_, new) in new }
                }
                
                // Add any other important keys
                for (key, value) in content {
                    if isImportantKey(key) && !shouldIgnoreKey(key) {
                        settings[key] = formatValue(value)
                    }
                }
            }
        }
        
        return settings
    }
    
    /// Extract settings specific to a payload type
    private func extractTypeSpecificSettings(from content: [String: Any], payloadType: String, category: ConfigCategory) -> [String: String] {
        var settings: [String: String] = [:]
        
        switch payloadType {
        case "com.apple.security.pkcs1":
            if let name = content["Name"] as? String {
                settings["Certificate Name"] = name
            }
            if let certificateURL = content["CertServer"] as? String {
                settings["Certificate Server"] = certificateURL
            }
            
        case "com.apple.wifi.managed":
            if let ssid = content["SSID_STR"] as? String {
                settings["Wi-Fi Name"] = ssid
            }
            if let hiddenNetwork = content["Hidden Network"] as? Bool {
                settings["Hidden Network"] = hiddenNetwork ? "Yes" : "No"
            }
            if let securityType = content["SecurityType"] as? String {
                settings["Security Type"] = securityType
            }
            
        case "com.apple.applicationaccess.new":
            if let allowCamera = content["allowCamera"] as? Bool {
                settings["Allow Camera"] = allowCamera ? "Yes" : "No"
            }
            if let allowScreenShot = content["allowScreenShot"] as? Bool {
                settings["Allow Screenshots"] = allowScreenShot ? "Yes" : "No"
            }
            if let forceEncryptedBackup = content["forceEncryptedBackup"] as? Bool {
                settings["Force Encrypted Backup"] = forceEncryptedBackup ? "Yes" : "No"
            }
            
        case "com.apple.SoftwareUpdate":
            if let autoCheckEnabled = content["AutoCheckEnabled"] as? Bool {
                settings["Auto Check Updates"] = autoCheckEnabled ? "Yes" : "No"
            }
            if let autoUpdate = content["AutomaticDownload"] as? Bool {
                settings["Auto Download Updates"] = autoUpdate ? "Yes" : "No"
            }
            
        case "com.apple.systempolicy.control":
            if let assessmentEnabled = content["EnableAssessment"] as? Bool {
                settings["Gatekeeper Enabled"] = assessmentEnabled ? "Yes" : "No"
            }
            if let allowIdentifiedDevelopers = content["AllowIdentifiedDevelopers"] as? Bool {
                settings["Allow Identified Developers"] = allowIdentifiedDevelopers ? "Yes" : "No"
            }
            
        case "com.apple.firewall":
            if let firewallEnabled = content["EnableFirewall"] as? Bool {
                settings["Firewall Enabled"] = firewallEnabled ? "Yes" : "No"
            }
            if let blockAllIncoming = content["BlockAllIncoming"] as? Bool {
                settings["Block All Incoming"] = blockAllIncoming ? "Yes" : "No"
            }
            
        default:
            // For unknown types, just try to extract common settings
            for (key, value) in content {
                if isImportantKey(key) && !shouldIgnoreKey(key) {
                    settings[key] = formatValue(value)
                }
            }
        }
        
        return settings
    }
    
    /// Determine if a key is important enough to include
    private func isImportantKey(_ key: String) -> Bool {
        let importantPatterns = [
            "Enable", "Allow", "Force", "Require", "Block", "Prevent",
            "Auto", "Security", "Password", "Encryption", "Firewall",
            "VPN", "Certificate", "Identity", "Authentication"
        ]
        
        for pattern in importantPatterns {
            if key.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Determine if a key should be ignored (metadata, etc.)
    private func shouldIgnoreKey(_ key: String) -> Bool {
        let ignorePatterns = [
            "PayloadUUID", "PayloadVersion", "PayloadOrganization",
            "PayloadIdentifier", "PayloadDescription", "PayloadDisplayName"
        ]
        
        for pattern in ignorePatterns {
            if key == pattern {
                return true
            }
        }
        
        return false
    }
    
    /// Format a value for display
    private func formatValue(_ value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "Yes" : "No"
        case let array as [Any]:
            return array.map { formatValue($0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            let items = dict.map { "\($0.key): \(formatValue($0.value))" }
            return "{ " + items.joined(separator: ", ") + " }"
        default:
            return String(describing: value)
        }
    }
    
    /// Map a source MDM setting to its Intune equivalent
    private func mapToIntuneEquivalent(key: String, value: String, category: ConfigCategory) -> String {
        
        let keyLower = key.lowercased()
        
        // Security settings
        if keyLower.contains("firewall") && keyLower.contains("enable") {
            return "Endpoint security > Firewall > 'Enable firewall'"
        }
        if keyLower.contains("password") && keyLower.contains("require") {
            return "Device restrictions > Password > 'Require password'"
        }
        if keyLower.contains("filevault") || keyLower.contains("encryption") {
            return "Endpoint security > Disk encryption > 'Enable FileVault'"
        }
        
        // Network settings
        if keyLower.contains("wifi") {
            return "Device configuration > Wi-Fi > Create Wi-Fi profile"
        }
        if keyLower.contains("vpn") {
            return "Device configuration > VPN > Create VPN profile"
        }
        
        // Restrictions
        if keyLower.contains("camera") {
            return "Device restrictions > Built-in apps > 'Allow use of camera'"
        }
        if keyLower.contains("screenshot") {
            return "Device restrictions > Built-in apps > 'Allow screen capture'"
        }
        
        // Default mapping based on category
        switch category {
        case .security:
            return "Endpoint security > Security policies"
        case .network:
            return "Device configuration > Profiles > Network access"
        case .restrictions:
            return "Device configuration > Profiles > Restrictions"
        case .applications:
            return "Apps > macOS apps"
        case .certificates:
            return "Device configuration > Profiles > Certificates"
        case .compliance:
            return "Compliance policies > macOS"
        case .updates:
            return "Device configuration > Update policies"
        case .other:
            return "Device configuration > Custom profile"
        }
    }
}
