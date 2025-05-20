//
//  MDMDetectionService.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 03/03/2025.
//

import Foundation

/// Information about a detected MDM vendor
struct MDMVendorInfo: Equatable, Identifiable {
    let id = UUID()
    let identifier: String         // Unique identifier (e.g., "jamf", "kandji")
    let displayName: String        // User-friendly name (e.g., "Jamf Pro")
    let version: String?           // Version if available
    let managementType: String     // "Full MDM", "Agent-based", etc.
    let profileIdentifiers: [String] // Associated profile identifiers
    let isIntune: Bool             // Whether this is Microsoft Intune
    
    /// Default for Intune
    static let intune = MDMVendorInfo(
        identifier: "intune",
        displayName: "Microsoft Intune",
        version: nil,
        managementType: "Full MDM",
        profileIdentifiers: ["com.microsoft.intune", "com.microsoft.wdav", "com.microsoft.CompanyPortal"],
        isIntune: true
    )
    
    /// Default for no MDM detected
    static let none = MDMVendorInfo(
        identifier: "none",
        displayName: "No MDM Detected",
        version: nil,
        managementType: "None",
        profileIdentifiers: [],
        isIntune: false
    )
}

/// Service for detecting MDM solutions on macOS
class MDMDetectionService {
    static let shared = MDMDetectionService()
    private let logger = Logger.shared
    private let privilegedService = PrivilegedService.shared
    
    /// Known MDM vendors and their identifiers
    private let knownVendors: [String: [String]] = [
        "jamf": ["com.jamf", "com.jamfsoftware"],
        "kandji": ["io.kandji", "com.kandji"],
        "mosyle": ["com.mosyle", "business.mosyle"],
        "workspace": ["com.air-watch", "com.airwatch", "com.vmware.workspace", "awmdm.com", "Airwatch", "AirWatch", "Workspace ONE", "Intelligent Hub"],
        "addigy": ["com.addigy"],
        "hexnode": ["com.hexnode", "me.hexnode"],
        "meraki": ["com.meraki"],
        "filewave": ["com.filewave"],
        "micromdm": ["io.micromdm", "micromdm.io", "com.github.micromdm"],
        "microsoft": ["com.microsoft.intune", "com.microsoft.enterprise", "Microsoft.Intune", "Microsoft.Profiles"],
        "apple": ["com.apple.mdm", "com.apple.configuration"]
    ]
    
    private init() {}
    
    /// Detect the primary MDM vendor on the system
    func detectPrimaryMDM() async -> MDMVendorInfo {
        logger.info("Starting MDM detection")
        
        // Try each detection method in order of reliability
        if let vendor = await detectFromProfiles() {
            logger.info("Detected MDM from profiles: \(vendor.displayName)")
            return vendor
        }
        
        if let vendor = await detectFromCertificates() {
            logger.info("Detected MDM from certificates: \(vendor.displayName)")
            return vendor
        }
        
        if let vendor = await detectFromBinaries() {
            logger.info("Detected MDM from binaries: \(vendor.displayName)")
            return vendor
        }
        
        logger.info("No MDM solution detected")
        return MDMVendorInfo.none
    }
    
    /// Detect all MDM solutions (primary and secondary)
    func detectAllMDMSolutions() async -> [MDMVendorInfo] {
        var results: [MDMVendorInfo] = []
        
        // Run all detection methods and combine results
        if let profileVendor = await detectFromProfiles() {
            results.append(profileVendor)
        }
        
        if let certVendor = await detectFromCertificates(),
           !results.contains(where: { $0.identifier == certVendor.identifier }) {
            results.append(certVendor)
        }
        
        if let binaryVendor = await detectFromBinaries(),
           !results.contains(where: { $0.identifier == binaryVendor.identifier }) {
            results.append(binaryVendor)
        }
        
        return results.isEmpty ? [MDMVendorInfo.none] : results
    }
    
    /// Check if device is enrolled in any MDM
    func isEnrolledInMDM() async -> Bool {
        let vendor = await detectPrimaryMDM()
        return vendor.identifier != "none"
    }
    
    /// Check if device is enrolled in Microsoft Intune specifically
    func isEnrolledInIntune() async -> Bool {
        let vendor = await detectPrimaryMDM()
        return vendor.isIntune
    }
    
    // MARK: - Primary Detection Methods
    
