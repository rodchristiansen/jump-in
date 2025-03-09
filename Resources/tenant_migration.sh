#!/bin/bash

#########################################################################################################
#
# macOS MDM Migration Script
#
# This script handles migration between MDM solutions, including from any MDM to Microsoft Intune.
# It detects the current MDM, removes profiles, and guides enrollment into the new MDM.
#
# Usage:
#   ./tenant_migration.sh [OPERATION_FLAG] [--source-mdm "vendor"] [--target-tenant "tenant name"] [--no-ui]
#
# Operation Flags:
#   --full-migration     Perform the complete migration process
#   --detect-mdm         Only detect current MDM solution
#   --backup-only        Only backup current profiles
#   --remove-only        Only remove current MDM profiles
#   --update-cp-only     Only update/install Company Portal
#   --rotate-fv-only     Only rotate FileVault recovery key
#   --enroll-only        Only perform enrollment in target tenant
#   --check-status       Only check current enrollment status
#
#########################################################################################################

# Enhanced logging function
log() {
    local log_level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Echo to stdout (which is redirected to the log file)
    echo "[$timestamp] $log_level: $message"
    
    # Also log to system log for troubleshooting
    /usr/bin/logger -t "JUMP-IN" "$log_level: $message"
}

# Function to set up logging
setup_logging() {
    # Create log directory if it doesn't exist
    LOG_DIR=$(dirname "$LOG_FILE")
    if [[ ! -d "$LOG_DIR" ]]; then
        log "INFO" "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    }
    
    # Start logging to file and stdout
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    log "INFO" "========================================================"
    log "INFO" "macOS MDM Migration Tool v$SCRIPT_VERSION started"
    log "INFO" "Running as user: $(whoami)"
    log "INFO" "macOS Version: $(sw_vers -productVersion)"
    log "INFO" "Parameters: OPERATION=$OPERATION, SOURCE_MDM=$SOURCE_MDM, TARGET_TENANT=$TARGET_TENANT, USE_UI=$USE_UI"
    log "INFO" "========================================================"
}

# Function to show completion and relaunch for FileVault
show_migration_complete_and_relaunch() {
    echo "$(date) | Migration completed successfully, preparing for FileVault rotation"
    
    # Create a temporary script that will run after app closes
    FV_LAUNCHER="/tmp/fv_launcher_$(date +%s).sh"
    APP_PATH="$(cd "$(dirname "$0")" && pwd)"
    APP_BUNDLE_PATH="$(find '/Applications' -name 'JUMP-IN.app' -maxdepth 1 2>/dev/null || echo "$APP_PATH")"
    
    cat > "$FV_LAUNCHER" << EOF
#!/bin/bash

# Wait for current process to exit
sleep 2

# Get current console user
CONSOLE_USER=\$(who | grep console | head -1 | awk '{print \$1}')

# Verify we found a console user
if [ -z "\$CONSOLE_USER" ]; then
    echo "Error: Could not determine console user" >&2
    osascript -e 'display notification "Error: Could not determine console user" with title "MDM Migration Error"'
    exit 1
fi

# Create notification
osascript -e 'display notification "Launching FileVault rotation" with title "MDM Migration" subtitle "Final Security Step"'

# Check if we found the app bundle
if [[ -d "$APP_BUNDLE_PATH" && "$APP_BUNDLE_PATH" == *".app" ]]; then
    echo "Launching app bundle: $APP_BUNDLE_PATH with --filevault-only flag"
    # The key part: launch as non-root user with the filevault-only flag
    sudo -u "\$CONSOLE_USER" open "$APP_BUNDLE_PATH" --args --filevault-only
else
    # Fallback to direct execution
    echo "App bundle not found, using script path: $APP_PATH"
    sudo -u "\$CONSOLE_USER" "$APP_PATH/tenant_migration.sh" --rotate-fv-only
fi

# Remove this script
rm -f "\$0"
EOF
    
    # Make it executable
    chmod +x "$FV_LAUNCHER"
    
    # Show completion dialog
    if [ "$USE_UI" = true ]; then
        /usr/local/bin/dialog \
            --title "Migration Complete" \
            --message "Your Mac has been successfully migrated to the new tenant.\n\nAs a final security step, the app will now close and relaunch for FileVault key rotation.\n\nThis will prompt for your regular user password to update your FileVault recovery key." \
            --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarInfo.icns \
            --button1text "Continue" \
            --width 600 \
            --height 350 \
            --blurscreen
    else
        echo "=============================="
        echo "MIGRATION COMPLETED SUCCESSFULLY"
        echo "=============================="
        echo "The app will now relaunch for FileVault key rotation"
        echo "=============================="
    fi
    
    # Execute the launcher script in background and exit current process
    nohup "$FV_LAUNCHER" >/dev/null 2>&1 &
    exit 0
}

