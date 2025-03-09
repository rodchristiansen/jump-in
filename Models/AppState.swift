import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
   @Published var isAuthorized = false
   @Published var showError = false
   @Published var errorMessage = ""
   
   private let logger = Logger.shared
   private let helperManager = HelperToolServiceManager.shared

   func requestPrivileges() async {
       logger.info("Starting privilege request")
       
       // If running as root, automatically authorize
       if getuid() == 0 {
           logger.info("Running as root, automatically authorized")
           isAuthorized = true
           showError = false
           errorMessage = ""
           return
       }
       
       // Check if helper is already running
       if helperManager.isHelperToolRunning {
           logger.info("Helper already running, setting authorized")
           isAuthorized = true
           showError = false
           errorMessage = ""
           return
       }
       
       do {
           logger.info("Checking helper installation: \(helperManager.isHelperToolInstalled)")
           logger.info("Helper running status: \(helperManager.isHelperToolRunning)")
           
           // Try to install helper tool if not installed
           if !helperManager.isHelperToolInstalled {
               logger.info("Installing helper tool")
               do {
                   try await helperManager.installHelperTool()
                   logger.info("Helper tool installation completed")
               } catch {
                   #if DEBUG
                   // In debug mode, continue even if helper tool installation fails
                   logger.warning("Helper tool installation failed, but continuing in debug mode: \(error.localizedDescription)")
                   #else
                   throw error
                   #endif
               }
           }
           
           // Don't try to get helper proxy here - consider installation success sufficient
           logger.info("Authorization successful")
           isAuthorized = true
           showError = false
           errorMessage = ""
           logger.info("Successfully authorized")
           
       } catch {
           logger.error("Authorization failed: \(error)")
           
           #if DEBUG
           // In debug mode, auto-authorize for testing
           logger.warning("Debug mode: Auto-authorizing despite error")
           isAuthorized = true
           showError = false
           errorMessage = ""
           #else
           isAuthorized = false
           errorMessage = "Failed to authorize: \(error.localizedDescription)"
           showError = true
           logger.error("Failed to authorize: \(error)")
           #endif
       }
   }
}
