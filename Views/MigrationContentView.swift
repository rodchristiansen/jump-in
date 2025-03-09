import SwiftUI

struct MigrationContentView: View {
    @State private var resultMessage = "Ready to check for current Intune profile."
    
    var body: some View {
        VStack {
            Text("Welcome to Intune Tenant Switch")
                .font(.headline)
                .padding()
            
            Button(action: {
                startMigration()
            }) {
                Text("Start Migration")
                    .font(.title)
                    .padding()
            }
            
            Button(action: {
                NSApplication.shared.terminate(self)
            }) {
                Text("Exit")
                    .font(.title)
                    .padding()
            }
            
            Text(resultMessage)
                .padding()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
    }
    
    // Function to start the migration and prompt for credentials
    func startMigration() {
        runWithSudo(command: "/usr/bin/profiles", arguments: ["-L"]) { result in
            DispatchQueue.main.async {
                self.resultMessage = result.contains("Microsoft.Intune") || result.contains("Microsoft.Profiles") ?
                    "Current Intune profile found." : "No Intune profile found."
            }
        }
    }
    
    // Function to run a command using osascript for sudo prompt
    func runWithSudo(command: String, arguments: [String], completion: @escaping (String) -> Void) {
        // Create the AppleScript string to run the command as sudo
        let commandString = "\(command) \(arguments.joined(separator: " "))"
        let script = """
        do shell script "\(commandString)" with administrator privileges
        """

        // Run osascript with the above script to prompt for sudo password
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "No output"
        
        completion(output)
    }
}