# Add enhanced logging to MDM detection function
detect_mdm_vendor() {
    log "INFO" "Detecting current MDM solution"
    
    # Check for profiles first
    log "INFO" "Executing profiles list command"
    profiles_output=$(profiles list 2>&1)
    
    if [ $? -ne 0 ]; then
        log "WARNING" "profiles command failed: $profiles_output"
    }
    
    # Add logging for each vendor check
    if echo "$profiles_output" | grep -q -E '(Microsoft\.Intune|Microsoft\.Profiles|com\.microsoft\.enterprise)'; then
        CURRENT_MDM="intune"
        log "INFO" "Detected Microsoft Intune"
        return 0
    }
    
    if echo "$profiles_output" | grep -q -E '(com\.jamf|com\.jamfsoftware)' || [ -f "/usr/local/bin/jamf" ] || [ -f "/usr/local/jamf/bin/jamf" ]; then
        CURRENT_MDM="jamf"
        log "INFO" "Detected Jamf Pro"
        return 0
    }
    
    # And so on for each vendor check...
    
    # No MDM detected
    CURRENT_MDM="none"
    log "INFO" "No MDM solution detected"
    return 1
}

# Configuration variables
LOG_FILE="/Library/Application Support/JUMP-IN/Logs/mdm_migration.log"
COMPANY_PORTAL_URL="https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/CompanyPortal-Installer.pkg"
BACKUP_DIR="/Library/Application Support/MDMMigration/Backups"
SCRIPT_VERSION="2.1"

# Initialize variables
FILEVAULT_ENABLED=false
CURRENT_MDM=""
SOURCE_MDM=""
TARGET_TENANT=""
ADE_ENROLLED=false
COMMAND_FILE="/var/tmp/dialog.log"
USE_UI=true
OPERATION="full-migration"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --full-migration|--detect-mdm|--backup-only|--remove-only|--update-cp-only|--rotate-fv-only|--enroll-only|--check-status)
            OPERATION="${key:2}"  # Remove leading -- from operation name
            shift
            ;;
        --source-mdm)
            SOURCE_MDM="$2"
            shift
            shift
            ;;
        --target-tenant)
            TARGET_TENANT="$2"
            shift
            shift
            ;;
        --no-ui)
            USE_UI=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            shift
            ;;
    esac
done



# Function to set up logging
setup_logging() {
    # Create log directory if it doesn't exist
    LOG_DIR=$(dirname "$LOG_FILE")
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    fi
    
    # Start logging to file and stdout
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    echo "$(date) | macOS MDM Migration Tool v$SCRIPT_VERSION started"
    echo "$(date) | Running as user: $(whoami)"
    echo "$(date) | macOS Version: $(sw_vers -productVersion)"
    echo "$(date) | Parameters: OPERATION=$OPERATION, SOURCE_MDM=$SOURCE_MDM, TARGET_TENANT=$TARGET_TENANT, USE_UI=$USE_UI"
}

# Function to check and install SwiftDialog if UI is enabled
install_swiftdialog() {
    if [ "$USE_UI" = false ]; then
        echo "$(date) | UI disabled, skipping SwiftDialog check"
        return 0
    fi
    
    if [ ! -f "/usr/local/bin/dialog" ]; then
        echo "$(date) | SwiftDialog not found. Installing..."
        curl -L -o /tmp/dialog.pkg "https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.2/dialog-2.5.2-4777.pkg"
        installer -pkg /tmp/dialog.pkg -target /
        rm /tmp/dialog.pkg
        echo "$(date) | SwiftDialog installed successfully"
    else
        echo "$(date) | SwiftDialog is already installed"
    fi
}

