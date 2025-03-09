# JUMP-IN: Just Upgrade & Migrate to Intune
© Somesh Pathak

## Overview

JUMP-IN is an all-in-one macOS application that simplifies the migration between MDM solutions, specifically designed to help organizations move from any MDM vendor to Microsoft Intune or between Intune tenants.

**Key benefits:**
- Seamlessly migrate from any MDM to Microsoft Intune
- No data loss or device wipe required
- Comprehensive security with FileVault key rotation
- Complete migration in 15-20 minutes per device

## Features

### MDM Vendor Support

JUMP-IN detects and migrates from the following MDM solutions:

| Vendor | Supported |
|--------|-----------|
| Microsoft Intune | ✅ |
| Jamf Pro | ✅ |
| VMware Workspace ONE | ✅ |
| Kandji | ✅ |
| Mosyle | ✅ |
| Addigy | ✅ |

### Required Setup Steps

#### 1. Apple Business Manager (ABM) Configuration
- Assign the Mac device to Apple Business Manager
- Verify the device appears in ABM inventory
- Ensure ABM has the correct MDM server tokens

#### 2. Microsoft Intune Configuration
- Sync ABM token in Intune Admin Center
- Verify the sync completed successfully
- Assign required device profiles
  - Enrollment profile
  - Configuration profiles
  - Compliance policies

#### 3. Synchronization
- Wait for ABM-Intune sync to complete
- Verify device appears in Intune inventory
- Confirm profile assignments are active

### Migration Process

JUMP-IN handles the entire migration workflow:

1. **System Compatibility Check**: Verifies macOS version, FileVault status, and other prerequisites
2. **MDM Detection**: Automatically identifies current MDM solution
3. **Backup**: Creates a comprehensive backup of current MDM configurations
4. **Profile Removal**: Safely removes existing MDM profiles
5. **Company Portal**: Installs or updates Microsoft Company Portal
6. **Tenant Enrollment**: Guides enrollment into the new Intune tenant
7. **FileVault Security**: Rotates FileVault recovery key to maintain security compliance

## Installation

### System Requirements

- macOS 14.0 (Sonoma) or higher
- 4GB RAM minimum
- 10GB free disk space
- Administrative privileges
- FileVault enabled (recommended)
- Internet connection

### Download Options

1. **Direct Download**: Get the latest release from our [Releases page](https://github.com/pathaksomesh06/JUMP-IN/releases/tag/v1.0)

## Usage Guide

### Getting Started

1. Download and install JUMP-IN
2. Launch the application (requires administrator privileges)
3. Click "Get Started"
4. Follow the on-screen instructions through the migration process


## Security & Privacy

JUMP-IN was designed with security as a priority:

- All code is signed and notarized by Apple
- Privileged operations use Apple's SMJobBless framework
- No data is collected or transmitted outside your organization
- FileVault key rotation maintains security compliance
- All backups are stored locally in secure locations

## FAQ

### How long does migration take?
The typical migration process takes 15-20 minutes per device, but may vary depending on internet speed and system performance.

### Does JUMP-IN require internet access?
Yes, an internet connection is required to download the Company Portal app and complete enrollment in Microsoft Intune.

### Will users lose their data during migration?
No, JUMP-IN performs a non-destructive migration without wiping devices or removing user data.

### Does JUMP-IN support mass deployment?
Yes, JUMP-IN can be deployed via command line with automation tools like Jamf Pro, Microsoft Intune, or shell scripts.

### What permissions does JUMP-IN require?
JUMP-IN requires administrator privileges to remove MDM profiles and install the helper tool.

## Support

If you encounter issues or have questions about JUMP-IN:

- Open an issue
## Contributing

Contributions to JUMP-IN are always Welecome!
