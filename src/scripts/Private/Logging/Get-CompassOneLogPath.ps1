using namespace System.IO
using namespace System.Security.AccessControl

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Returns the secure log file path for PSCompassOne module with proper permissions.

.DESCRIPTION
    Private function that determines and returns the appropriate log file path for the PSCompassOne module.
    Implements secure audit logging with proper directory structure, access permissions, and cross-platform support.
    Ensures log directory has appropriate security controls and is tamper-resistant.

.OUTPUTS
    System.String
    Returns the full path to the secure log file with proper permissions.

.NOTES
    File Name      : Get-CompassOneLogPath.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
    Required Modules: Microsoft.PowerShell.Security v7.0.0
                     System.IO v4.0.0
#>

[CmdletBinding()]
param()

begin {
    # Cache validated path for performance
    $script:CachedLogPath = $null
    
    # Constants for path configuration
    $DEFAULT_LOG_FILENAME = 'PSCompassOne.log'
    $MODULE_FOLDER_NAME = 'PSCompassOne'
    $LOG_FOLDER_NAME = 'Logs'
}

process {
    try {
        # Return cached path if available and valid
        if ($script:CachedLogPath -and (Test-Path -Path $script:CachedLogPath -PathType Leaf)) {
            return $script:CachedLogPath
        }

        # Check for custom log path in environment variable
        $logPath = $env:COMPASSONE_LOG_PATH

        if (-not $logPath) {
            # Determine default log path based on platform
            if ($IsWindows -or (-not $PSVersionTable.Platform)) {
                # Windows path using LocalAppData
                $basePath = [Environment]::GetFolderPath('LocalApplicationData')
                $logPath = Join-Path -Path $basePath -ChildPath $MODULE_FOLDER_NAME
            }
            else {
                # Linux/macOS path
                $basePath = [Environment]::GetFolderPath('UserProfile')
                $logPath = Join-Path -Path $basePath -ChildPath ".${MODULE_FOLDER_NAME}"
            }
            
            # Append Logs subdirectory
            $logPath = Join-Path -Path $logPath -ChildPath $LOG_FOLDER_NAME
        }

        # Create directory if it doesn't exist
        if (-not (Test-Path -Path $logPath -PathType Container)) {
            $null = New-Item -Path $logPath -ItemType Directory -Force
            
            # Set secure directory permissions
            if ($IsWindows -or (-not $PSVersionTable.Platform)) {
                # Windows NTFS permissions
                $acl = Get-Acl -Path $logPath
                $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance
                
                # Add current user with Modify rights
                $userIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $userIdentity.Name,
                    'Modify',
                    'ContainerInherit,ObjectInherit',
                    'None',
                    'Allow'
                )
                $acl.AddAccessRule($accessRule)
                
                # Add SYSTEM with Full Control
                $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    'NT AUTHORITY\SYSTEM',
                    'FullControl',
                    'ContainerInherit,ObjectInherit',
                    'None',
                    'Allow'
                )
                $acl.AddAccessRule($systemRule)
                
                Set-Acl -Path $logPath -AclObject $acl
            }
            else {
                # Linux/macOS permissions (700)
                chmod 700 $logPath
            }
        }

        # Construct full log file path
        $fullLogPath = Join-Path -Path $logPath -ChildPath $DEFAULT_LOG_FILENAME

        # Create log file if it doesn't exist
        if (-not (Test-Path -Path $fullLogPath -PathType Leaf)) {
            $null = New-Item -Path $fullLogPath -ItemType File -Force
            
            # Set secure file permissions
            if ($IsWindows -or (-not $PSVersionTable.Platform)) {
                $fileAcl = Get-Acl -Path $fullLogPath
                $fileAcl.SetAccessRuleProtection($true, $false)
                
                # Add current user with Modify rights
                $userIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                $fileRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $userIdentity.Name,
                    'Modify',
                    'None',
                    'None',
                    'Allow'
                )
                $fileAcl.AddAccessRule($fileRule)
                
                # Add SYSTEM with Full Control
                $systemFileRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    'NT AUTHORITY\SYSTEM',
                    'FullControl',
                    'None',
                    'None',
                    'Allow'
                )
                $fileAcl.AddAccessRule($systemFileRule)
                
                Set-Acl -Path $fullLogPath -AclObject $fileAcl
            }
            else {
                # Linux/macOS file permissions (600)
                chmod 600 $fullLogPath
            }
        }

        # Verify write access
        $testFile = $true
        try {
            [IO.File]::OpenWrite($fullLogPath).Close()
        }
        catch {
            $testFile = $false
            throw "Unable to write to log file: $fullLogPath"
        }

        if ($testFile) {
            # Cache the validated path
            $script:CachedLogPath = $fullLogPath
            return $fullLogPath
        }
    }
    catch {
        # If primary log path fails, attempt to use temporary directory as fallback
        $tempPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $MODULE_FOLDER_NAME
        $tempPath = Join-Path -Path $tempPath -ChildPath $LOG_FOLDER_NAME
        $tempLogPath = Join-Path -Path $tempPath -ChildPath $DEFAULT_LOG_FILENAME

        if (-not (Test-Path -Path $tempPath)) {
            $null = New-Item -Path $tempPath -ItemType Directory -Force
        }

        Write-Warning "Failed to use primary log path. Using temporary location: $tempLogPath"
        return $tempLogPath
    }
}