# Function to detect MDM vendor
detect_mdm_vendor() {
    echo "$(date) | Detecting current MDM solution"
    
    # Check for profiles first
    profiles_output=$(profiles list 2>/dev/null)
    
    # Check for Microsoft Intune
    if echo "$profiles_output" | grep -q -E '(Microsoft\.Intune|Microsoft\.Profiles|com\.microsoft\.enterprise)'; then
        CURRENT_MDM="intune"
        echo "$(date) | Detected Microsoft Intune"
        return 0
    fi
    
    # Check for Jamf
    if echo "$profiles_output" | grep -q -E '(com\.jamf|com\.jamfsoftware)' || [ -f "/usr/local/bin/jamf" ] || [ -f "/usr/local/jamf/bin/jamf" ]; then
        CURRENT_MDM="jamf"
        echo "$(date) | Detected Jamf Pro"
        return 0
    fi
    
    # Check for Kandji
    if echo "$profiles_output" | grep -q -E '(io\.kandji|com\.kandji)' || [ -d "/Library/Kandji" ]; then
        CURRENT_MDM="kandji"
        echo "$(date) | Detected Kandji MDM"
        return 0
    fi
    
    # Check for Mosyle
    if echo "$profiles_output" | grep -q -E '(com\.mosyle|business\.mosyle)' || [ -d "/Library/Application Support/Mosyle" ]; then
        CURRENT_MDM="mosyle"
        echo "$(date) | Detected Mosyle MDM"
        return 0
    fi
    
    # Check for VMware Workspace ONE/AirWatch - comprehensive detection
if echo "$profiles_output" | grep -q -E '(com\.air-watch|com\.airwatch|com\.vmware)' ||
   [ -d "/Applications/Workspace ONE Intelligent Hub.app" ] ||
   [ -d "/Applications/VMware AirWatch Agent.app" ] ||
   [ -d "/Library/Application Support/AirWatch" ] ||
   [ -f "/Library/LaunchDaemons/com.airwatch.airwatchd.plist" ] ||
   [ -f "/Library/LaunchDaemons/com.vmware.hub.plist" ] ||
   profiles show 2>/dev/null | grep -q -E '(airwatch|Airwatch|Workspace|Hub|awmdm\.com)' ||
   profiles status -type enrollment 2>/dev/null | grep -q 'awmdm\.com'; then
    CURRENT_MDM="workspace"
    log "INFO" "Detected VMware Workspace ONE/AirWatch"
    return 0
fi
    
    # Check for Addigy
    if echo "$profiles_output" | grep -q -E '(com\.addigy)' || [ -d "/Library/Addigy" ]; then
        CURRENT_MDM="addigy"
        echo "$(date) | Detected Addigy"
        return 0
    fi
    
    # Check for generic MDM enrollment
    if echo "$profiles_output" | grep -q -E '(MDM|Profile)'; then
        CURRENT_MDM="unknown_mdm"
        echo "$(date) | Detected unknown MDM solution"
        return 0
    fi
    
    # No MDM detected
    CURRENT_MDM="none"
    echo "$(date) | No MDM solution detected"
    return 1
}

# Function to override detected MDM with command line parameter
set_mdm_vendor() {
    if [ -n "$SOURCE_MDM" ]; then
        echo "$(date) | Overriding detected MDM with specified value: $SOURCE_MDM"
        CURRENT_MDM="$SOURCE_MDM"
    fi
}

# Function to check if device is ADE enrolled
check_ade_enrollment() {
    echo "$(date) | Checking if device is ADE enrolled"
    
    if profiles status -type enrollment 2>/dev/null | grep -q "Enrolled via DEP: Yes"; then
        echo "$(date) | Device is ADE enrolled"
        ADE_ENROLLED=true
    else
        echo "$(date) | Device is not ADE enrolled"
        ADE_ENROLLED=false
    fi
}

# Function to check FileVault status
check_filevault() {
    echo "$(date) | Checking FileVault status"
    
    if fdesetup status | grep -q "FileVault is On"; then
        echo "$(date) | FileVault is enabled"
        FILEVAULT_ENABLED=true
    else
        echo "$(date) | FileVault is not enabled"
        FILEVAULT_ENABLED=false
    fi
}

