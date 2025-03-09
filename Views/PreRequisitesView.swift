import SwiftUI
import Foundation

struct PreRequisitesView: View {
    @StateObject private var migrationService = MigrationService.shared
    @State private var navigateToMigration = false
    @State private var checkingInProgress = false
    @State private var showTenantPrompt = false
    @State private var targetTenantName = ""
    @State private var debugMessage: String = ""
    @State private var showDebugAlert = false
    @State private var mdmVendorInfo: MDMVendorInfo?
    
    private let privilegedService = PrivilegedService.shared
    private let systemRequirements = SystemRequirements()
    private let logger = Logger.shared
    private let mdmDetectionService = MDMDetectionService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                Text("System Requirements")
                    .font(.largeTitle)
                    .padding(.top, 30)
                
                // MDM Vendor Display
                if let mdmInfo = mdmVendorInfo {
                    MDMVendorInfoView(mdmInfo: mdmInfo)
                }
                
                Text("Checking your Mac's compatibility for MDM migration")
                    .foregroundColor(.secondary)
                
                // Requirements List
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RequirementRow(
                            title: "MDM Enrollment",
                            description: "Checking current MDM enrollment",
                            isChecked: migrationService.migrationState.prerequisites.isMDMEnrolled
                        )
                        
                        RequirementRow(
                            title: "macOS Version",
                            description: "Checking system compatibility",
                            isChecked: migrationService.migrationState.prerequisites.isMacOSCompatible
                        )
                        
                        RequirementRow(
                            title: "FileVault",
                            description: "Checking disk encryption status",
                            isChecked: migrationService.migrationState.prerequisites.isFileVaultEnabled
                        )
                        
