import Foundation
import SwiftUI

/**
 * FileVault Rotation Test Script
 * This standalone script tests the FileVault rotation functionality
 * independently of the full migration process.
 */
class FileVaultTest {
    private let logger = Logger.shared
    
    func runTest() async {
        logger.info("Starting FileVault rotation test")
        
        // 1. Check if FileVault is enabled
        let isFileVaultEnabled = await checkFileVaultStatus()
        if !isFileVaultEnabled {
            logger.error("FileVault is not enabled on this system. Please enable it before testing.")
            await showAlert(title: "FileVault Not Enabled",
                          message: "FileVault is not enabled on this system. Please enable it before testing.")
            return
        }
        
        // 2. Test rotation using SecureFileVaultManager
        logger.info("Testing rotation with SecureFileVaultManager")
        do {
            try await testSecureFileVaultManager()
        } catch {
            logger.error("SecureFileVaultManager rotation failed: \(error.localizedDescription)")
            await testFallbackMethod()
        }
    }
    
    private func checkFileVaultStatus() async -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
            process.arguments = ["status"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            logger.info("FileVault status check result: \(output)")
            return output.contains("FileVault is On")
        } catch {
            logger.error("Error checking FileVault status: \(error.localizedDescription)")
            return false
        }
    }
    
    private func testSecureFileVaultManager() async throws {
        logger.info("Creating instance of SecureFileVaultManager...")
        let secureManager = SecureFileVaultManager()
        
        logger.info("Calling rotateFileVaultKey...")
        try await secureManager.rotateFileVaultKey()
        
        logger.info("SecureFileVaultManager rotation completed successfully!")
        await showAlert(title: "Success",
                      message: "SecureFileVaultManager rotation completed successfully!")
    }
    
    private func testFallbackMethod() async {
        logger.info("Testing fallback rotation method")
        
        do {
            // Create a temporary script for FileVault rotation that uses the interactive approach
            let tempScriptPath = "/private/tmp/filevault_test_\(UUID().uuidString).sh"
            
            let scriptContent = """
            #!/bin/bash

            # Get the current console user
            CURRENT_USER=$(who | grep console | awk '{print $1}')
            echo "Current user: $CURRENT_USER"

            # Show information dialog
            osascript -e 'display dialog "You will now be prompted for your login password to rotate your FileVault recovery key." buttons {"Continue"} default button "Continue" with icon note'

            # Use the direct fdesetup approach
            OUTPUT=$(sudo -u "$CURRENT_USER" /usr/bin/security authorizationdb write com.apple.fdesetup.authrestart allow)
            echo "Auth result: $OUTPUT"

            # Use the interactive approach
            echo "Running fdesetup changerecovery..."
            OUTPUT=$(fdesetup changerecovery -personal 2>&1)
            RESULT=$?
            
            echo "fdesetup result: $RESULT"
            echo "fdesetup output: $OUTPUT"

            if [ $RESULT -ne 0 ]; then
                if [[ "$OUTPUT" == *"Error: User canceled"* ]]; then
                    osascript -e 'display dialog "FileVault key rotation was canceled." buttons {"OK"} default button "OK" with icon caution'
                    echo "User canceled"
                    exit 0
                else
                    osascript -e 'display dialog "Failed to rotate FileVault key: '"$OUTPUT"'" buttons {"OK"} default button "OK" with icon stop'
                    echo "Error occurred"
                    exit 1
                fi
            fi

            # Show the recovery key to the user
            osascript -e 'display dialog "Your new FileVault recovery key is:\\n\\n'"$OUTPUT"'\\n\\nPlease store this key in a safe place." buttons {"OK"} default button "OK" with icon caution'

            echo "FileVault key rotation completed successfully."
            exit 0
            """
            
            logger.info("Writing test script to \(tempScriptPath)")
            try scriptContent.write(to: URL(fileURLWithPath: tempScriptPath), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)
            
            // Execute the script with proper permissions for GUI access
            logger.info("Executing test script...")
            let command = """
            do shell script "'\(tempScriptPath)'" with administrator privileges
            """
            
            logger.info("Using osascript to execute script with privileges")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", command]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            logger.info("Process started, waiting for completion...")
            
            // Set a timeout for the process
            let timeoutTask = DispatchWorkItem {
                if process.isRunning {
                    logger.warning("Process timed out, terminating...")
                    process.terminate()
                }
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeoutTask)
            
            process.waitUntilExit()
            timeoutTask.cancel()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            // Clean up the temporary script
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            
            logger.info("Script output: \(output)")
            if !error.isEmpty {
                logger.error("Script error: \(error)")
            }
            
            if process.terminationStatus != 0 {
                logger.error("FileVault key rotation failed with status: \(process.terminationStatus)")
                await showAlert(title: "Rotation Failed",
                              message: "FileVault key rotation failed: \(error)")
            } else {
                logger.info("FileVault key rotation completed successfully")
                await showAlert(title: "Success",
                              message: "Fallback rotation method completed successfully!")
            }
            
        } catch {
            logger.error("Failed to execute fallback rotation: \(error.localizedDescription)")
            await showAlert(title: "Error",
                          message: "Failed to execute fallback rotation: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// Helper function to run the test
func testFileVaultRotation() async {
    let tester = FileVaultTest()
    await tester.runTest()
}

// Execute the test when called
await testFileVaultRotation()