    /// Detect MDM vendor from configuration profiles
    private func detectFromProfiles() async -> MDMVendorInfo? {
        do {
            // Use 'profiles list' or 'profiles show' as needed
            let profilesOutput = try await privilegedService.executeCommand(
                "/usr/bin/profiles list",
                requireRoot: true
            )
            logger.info("Obtained profiles list for MDM detection")
            
            // 1) If "No configuration profiles installed" (or the system-domain variant),
            //    immediately conclude there's no MDM
            if profilesOutput.contains("No configuration profiles installed") ||
               profilesOutput.contains("There are no configuration profiles installed in the system domain") {
                logger.info("No profiles installed; returning 'none' MDM")
                return MDMVendorInfo.none
            }
            
            // 2) Check specifically for Intune
            if profilesOutput.contains("Microsoft.Intune") ||
               profilesOutput.contains("Microsoft.Profiles.MDM") ||
               profilesOutput.contains("com.microsoft.enterprise") {
                
                logger.info("Detected Microsoft Intune from profiles")
                let version: String? = nil
                return MDMVendorInfo(
                    identifier: "intune",
                    displayName: "Microsoft Intune",
                    version: version,
                    managementType: "Full MDM",
                    profileIdentifiers: ["Microsoft.Intune", "Microsoft.Profiles.MDM"],
                    isIntune: true
                )
            }
            
            // 3) Check other known MDMs
            for (vendorId, identifiers) in knownVendors {
                for identifier in identifiers {
                    if profilesOutput.contains(identifier) {
                        return await createVendorInfo(vendorId, profilesOutput: profilesOutput)
                    }
                }
            }
            
            // Check specifically for Workspace ONE/AirWatch using enrollment status
            do {
                // Check enrollment status for Airwatch server URL
                let enrollmentOutput = try await privilegedService.executeCommand(
                    "/usr/bin/profiles status -type enrollment",
                    requireRoot: true
                )
                if enrollmentOutput.contains("awmdm.com") {
                    logger.info("Detected VMware Workspace ONE from MDM server URL")
                    return await createVendorInfo("workspace", profilesOutput: profilesOutput)
                }
                
                // Check detailed profiles for Airwatch/VMware identifiers
                let detailedOutput = try await privilegedService.executeCommand(
                    "/usr/bin/profiles show",
                    requireRoot: true
                )
                if detailedOutput.contains("Airwatch") ||
                   detailedOutput.contains("AirWatch") ||
                   detailedOutput.contains("Workspace ONE") ||
                   detailedOutput.contains("Intelligent Hub") {
                    logger.info("Detected VMware Workspace ONE from detailed profile info")
                    return await createVendorInfo("workspace", profilesOutput: detailedOutput)
                }
            } catch {
                logger.warning("Failed to check enrollment status: \(error.localizedDescription)")
            }
            
            // 4) If we see "MDM" but no recognized vendor, return "Unknown MDM"
            if profilesOutput.contains("MDM") {
                return MDMVendorInfo(
                    identifier: "unknown_mdm",
                    displayName: "Unknown MDM Solution",
                    version: nil,
                    managementType: "Full MDM",
                    profileIdentifiers: ["MDM"],
                    isIntune: false
                )
            }
            
            // Otherwise, no MDM found
            logger.info("No MDM profiles detected; returning 'none' MDM")
            return MDMVendorInfo.none
            
        } catch {
            logger.error("Failed to detect MDM from profiles: \(error.localizedDescription)")
            return MDMVendorInfo.none
        }
    }
    