# Function to install or update Company Portal
install_company_portal() {
    echo "$(date) | Checking Company Portal installation"
    
    if [ ! -d "/Applications/Company Portal.app" ] || [ "$1" == "force" ]; then
        echo "$(date) | Installing/updating Company Portal"
        curl -L -o /tmp/CompanyPortal.pkg "$COMPANY_PORTAL_URL"
        installer -pkg /tmp/CompanyPortal.pkg -target /
        rm -f /tmp/CompanyPortal.pkg
        echo "$(date) | Company Portal installed successfully"
        return 0
    else
        echo "$(date) | Company Portal is already installed"
        return 0
    fi
}

# Function to backup current MDM profiles
backup_mdm_profiles() {
    echo "$(date) | Backing up current MDM profiles"
    
    # Create timestamped backup directory with MDM vendor name
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="$BACKUP_DIR/${CURRENT_MDM}_$timestamp"
    
    mkdir -p "$backup_path"
    
    # Export profiles to backup directory
    profiles -P -o "$backup_path/profiles.plist"
    
    # Save current MDM info
    echo "Current MDM: $CURRENT_MDM" > "$backup_path/mdm_info.txt"
    date >> "$backup_path/mdm_info.txt"
    
    # Additional vendor-specific backups
    case "$CURRENT_MDM" in
        mosyle)
            echo "$(date) | Backing up Mosyle-specific data"
            if [ -d "/Library/Application Support/Mosyle" ]; then
                mkdir -p "$backup_path/mosyle"
                cp -R "/Library/Application Support/Mosyle/conf" "$backup_path/mosyle/" 2>/dev/null || true
            fi
            ;;
        workspace)
            echo "$(date) | Backing up VMware Workspace ONE specific data"
            if [ -d "/Library/Application Support/AirWatch" ]; then
                mkdir -p "$backup_path/airwatch"
                cp -R "/Library/Application Support/AirWatch/Data" "$backup_path/airwatch/" 2>/dev/null || true
            fi
            ;;
        addigy)
            echo "$(date) | Backing up Addigy-specific data"
            if [ -d "/Library/Addigy" ]; then
                mkdir -p "$backup_path/addigy"
                cp -R "/Library/Addigy/conf" "$backup_path/addigy/" 2>/dev/null || true
            fi
            ;;
        hexnode)
            echo "$(date) | Backing up Hexnode-specific data"
            if [ -d "/Library/Application Support/Hexnode" ]; then
                mkdir -p "$backup_path/hexnode"
                cp -R "/Library/Application Support/Hexnode" "$backup_path/hexnode/" 2>/dev/null || true
            fi
            ;;
        meraki)
            echo "$(date) | Backing up Meraki-specific data"
            if [ -d "/Library/Application Support/Meraki" ]; then
                mkdir -p "$backup_path/meraki"
                cp -R "/Library/Application Support/Meraki" "$backup_path/meraki/" 2>/dev/null || true
            fi
            ;;
        filewave)
            echo "$(date) | Backing up FileWave-specific data"
            if [ -d "/Library/FileWave" ]; then
                mkdir -p "$backup_path/filewave"
                cp -R "/Library/FileWave/Client" "$backup_path/filewave/" 2>/dev/null || true
            fi
            ;;
    esac
    
    echo "$(date) | MDM profiles backed up to: $backup_path"
    return 0
}