                        RequirementRow(
                            title: "Security Settings",
                            description: "Checking system security",
                            isChecked: migrationService.migrationState.prerequisites.isGatekeeperEnabled
                        )
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxHeight: 200)
                
                Spacer(minLength: 20)
                
                #if DEBUG
                // Debug Section
                VStack(spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        Button("Test Privileges") {
                            Task {
                                await testPrivileges()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Button("Detect MDM") {
                            Task {
                                await detectMDMVendor()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button("Print Logs") {
                            printDebugLogs()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.gray)
                    }
                    
                    if !debugMessage.isEmpty {
                        Text(debugMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                #endif
                
                Spacer()
                
                // Action Buttons - Made them always visible regardless of scroll position
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await performRequirementChecks()
                        }
                    } label: {
                        HStack {
                            if checkingInProgress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            }
                            Text("Check Requirements")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(checkingInProgress)
                    
                    Button {
                        if migrationService.migrationState.targetMDMVendor?.isIntune == true {
                            showTenantPrompt = true
                        } else {
                            Task {
                                await startMigration()
                            }
                        }
                    } label: {
                        Text("Start Migration")
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!migrationService.migrationState.prerequisites.allPrerequisitesMet || checkingInProgress)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
                .background(Color(.windowBackgroundColor))  // Add background to ensure visibility
            }
            .padding(30)
            .frame(width: 700, height: 600)
            .onAppear {
                Task {
                    // Update root status if running as root
                    if getuid() == 0 {
                        logger.info("Running as root, updating privileges in requirements")
                        migrationService.migrationState.updatePrerequisites(
                            isMDMEnrolled: true,
                            isMacOSCompatible: true,
                            isFileVaultEnabled: true,
                            isGatekeeperEnabled: true
                        )
                    }
                    
                    await performRequirementChecks()
                }
            }
            .navigationDestination(isPresented: $navigateToMigration) {
                MigrationProgressView()
            }
            .sheet(isPresented: $showTenantPrompt) {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        
                    Text("Enter Target Tenant")
                        .font(.headline)
                        
                    Text("Please enter the name or identifier of the target Intune tenant you want to migrate to.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        
                    TextField("Target Tenant Name/ID", text: $targetTenantName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)
                        .padding(.vertical)
                        
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            showTenantPrompt = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Confirm") {
                            migrationService.migrationState.targetTenantName = targetTenantName
                            showTenantPrompt = false
                            Task {
                                await startMigration()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(targetTenantName.isEmpty)
                    }
                }
                .padding(30)
                .frame(width: 400, height: 300)
            }
            .alert("Debug Info", isPresented: $showDebugAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(debugMessage)
            }
        }
    }
    
    // MARK: - Supporting Views
    struct RequirementRow: View {
        let title: String
        let description: String
        let isChecked: Bool
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isChecked ? .green : .red)
                    .font(.system(size: 16))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
    }
    
    // Fix for MDMVendorInfoView in PreRequisitesView.swift

    struct MDMVendorInfoView: View {
        let mdmInfo: MDMVendorInfo
        
        var body: some View {
            VStack(spacing: 8) {
                // Current MDM
                HStack {
                    Text("Current MDM: ")
                        .fontWeight(.medium)
                    
                    if mdmInfo.identifier == "none" {
                        Text("None")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    } else {
                        Text(mdmInfo.displayName)
                            .fontWeight(.semibold)
                            .foregroundColor(mdmInfo.isIntune ? .blue : .orange)
                    }
                }
                
                // Optional version
                if let version = mdmInfo.version, mdmInfo.identifier != "none" {
                    Text("Version: \(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if mdmInfo.identifier != "none" {
                    Text("Management Type: \(mdmInfo.managementType)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Always show Intune as the target MDM
                Text("Target MDM: Microsoft Intune")
                    .padding(.top, 4)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .background(Color.blue.opacity(0.05))
            .cornerRadius(10)
        }
    }

    
    // Fix for PreRequisitesView.swift to properly handle MDM detection

    private func performRequirementChecks() async {
        logger.info("Starting system requirement checks")
        checkingInProgress = true
        
        // Detect MDM vendor first
        let detectedVendor = await mdmDetectionService.detectPrimaryMDM()
        await MainActor.run {
            self.mdmVendorInfo = detectedVendor
        }
        
        // If running as root, update prerequisite status directly
        if getuid() == 0 {
            logger.info("Running as root, skipping checks but using detected vendor info")
            
            // Only consider enrolled if an actual MDM is detected (not "none")
            let isEnrolled = (detectedVendor.identifier != "none")
            await MainActor.run {
                migrationService.migrationState.updatePrerequisites(
                    isMDMEnrolled: isEnrolled,
                    mdmVendorInfo: detectedVendor,
                    isMacOSCompatible: true,
                    isFileVaultEnabled: true,
                    isGatekeeperEnabled: true
                )
            }
            checkingInProgress = false
            return
        }
        
        do {
            // Get system status with the enhanced detection
            let status = await systemRequirements.performAllChecks()
            
            // Update migration state with all system checks - ensure mdmVendorInfo is properly passed
            await MainActor.run {
                migrationService.migrationState.updatePrerequisites(
                    isMDMEnrolled: detectedVendor.identifier != "none",
                    mdmVendorInfo: detectedVendor,
                    isMacOSCompatible: status.isMacOSCompatible,
                    isFileVaultEnabled: status.isFileVaultEnabled,
                    isGatekeeperEnabled: status.isGatekeeperEnabled
                )
            }
        } catch {
            logger.error("Requirement checks failed: \(error.localizedDescription)")
        }
        
        checkingInProgress = false
    }
    
    private func startMigration() async {
        logger.info("Starting MDM migration process")
        
        do {
            // Navigate to progress view first
            await MainActor.run {
                navigateToMigration = true
            }
            
            // Create an appropriate migration strategy
            let sourceMDM = migrationService.migrationState.sourceMDMVendor ?? MDMVendorInfo.none
            let targetMDM = migrationService.migrationState.targetMDMVendor ?? MDMVendorInfo.intune
            
            let strategy = MDMMigrationStrategy(sourceMDM: sourceMDM, targetMDM: targetMDM)
            
            // Then start the migration
            try await Task.sleep(nanoseconds: 1_000_000_000) // Small delay to ensure view transition
            try await strategy.executeMigration()
        } catch {
            logger.error("Failed to start migration: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Debug Methods
    #if DEBUG
    private func testPrivileges() async {
        do {
            let isRoot = try await privilegedService.testPrivileges()
            debugMessage = "Root privileges: \(isRoot)\nUser ID: \(getuid())"
            logger.info("Root privileges test: \(isRoot)")
            showDebugAlert = true
        } catch {
            debugMessage = "Error: \(error.localizedDescription)"
            logger.error("Privilege test failed: \(error.localizedDescription)")
            showDebugAlert = true
        }
    }
    
    private func detectMDMVendor() async {
        let vendor = await mdmDetectionService.detectPrimaryMDM()
        await MainActor.run {
            self.mdmVendorInfo = vendor
            debugMessage = """
            Detected MDM: \(vendor.displayName)
            Identifier: \(vendor.identifier)
            Version: \(vendor.version ?? "Unknown")
            Management Type: \(vendor.managementType)
            Is Intune: \(vendor.isIntune ? "Yes" : "No")
            """
            showDebugAlert = true
        }
        
        logger.info("MDM detection: \(vendor.displayName) (\(vendor.identifier))")
    }
    
    private func printDebugLogs() {
        logger.info("=== Debug Information ===")
        logger.info("Root status: \(getuid() == 0 ? "Running as root" : "Not root")")
        logger.info("User ID: \(getuid())")
        logger.info("Current MDM: \(mdmVendorInfo?.displayName ?? "Unknown")")
        logger.info("Prerequisites met: \(migrationService.migrationState.prerequisites.allPrerequisitesMet)")
        logger.info("Current phase: \(migrationService.currentStatus)")
        debugMessage = "Debug logs printed to console"
        showDebugAlert = true
    }
    #endif
}
