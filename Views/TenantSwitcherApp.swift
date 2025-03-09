import SwiftUI
import UserNotifications

// MARK: - Main App
@main
struct TenantSwitcherApp: App {
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @State private var showFileVaultOnly = false
    let appDelegate = AppDelegate()
    
    init() {
        NSApplication.shared.delegate = appDelegate
        
        // Check if launched with --filevault-only flag
        if ProcessInfo.processInfo.arguments.contains("--filevault-only") {
            Logger.shared.info("Running in FileVault-only mode")
            self.showFileVaultOnly = true
            self.showSplash = false
            return // Skip the admin privileges check
        }
        
        // Check if running as root or if we're already in a relaunch attempt
        let isRoot = getuid() == 0
        let launchedByAdmin = ProcessInfo.processInfo.environment["SUDO_USER"] != nil
        let isAdminRelaunch = ProcessInfo.processInfo.arguments.contains("--admin-relaunch")
        
        Logger.shared.info("Application initialized with root privileges: \(isRoot), sudo environment: \(launchedByAdmin), admin relaunch: \(isAdminRelaunch)")
        
        // Only show the dialog if not root, not already launched by admin, and not an admin relaunch
        if !isRoot && !launchedByAdmin && !isAdminRelaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Administrator Privileges Required"
                alert.informativeText = "This app requires administrator privileges to function properly. Would you like to relaunch with admin privileges?"
                alert.addButton(withTitle: "Relaunch as Admin")
                alert.addButton(withTitle: "Continue")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // Use the actual installed app bundle path
                    guard let appBundlePath = Bundle.main.bundlePath as String? else {
                        Logger.shared.error("Could not determine app bundle path")
                        return
                    }
                    
                    let appPath = Bundle.main.bundlePath
                    let executableName = Bundle.main.executableURL?.lastPathComponent ?? "JUMP-IN"
                    let script = """
                    do shell script "'\(appPath)/Contents/MacOS/\(executableName)' --admin-relaunch" with administrator privileges
                    """
                    
                    Logger.shared.info("Attempting to relaunch with script: \(script)")
                    
                    // Use Process for more reliable execution
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = ["-e", script]
                    
                    // Add timeout
                    let timeoutTask = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                            Logger.shared.error("Relaunch timed out")
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutTask)
                    
                    do {
                        try process.run()
                        Logger.shared.info("Launched new instance as admin; terminating old instance now.")
                        exit(0)
                    } catch {
                        Logger.shared.error("Failed to start relaunch process: \(error)")
                    }
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if showFileVaultOnly {
                FileVaultRotationView()
            } else {
                MainContentView(showSplash: $showSplash, appState: appState)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - Main Content View
struct MainContentView: View {
    @Binding var showSplash: Bool
    @ObservedObject var appState: AppState
    
    var body: some View {
        Group {
            if showSplash {
                SplashView(isShowing: $showSplash)
            } else {
                if appState.isAuthorized || getuid() == 0 {
                    NavigationStack {
                        WelcomeView()
                    }
                } else {
                    RequestPrivilegesView(appState: appState)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            if let window = NSApplication.shared.windows.first {
                window.center()
                window.setFrameAutosaveName("MainWindow")
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setupMainWindow()
        
        // Only start notifications if not in FileVault-only mode
        if !ProcessInfo.processInfo.arguments.contains("--filevault-only") {
            NotificationService.shared.startMigrationNotifications()
        }
    }
    
    private func setupMainWindow() {
        if let window = NSApplication.shared.windows.first {
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.makeKeyAndOrderFront(nil)
            
            // Enable close button in FileVault mode, disable in main mode
            let isFileVaultMode = ProcessInfo.processInfo.arguments.contains("--filevault-only")
            window.standardWindowButton(.closeButton)?.isEnabled = isFileVaultMode
            window.isReleasedWhenClosed = false
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Only stop notifications in regular mode
        if !ProcessInfo.processInfo.arguments.contains("--filevault-only") {
            NotificationService.shared.stopNotifications()
        }
        logger.info("Application terminating, cleaned up resources")
    }
}
