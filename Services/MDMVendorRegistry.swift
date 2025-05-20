//
//  MDMVendorRegistry.swift
//  JUMP-IN
//
//  Created by Somesh Pathak on 03/03/2025.
//

import Foundation

/// Represents an MDM vendor with its identification patterns and details
struct MDMVendorDefinition {
    let identifier: String                // Unique identifier (e.g., "jamf", "intune")
    let displayName: String               // User-friendly name
    let profilePatterns: [String]         // Profile identifier patterns
    let binaryPaths: [String]             // Paths to vendor binaries
    let certificatePatterns: [String]     // Patterns in certificates
    let agentPaths: [String]              // Paths to management agents
    let managementType: String            // Type of management
    let removalCommands: [String]         // Commands to remove this MDM
    let detectionPriority: Int            // Priority in detection (lower = higher priority)
    
    var isIntune: Bool {
        return identifier == "intune" || identifier == "microsoft"
    }
}

/// Repository of MDM vendor definitions
class MDMVendorRegistry {
    static let shared = MDMVendorRegistry()
    private let logger = Logger.shared
    
    /// All supported MDM vendors
    private(set) var vendors: [String: MDMVendorDefinition]
    
    private init() {
        // Initialize vendor definitions
        vendors = [
            "intune": MDMVendorDefinition(
                identifier: "intune",
                displayName: "Microsoft Intune",
                profilePatterns: [
                    "com.microsoft.intune",
                    "com.microsoft.enterprise",
                    "Microsoft.Intune",
                    "Microsoft.Profiles.MDM",
                    "Microsoft.Profiles"
                ],
                binaryPaths: [
                    "/Applications/Company Portal.app",
                    "/Library/Intune"
                ],
                certificatePatterns: [
                    "Microsoft Intune",
                    "Intune MDM",
                    "Microsoft Corporation"
                ],
                agentPaths: [
                    "/Library/Intune/Microsoft Intune Agent.app"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles remove -identifier 'Microsoft.Profiles.MDM'",
                    "profiles remove -identifier 'Microsoft.Intune'",
                    "profiles -D" // Fallback aggressive removal
                ],
                detectionPriority: 10
            ),
            "jamf": MDMVendorDefinition(
                identifier: "jamf",
                displayName: "Jamf Pro",
                profilePatterns: [
                    "com.jamf",
                    "com.jamfsoftware"
                ],
                binaryPaths: [
                    "/usr/local/bin/jamf",
                    "/usr/local/jamf/bin/jamf"
                ],
                certificatePatterns: [
                    "JAMF",
                    "jamf",
                    "JSS"
                ],
                agentPaths: [
                    "/Library/Application Support/JAMF",
                    "/usr/local/jamf"
                ],
                managementType: "Agent & MDM",
                removalCommands: [
                    "jamf removeFramework",
                    "profiles -D"
                ],
                detectionPriority: 20
            ),
            "kandji": MDMVendorDefinition(
                identifier: "kandji",
                displayName: "Kandji MDM",
                profilePatterns: [
                    "io.kandji",
                    "com.kandji"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "Kandji",
                    "kandji.io"
                ],
                agentPaths: [
                    "/Library/Kandji",
                    "/Library/Kandji/Kandji Agent.app"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "launchctl unload /Library/LaunchDaemons/io.kandji.*.plist",
                    "profiles -D"
                ],
                detectionPriority: 30
            ),
            "mosyle": MDMVendorDefinition(
                identifier: "mosyle",
                displayName: "Mosyle MDM",
                profilePatterns: [
                    "com.mosyle",
                    "business.mosyle"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "Mosyle",
                    "mosyle.com"
                ],
                agentPaths: [
                    "/Library/Application Support/Mosyle",
                    "/Library/Mosyle"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles -D"
                ],
                detectionPriority: 40
            ),
            "workspace": MDMVendorDefinition(
                identifier: "workspace",
                displayName: "VMware Workspace ONE",
                profilePatterns: [
                    "com.air-watch",
                    "com.airwatch",
                    "com.vmware.workspace",
                    "Airwatch",
                    "AirWatch",
                    "Workspace ONE",
                    "Intelligent Hub"
                ],
                binaryPaths: [
                    "/Applications/Workspace ONE Intelligent Hub.app",
                    "/Applications/VMware AirWatch Agent.app"
                ],
                certificatePatterns: [
                    "AirWatch",
                    "VMware",
                    "Workspace ONE",
                    "awmdm.com"
                ],
                agentPaths: [
                    "/Applications/Workspace ONE Intelligent Hub.app",
                    "/Library/Application Support/AirWatch",
                    "/Library/Application Support/VMware"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles remove -type enrollment",
                    "launchctl unload /Library/LaunchDaemons/com.air-watch.*.plist",
                    "launchctl unload /Library/LaunchDaemons/com.vmware.*.plist",
                    "rm -rf /Library/Application\\ Support/AirWatch",
                    "profiles -D"
                ],
                detectionPriority: 50
            ),
            "addigy": MDMVendorDefinition(
                identifier: "addigy",
                displayName: "Addigy",
                profilePatterns: [
                    "com.addigy"
                ],
                binaryPaths: [
                    "/usr/local/bin/addigy"
                ],
                certificatePatterns: [
                    "Addigy",
                    "addigy.com"
                ],
                agentPaths: [
                    "/Library/Addigy",
                    "/Library/Application Support/Addigy"
                ],
                managementType: "Agent & MDM",
                removalCommands: [
                    "profiles -D"
                ],
                detectionPriority: 60
            ),
            "meraki": MDMVendorDefinition(
                identifier: "meraki",
                displayName: "Cisco Meraki",
                profilePatterns: [
                    "com.meraki"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "Meraki",
                    "Cisco Systems"
                ],
                agentPaths: [
                    "/Library/Application Support/Meraki"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles -D"
                ],
                detectionPriority: 70
            ),
            "hexnode": MDMVendorDefinition(
                identifier: "hexnode",
                displayName: "Hexnode MDM",
                profilePatterns: [
                    "com.hexnode",
                    "me.hexnode"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "Hexnode",
                    "hexnode.com"
                ],
                agentPaths: [
                    "/Library/Application Support/Hexnode",
                    "/Applications/Hexnode MDM.app"
                ],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles -D"
                ],
                detectionPriority: 80
            ),
            "filewave": MDMVendorDefinition(
                identifier: "filewave",
                displayName: "FileWave",
                profilePatterns: [
                    "com.filewave"
                ],
                binaryPaths: [
                    "/usr/local/bin/fwcontrol"
                ],
                certificatePatterns: [
                    "FileWave",
                    "filewave.com"
                ],
                agentPaths: [
                    "/Library/FileWave",
                    "/usr/local/filewave"
                ],
                managementType: "Agent & MDM",
                removalCommands: [
                    "fwcontrol uninstall",
                    "profiles -D"
                ],
                detectionPriority: 90
            ),
            "apple": MDMVendorDefinition(
                identifier: "apple",
                displayName: "Apple Business/School Manager",
                profilePatterns: [
                    "com.apple.mdm",
                    "com.apple.configuration"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "Apple MDM",
                    "ABM",
                    "ASM"
                ],
                agentPaths: [],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles -D"
                ],
                detectionPriority: 100
            ),
            "micromdm": MDMVendorDefinition(
                identifier: "micromdm",
                displayName: "MicroMDM",
                profilePatterns: [
                    "io.micromdm",
                    "micromdm.io",
                    "com.github.micromdm"
                ],
                binaryPaths: [],
                certificatePatterns: [
                    "MicroMDM CA"
                ],
                agentPaths: [],
                managementType: "Full MDM",
                removalCommands: [
                    "profiles remove -identifier 'io.micromdm.mdm'"
                ],
                detectionPriority: 110
            )
        ]
        
        logger.info("MDM Vendor Registry initialized with \(vendors.count) vendors")
    }
    
    /// Get vendor definition by identifier
    func getVendor(identifier: String) -> MDMVendorDefinition? {
        return vendors[identifier]
    }
    
    /// Get vendor definition by profile identifier pattern
    func getVendorByProfilePattern(_ pattern: String) -> MDMVendorDefinition? {
        for (_, vendor) in vendors {
            for profilePattern in vendor.profilePatterns {
                if pattern.contains(profilePattern) {
                    return vendor
                }
            }
        }
        return nil
    }
    
    /// Get vendor-specific removal commands
    func getRemovalCommands(forVendor identifier: String) -> [String] {
        return vendors[identifier]?.removalCommands ?? ["profiles -D"]
    }
    
    /// Get ordered list of vendors by detection priority
    func getVendorsByPriority() -> [MDMVendorDefinition] {
        return vendors.values.sorted(by: { $0.detectionPriority < $1.detectionPriority })
    }
    
    /// Create MDMVendorInfo from a vendor definition
    func createVendorInfo(from definition: MDMVendorDefinition, version: String? = nil) -> MDMVendorInfo {
        return MDMVendorInfo(
            identifier: definition.identifier,
            displayName: definition.displayName,
            version: version,
            managementType: definition.managementType,
            profileIdentifiers: definition.profilePatterns,
            isIntune: definition.isIntune
        )
    }
    
    /// Add or update a vendor definition at runtime
    func registerVendor(_ vendor: MDMVendorDefinition) {
        vendors[vendor.identifier] = vendor
        logger.info("Registered MDM vendor: \(vendor.displayName)")
    }
}