# Function to remove VMware AirWatch/Workspace ONE MDM profiles and components
remove_airwatch_profiles() {
    echo "$(date) | Removing VMware AirWatch/Workspace ONE MDM enrollment"

    # Define VMware AirWatch/Workspace ONE components
    DAEMON_PLIST="/Library/LaunchDaemons/com.airwatch.airwatchd.plist"
    AGENT_PLIST="/Library/LaunchAgents/com.airwatch.mac.agent.plist"
    AWCM_PLIST="/Library/LaunchDaemons/com.airwatch.awcmd.plist"
    SCHEDULER_PLIST="/Library/LaunchDaemons/com.airwatch.AWSoftwareUpdateScheduler.plist"
    REMOTE_PLIST="/Library/LaunchDaemons/com.airwatch.AWRemoteManagementDaemon.plist"
    REMOTETUNNEL_PLIST="/Library/LaunchDaemons/com.airwatch.AWRemoteTunnelAgent.plist"
    
    # Additional Workspace ONE components
    HUB_PLIST="/Library/LaunchDaemons/com.vmware.hub.plist"
    HUB_AGENT_PLIST="/Library/LaunchAgents/com.vmware.hub.agent.plist"
    
    # 1. Try using Hub to unenroll if available
    if [ -d "/Applications/Workspace ONE Intelligent Hub.app" ]; then
        echo "$(date) | Using Workspace ONE Intelligent Hub to unenroll"
        open -a "/Applications/Workspace ONE Intelligent Hub.app" --args -unenroll
        
        # Wait for potential unenrollment process to complete
        echo "$(date) | Waiting for Hub unenrollment to complete"
        sleep 10
    elif [ -d "/Applications/VMware AirWatch Agent.app" ]; then
        echo "$(date) | Using VMware AirWatch Agent to unenroll"
        open -a "/Applications/VMware AirWatch Agent.app" --args -unenroll
        
        # Wait for potential unenrollment process to complete
        echo "$(date) | Waiting for Agent unenrollment to complete"
        sleep 10
    fi
    
    # 2. Unload all LaunchDaemons and LaunchAgents
    echo "$(date) | Unloading LaunchDaemons and LaunchAgents"
    for plist in "$DAEMON_PLIST" "$AWCM_PLIST" "$SCHEDULER_PLIST" "$REMOTE_PLIST" "$REMOTETUNNEL_PLIST" "$HUB_PLIST"; do
        if [ -f "$plist" ]; then
            echo "$(date) | Unloading $plist"
            launchctl unload "$plist" 2>/dev/null || true
        fi
    done
    
    # Handle LaunchAgents for all users
    for user_home in /Users/*; do
        if [ -d "$user_home" ]; then
            user=$(basename "$user_home")
            if id "$user" &>/dev/null && [ "$user" != "Shared" ]; then
                uid=$(id -u "$user")
                
                # Unload user agents
                for plist in "$AGENT_PLIST" "$HUB_AGENT_PLIST"; do
                    echo "$(date) | Unloading $plist for user $user"
                    launchctl asuser "$uid" launchctl unload "$plist" 2>/dev/null || true
                    
                    # Also check in user-specific LaunchAgents folder
                    user_plist="$user_home/Library/LaunchAgents/$(basename "$plist")"
                    if [ -f "$user_plist" ]; then
                        echo "$(date) | Unloading user-specific $user_plist"
                        launchctl asuser "$uid" launchctl unload "$user_plist" 2>/dev/null || true
                    fi
                done
            fi
        fi
    done
    
    # 3. Remove profiles with AirWatch/VMware identifiers
    echo "$(date) | Removing VMware/AirWatch profiles"
    profiles_output=$(profiles list 2>/dev/null)
    
    # Extract profile identifiers related to AirWatch/VMware
    while read -r line; do
        if [[ $line =~ profileIdentifier:\ (.+) ]]; then
            profile_id="${BASH_REMATCH[1]}"
            if [[ $profile_id == *"airwatch"* ]] || [[ $profile_id == *"AirWatch"* ]] || [[ $profile_id == *"vmware"* ]] || [[ $profile_id == *"VMware"* ]]; then
                echo "$(date) | Removing profile: $profile_id"
                profiles remove -identifier "$profile_id" 2>/dev/null || true
            fi
        fi
    done <<< "$profiles_output"
    
    # 4. Remove MDM profile specifically
    echo "$(date) | Removing MDM profile"
    profiles -N remove || true
    
    # 5. Delete application files
    echo "$(date) | Removing application files"
    rm -rf "/Applications/VMware AirWatch Agent.app" 2>/dev/null || true
    rm -rf "/Applications/Workspace ONE Intelligent Hub.app" 2>/dev/null || true
    
    # 6. Delete LaunchDaemons and LaunchAgents plists
    echo "$(date) | Removing LaunchDaemons and LaunchAgents plists"
    for plist in "$DAEMON_PLIST" "$AWCM_PLIST" "$SCHEDULER_PLIST" "$REMOTE_PLIST" "$REMOTETUNNEL_PLIST" "$HUB_PLIST"; do
        rm -f "$plist" 2>/dev/null || true
    done
    
    # Handle LaunchAgents for all users
    for user_home in /Users/*; do
        if [ -d "$user_home" ]; then
            user=$(basename "$user_home")
            if [ "$user" != "Shared" ]; then
                # Remove user preferences and LaunchAgents
                rm -f "$user_home/Library/Preferences/com.airwatch.mac.agent.plist" 2>/dev/null || true
                rm -f "$user_home/Library/Preferences/com.airwatch.mac.enroller.plist" 2>/dev/null || true
                rm -f "$user_home/Library/Preferences/com.aiwatch.mac.enroller.plist" 2>/dev/null || true
                rm -f "$user_home/Library/Preferences/com.vmware.hub.plist" 2>/dev/null || true
                
                # Remove user-specific LaunchAgents
                rm -f "$user_home/Library/LaunchAgents/com.airwatch.mac.agent.plist" 2>/dev/null || true
                rm -f "$user_home/Library/LaunchAgents/com.vmware.hub.agent.plist" 2>/dev/null || true
            fi
        fi
    done
    
    # 7. Delete application support directories
    echo "$(date) | Removing application support directories"
    rm -rf "/Library/Application Support/AirWatch" 2>/dev/null || true
    rm -rf "/Library/Application Support/VMware" 2>/dev/null || true
    
    # 8. Kill any remaining processes
    echo "$(date) | Killing any remaining processes"
    pkill -f "AirWatch" 2>/dev/null || true
    pkill -f "Workspace ONE" 2>/dev/null || true
    pkill -f "VMware" 2>/dev/null || true
    
    # 9. Verify removal
    echo "$(date) | Verifying removal"
    profiles_after=$(profiles list 2>/dev/null)
    
    if echo "$profiles_after" | grep -q -E '(airwatch|vmware|AirWatch|VMware)'; then
        echo "$(date) | WARNING: Some VMware/AirWatch profiles may still be present"
        
        # Try more aggressive removal with profiles -D
        echo "$(date) | Attempting more aggressive profile removal"
        profiles -D
        
        # Final verification
        if profiles list 2>/dev/null | grep -q -E '(airwatch|vmware|AirWatch|VMware)'; then
            echo "$(date) | ERROR: Failed to remove all VMware/AirWatch profiles"
            return 1
        fi
    fi
    
    echo "$(date) | VMware AirWatch/Workspace ONE successfully removed"
    return 0
}

# Function to remove MDM profiles based on vendor
remove_mdm_profiles() {
    echo "$(date) | Removing MDM profiles for vendor: $CURRENT_MDM"
    
    # First try vendor-specific removal
    case "$CURRENT_MDM" in
        intune)
            echo "$(date) | Removing Microsoft Intune profiles"
            
            # Get list of profile identifiers
            profile_ids=()
            while read -r line; do
                if [[ $line =~ profileIdentifier:\ (.+) ]]; then
                    profile_id="${BASH_REMATCH[1]}"
                    if [[ $profile_id == *"Microsoft"* || $profile_id == *"microsoft"* ]]; then
                        profile_ids+=("$profile_id")
                    fi
                fi
            done < <(profiles list)
            
            # Remove each profile
            for profile_id in "${profile_ids[@]}"; do
                echo "$(date) | Removing profile: $profile_id"
                profiles remove -identifier "$profile_id"
            done
            ;;
            
        jamf)
            echo "$(date) | Removing Jamf MDM profiles"
            
            # Try jamf binary first
            if [ -f "/usr/local/bin/jamf" ]; then
                echo "$(date) | Using Jamf binary to remove MDM"
                /usr/local/bin/jamf removeFramework
                /usr/local/bin/jamf removeMdmProfile
            elif [ -f "/usr/local/jamf/bin/jamf" ]; then
                echo "$(date) | Using Jamf binary to remove MDM"
                /usr/local/jamf/bin/jamf removeFramework
                /usr/local/jamf/bin/jamf removeMdmProfile
            fi
            
            # Remove Jamf-related LaunchDaemons
            rm -f /Library/LaunchDaemons/com.jamf*.plist
            
            # Remove Jamf directories
            rm -rf "/Library/Application Support/JAMF"
            rm -rf "/usr/local/jamf"
            ;;
            
        kandji)
            echo "$(date) | Removing Kandji MDM profiles"
            
            # Stop Kandji services
            launchctl unload /Library/LaunchDaemons/io.kandji.*.plist 2>/dev/null || true
            
            # Remove Kandji agent
            rm -rf "/Library/Kandji"
            
            # Remove Kandji profiles
            local profile_ids=()
            while read -r line; do
                if [[ $line =~ profileIdentifier:\ (.+) ]]; then
                    profile_id="${BASH_REMATCH[1]}"
                    if [[ $profile_id == *"kandji"* ]]; then
                        profile_ids+=("$profile_id")
                    fi
                fi
            done < <(profiles list)
            
            for profile_id in "${profile_ids[@]}"; do
                echo "$(date) | Removing profile: $profile_id"
                profiles remove -identifier "$profile_id"
            done
            ;;
            
        mosyle)
            echo "$(date) | Removing Mosyle MDM profiles"
            
            # Stop Mosyle services
            launchctl unload /Library/LaunchDaemons/com.mosyle.*.plist 2>/dev/null || true
            
            # Remove Mosyle directories
            rm -rf "/Library/Application Support/Mosyle"
            rm -rf "/Library/Mosyle"
            
            # Remove Mosyle profiles
            local profile_ids=()
            while read -r line; do
                if [[ $line =~ profileIdentifier:\ (.+) ]]; then
                    profile_id="${BASH_REMATCH[1]}"
                    if [[ $profile_id == *"mosyle"* ]]; then
                        profile_ids+=("$profile_id")
                    fi
                fi
            done < <(profiles list)
            
            for profile_id in "${profile_ids[@]}"; do
                echo "$(date) | Removing profile: $profile_id"
                profiles remove -identifier "$profile_id"
            done
            ;;
            
        workspace)
    echo "$(date) | Removing VMware Workspace ONE/AirWatch profiles"
            
    # Call the specialized AirWatch removal function
    remove_airwatch_profiles
    ;;
            
        *)
            echo "$(date) | No vendor-specific removal for $CURRENT_MDM, using generic approach"
            ;;
    esac
    
    # Generic approach for all vendors as a fallback
    echo "$(date) | Performing generic MDM profile removal"
    
    # Get list of all profile identifiers
    local all_profile_ids=()
    while read -r line; do
        if [[ $line =~ profileIdentifier:\ (.+) ]]; then
            profile_id="${BASH_REMATCH[1]}"
            all_profile_ids+=("$profile_id")
        fi
    done < <(profiles list)
    
    # Remove each profile
    for profile_id in "${all_profile_ids[@]}"; do
        echo "$(date) | Removing profile: $profile_id"
        profiles remove -identifier "$profile_id"
    done
    
    # Verify removal
    if profiles list | grep -q -E '(MDM|Profile)'; then
        echo "$(date) | WARNING: Some MDM profiles may still be present"
        
        # Try more aggressive removal
        echo "$(date) | Attempting more aggressive profile removal"
        profiles -D
        
        # Final verification
        if profiles list | grep -q -E '(MDM|Profile)'; then
            echo "$(date) | ERROR: Failed to remove all profiles"
            return 1
        fi
    fi
    
    echo "$(date) | All MDM profiles successfully removed"
    return 0
}


# Function to guide through enrollment to Microsoft Intune
guide_enrollment() {
    echo "$(date) | Guiding user through enrollment process to Microsoft Intune"
    
    # Skip user guidance if UI is disabled
    if [ "$USE_UI" = false ]; then
        # For ADE-enrolled devices, still need to renew profiles
        if [ "$ADE_ENROLLED" = true ]; then
            echo "$(date) | Renewing profiles to trigger Setup Assistant"
            profiles renew -type enrollment
        } else {
            echo "$(date) | UI disabled, skipping enrollment guidance"
        }
        return 0
    fi
    
    # Handle enrollment differently based on ADE status
    if [ "$ADE_ENROLLED" = true ]; then
        # For ADE-enrolled devices
        /usr/local/bin/dialog \
            --title "Complete ADE Enrollment" \
            --message "Your device is ADE-enrolled and will now connect to Microsoft Intune.\n\nAfter closing this dialog, the macOS Setup Assistant will appear. Follow the prompts to complete enrollment with your credentials for the new tenant ($TARGET_TENANT).\n\nThis is necessary to maintain management of your device." \
            --icon /Applications/Company\ Portal.app/Contents/Resources/AppIcon.icns \
            --button1text "Continue" \
            --width 600 \
            --height 400 \
            --blurscreen
        
        # Renew profiles to trigger Setup Assistant
        echo "$(date) | Renewing profiles to trigger Setup Assistant"
        profiles renew -type enrollment
    else {
        # For user-initiated enrollment
        /usr/local/bin/dialog \
            --title "Complete Intune Enrollment" \
            --message "Migration is almost complete!\n\nAfter closing this dialog, the Company Portal app will open. Please sign in with your credentials for Microsoft Intune ($TARGET_TENANT) to complete the enrollment process.\n\nThis step is essential for maintaining access to corporate resources." \
            --icon /Applications/Company\ Portal.app/Contents/Resources/AppIcon.icns \
            --button1text "Open Company Portal" \
            --width 600 \
            --height 400 \
            --blurscreen
        
        # Launch Company Portal
        echo "$(date) | Launching Company Portal"
        open -a "/Applications/Company Portal.app"
        
        # Bring Company Portal to the front
        osascript <<EOF
tell application "Company Portal" to activate
EOF
    }
    fi
}

# Function to handle errors
handle_error() {
    local error_message="$1"
    local error_code="$2"
    
    echo "$(date) | ERROR: $error_message"
    
    # Show error dialog if UI is enabled
    if [ "$USE_UI" = true ]; then
        /usr/local/bin/dialog \
            --title "Migration Error" \
            --message "An error occurred during the migration process:\n\n$error_message\n\nError code: $error_code\n\nPlease contact your IT support team for assistance." \
            --icon caution \
            --button1text "Exit" \
            --width 600 \
            --height 400 \
            --blurscreen
    fi
    
    echo "$(date) | macOS MDM Migration failed with error $error_code"
    exit $error_code
}

#---------------------------------------------------------------
# Main script execution
#---------------------------------------------------------------

# Ensure we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Set up logging
setup_logging

# Install SwiftDialog if UI is enabled
install_swiftdialog

# Detect current MDM solution
detect_mdm_vendor

# Override with command line parameter if specified
set_mdm_vendor

# Check prerequisites
check_ade_enrollment
check_filevault

# Execute operation based on flag
case "$OPERATION" in
    detect-mdm)
        echo "$(date) | Executing detect-mdm operation"
        echo "Detected MDM solution: $CURRENT_MDM"
        exit 0
        ;;
        
    remove-only)
        echo "$(date) | Executing remove-only operation"
        remove_mdm_profiles
        ;;
        
    backup-only)
        echo "$(date) | Executing backup-only operation"
        backup_mdm_profiles
        ;;
        
    update-cp-only)
        echo "$(date) | Executing update-cp-only operation"
        install_company_portal force
        ;;
        
    rotate-fv-only)
        echo "$(date) | Executing rotate-fv-only operation"
        # This operation is handled by TenantSwitcherApp.swift when launched with --filevault-only flag
        echo "$(date) | FileVault rotation is now handled by the app with the --filevault-only flag"
        exit 0
        ;;
        
    enroll-only)
        echo "$(date) | Executing enroll-only operation"
        if [ -z "$TARGET_TENANT" ]; then
            handle_error "Target tenant name is required for enrollment" 2
        fi
        guide_enrollment
        ;;
        
    check-status)
        echo "$(date) | Executing check-status operation"
        echo "Current MDM: $CURRENT_MDM"
        # Already performed checks above
        ;;
        
    full-migration)
        echo "$(date) | Executing full migration"
        
        # Require target tenant for full migration
        if [ -z "$TARGET_TENANT" ]; then
            handle_error "Target tenant name is required for migration" 2
        }
        
        show-completion)
        echo "$(date) | Executing show-completion operation"
        show_migration_complete_and_relaunch
        ;;
        
        # Execute all steps in sequence
        backup_mdm_profiles || handle_error "Failed to backup profiles" 3
        install_company_portal force || handle_error "Failed to update Company Portal" 4
        remove_mdm_profiles || handle_error "Failed to remove profiles" 5
        guide_enrollment
        show_migration_complete_and_relaunch  # New function to handle FileVault rotation via app relaunch
        ;;
        
    *)
        handle_error "Unknown operation: $OPERATION" 1
        ;;
esac

echo "$(date) | Operation completed successfully"
exit 0
