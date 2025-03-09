import SwiftUI

struct FileVaultRotationView: View {
    @State private var isRotating = false
    @State private var isCompleted = false
    @State private var resultMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 30)
            
            Text("Final Security Step")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Rotate your FileVault recovery key to complete the migration")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if !isCompleted {
                Button {
                    rotateFileVaultKey()
                } label: {
                    HStack {
                        if isRotating {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                                .padding(.trailing, 5)
                        } else {
                            Image(systemName: "key.fill")
                                .padding(.trailing, 5)
                        }
                        Text(isRotating ? "Rotating Key..." : "Rotate FileVault Key")
                    }
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isRotating)
                .padding(.vertical, 20)
            } else {
                Text(resultMessage)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.vertical, 20)
                
                Button("Exit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func rotateFileVaultKey() {
        isRotating = true
        
        // Execute fdesetup with admin privileges
        let script = """
        do shell script "fdesetup changerecovery -personal" with administrator privileges
        """
        
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        
        isRotating = false
        isCompleted = true
        
        if let error = error {
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            if errorMessage.contains("User canceled") {
                resultMessage = "FileVault rotation was canceled.\n\nYou can rotate your key later through System Settings."
            } else {
                resultMessage = "Failed to rotate FileVault key: \(errorMessage)"
            }
        } else if let recoveryKey = result?.stringValue, !recoveryKey.isEmpty {
            resultMessage = "Your new FileVault recovery key is:\n\n\(recoveryKey)\n\nPlease store this key in a safe place."
            
            // Copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recoveryKey, forType: .string)
        } else {
            resultMessage = "FileVault key rotation completed."
        }
    }
}