    /// Detect MDM vendor from certificates
    private func detectFromCertificates() async -> MDMVendorInfo? {
        do {
            // Check for MDM enrollment certificates
            let certsOutput = try await privilegedService.executeCommand("/usr/bin/security find-certificate -a -c 'SCEP' -p /Library/Keychains/System.keychain", requireRoot: true)
            
            // Look for vendor-specific certificate patterns
            if certsOutput.contains("jamf") || certsOutput.contains("JAMF") {
                return await createVendorInfo("jamf", certsOutput: certsOutput)
            }
            
            if certsOutput.contains("Microsoft") || certsOutput.contains("Intune") {
                return MDMVendorInfo.intune
            }
            
            if certsOutput.contains("kandji") || certsOutput.contains("Kandji") {
                return await createVendorInfo("kandji", certsOutput: certsOutput)
            }
            
            if certsOutput.contains("mosyle") || certsOutput.contains("Mosyle") {
                return await createVendorInfo("mosyle", certsOutput: certsOutput)
            }

            if certsOutput.contains("MicroMDM") {
                return await createVendorInfo("micromdm", certsOutput: certsOutput)
            }

            if certsOutput.contains("vmware") || certsOutput.contains("airwatch") || certsOutput.contains("workspace") || certsOutput.contains("awmdm") {
                return await createVendorInfo("workspace", certsOutput: certsOutput)
            }
            
            // Generic MDM certificate detection
            if certsOutput.contains("MDM") || certsOutput.contains("SCEP") {
                return MDMVendorInfo(
                    identifier: "unknown_mdm",
                    displayName: "Unknown MDM Solution",
                    version: nil,
                    managementType: "Certificate-based MDM",
                    profileIdentifiers: [],
                    isIntune: false
                )
            }
            
            return nil
        } catch {
            logger.error("Failed to detect MDM from certificates: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Detect MDM vendor from installed binaries and agents
    private func detectFromBinaries() async -> MDMVendorInfo? {
        // Check for Jamf binary
        if FileManager.default.fileExists(atPath: "/usr/local/bin/jamf") ||
           FileManager.default.fileExists(atPath: "/usr/local/jamf/bin/jamf") {
            return await createVendorInfo("jamf", fromBinary: true)
        }
        
        // Check for Kandji agent
        if FileManager.default.fileExists(atPath: "/Library/Kandji/Kandji Agent.app") {
            return await createVendorInfo("kandji", fromBinary: true)
        }
        
        // Check for Mosyle agent
        if FileManager.default.fileExists(atPath: "/Library/Application Support/Mosyle") {
            return await createVendorInfo("mosyle", fromBinary: true)
        }
        
        // Check for Workspace ONE Hub
        if FileManager.default.fileExists(atPath: "/Applications/Workspace ONE Intelligent Hub.app") ||
           FileManager.default.fileExists(atPath: "/Applications/VMware AirWatch Agent.app") ||
           FileManager.default.fileExists(atPath: "/Library/Application Support/AirWatch") {
            return await createVendorInfo("workspace", fromBinary: true)
        }

        
        // Check for Intune Company Portal
        if FileManager.default.fileExists(atPath: "/Applications/Company Portal.app") {
            return MDMVendorInfo.intune
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    /// Create vendor info for a specific vendor
    private func createVendorInfo(_ vendorId: String, profilesOutput: String? = nil, certsOutput: String? = nil, fromBinary: Bool = false) async -> MDMVendorInfo {
        let displayName: String
        let version: String?
        let profileIdentifiers: [String]
        
        switch vendorId {
            case "jamf":
                displayName = "Jamf Pro"
                version = await extractJamfVersion()
                profileIdentifiers = knownVendors["jamf"] ?? ["com.jamf"]
                
            case "kandji":
                displayName = "Kandji MDM"
                version = nil
                profileIdentifiers = knownVendors["kandji"] ?? ["io.kandji"]
                
            case "mosyle":
                displayName = "Mosyle MDM"
                version = nil
                profileIdentifiers = knownVendors["mosyle"] ?? ["com.mosyle"]
                
            case "workspace":
                displayName = "VMware Workspace ONE"
                version = await extractWorkspaceOneVersion()
                profileIdentifiers = knownVendors["workspace"] ?? ["com.air-watch"]

            case "micromdm":
                displayName = "MicroMDM"
                version = nil
                profileIdentifiers = knownVendors["micromdm"] ?? ["io.micromdm"]
                
            default:
                displayName = vendorId.capitalized + " MDM"
                version = nil
                profileIdentifiers = knownVendors[vendorId] ?? []
        }
        
        let managementType = fromBinary ? "Agent-based MDM" : "Full MDM"
        
        return MDMVendorInfo(
            identifier: vendorId,
            displayName: displayName,
            version: version,
            managementType: managementType,
            profileIdentifiers: profileIdentifiers,
            isIntune: vendorId == "intune" || vendorId == "microsoft"
        )
    }
    
    /// Extract Jamf version if available
    private func extractJamfVersion() async -> String? {
        let jamfBinaryPaths = ["/usr/local/bin/jamf", "/usr/local/jamf/bin/jamf"]
        
        for path in jamfBinaryPaths where FileManager.default.fileExists(atPath: path) {
            do {
                let versionOutput = try await privilegedService.executeCommand("\(path) version", requireRoot: false)
                
                // Extract version from output
                if let range = versionOutput.range(of: "\\d+\\.\\d+\\.\\d+(-t\\d+)?", options: .regularExpression) {
                    return String(versionOutput[range])
                }
            } catch {
                logger.error("Failed to get Jamf version: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    /// Extract Workspace ONE version if available
    private func extractWorkspaceOneVersion() async -> String? {
        // Try to get Hub version if installed
        if FileManager.default.fileExists(atPath: "/Applications/Workspace ONE Intelligent Hub.app") {
            do {
                let plistPath = "/Applications/Workspace ONE Intelligent Hub.app/Contents/Info.plist"
                let plistCmd = "defaults read '\(plistPath)' CFBundleShortVersionString"
                
                let versionOutput = try await privilegedService.executeCommand(plistCmd, requireRoot: false)
                return versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                logger.error("Failed to get Workspace ONE Hub version: \(error.localizedDescription)")
            }
        }
        
        
        if FileManager.default.fileExists(atPath: "/Applications/VMware AirWatch Agent.app") {
            do {
                let plistPath = "/Applications/VMware AirWatch Agent.app/Contents/Info.plist"
                let plistCmd = "defaults read '\(plistPath)' CFBundleShortVersionString"
                
                let versionOutput = try await privilegedService.executeCommand(plistCmd, requireRoot: false)
                return versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                logger.error("Failed to get AirWatch Agent version: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    
    func getDetailedVendorInfo(_ vendor: MDMVendorInfo) async -> MDMVendorInfo {
        // Start with the basic info
        var identifier = vendor.identifier
        var displayName = vendor.displayName
        var version = vendor.version
        var managementType = vendor.managementType
        var profileIdentifiers = vendor.profileIdentifiers
        
        
        switch vendor.identifier {
            case "jamf":
                // Try to get more Jamf details (server URL, etc.)
                if let jamfDetails = await getJamfDetails() {
                    version = jamfDetails.version
                    // Could add server URL or other details to the struct
                }
                
            case "intune":
                // Try to get tenant info
                if let tenant = try? await privilegedService.getCurrentTenant() {
                    displayName = "Microsoft Intune (\(tenant))"
                }
                
            case "workspace":
                // Try to get Workspace ONE server info
                if let serverURL = try? await getWorkspaceOneServer() {
                    displayName = "VMware Workspace ONE (\(serverURL))"
                }
                
            default:
                break
        }
        
        return MDMVendorInfo(
            identifier: identifier,
            displayName: displayName,
            version: version,
            managementType: managementType,
            profileIdentifiers: profileIdentifiers,
            isIntune: vendor.isIntune
        )
    }
    
    /// Get server URL for Workspace ONE if available
    private func getWorkspaceOneServer() async throws -> String? {
        let enrollmentOutput = try await privilegedService.executeCommand(
            "/usr/bin/profiles status -type enrollment",
            requireRoot: true
        )
        
        if let range = enrollmentOutput.range(of: "MDM server: (https://[^\\s]+)", options: .regularExpression) {
            let serverLine = String(enrollmentOutput[range])
            if let urlRange = serverLine.range(of: "https://[^\\s]+", options: .regularExpression) {
                return String(serverLine[urlRange])
            }
        }
        
        return nil
    }
    
    /// Get detailed information about Jamf installation
    private func getJamfDetails() async -> (version: String?, serverURL: String?)? {
        // Check for Jamf configuration
        if FileManager.default.fileExists(atPath: "/Library/Preferences/com.jamfsoftware.jamf.plist") {
            do {
                let plistOutput = try await privilegedService.executeCommand("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist", requireRoot: true)
                
                // Parse the output to extract server URL and version info
                var version: String? = nil
                var serverURL: String? = nil
                
                if plistOutput.contains("server =") {
                    let lines = plistOutput.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("server =") {
                            serverURL = line.components(separatedBy: "=").last?
                                .trimmingCharacters(in: .whitespaces)
                                .replacingOccurrences(of: "\"", with: "")
                                .replacingOccurrences(of: ";", with: "")
                        }
                    }
                }
                
                // Try to get version if not already set
                if version == nil {
                    version = await extractJamfVersion()
                }
                
                return (version: version, serverURL: serverURL)
            } catch {
                logger.error("Failed to read Jamf preferences: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
}
