#Requires -Version 7.0
#Requires -RunAsAdministrator
using namespace System
using namespace System.IO
using namespace System.Security.Cryptography
using namespace Microsoft.PowerShell.SecretStore

# Version: Microsoft.PowerShell.Core 7.0.0
# Version: Microsoft.PowerShell.SecretStore 1.0.0

#region Script Variables
$script:ModuleName = 'PSCompassOne'
$script:UninstallLogPath = Join-Path $env:TEMP 'PSCompassOne_uninstall.log'
$script:BackupPath = Join-Path $env:TEMP 'PSCompassOne_backup'
$script:RetryAttempts = 3
$script:RetryDelay = 5
#endregion

#region Helper Functions
function Write-UninstallLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Information'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $script:UninstallLogPath -Value $logEntry -ErrorAction SilentlyContinue
    
    # Write to appropriate PowerShell stream
    switch ($Level) {
        'Information' { Write-Information $Message -InformationAction Continue }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        'Debug' { Write-Debug $Message }
    }
}

function Test-UninstallPrerequisites {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        Write-UninstallLog "Checking uninstallation prerequisites..." -Level Debug
        
        # Check for administrative privileges
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-UninstallLog "Administrative privileges required for uninstallation" -Level Error
            return $false
        }
        
        # Check if module is loaded in any sessions
        $loadedModules = Get-Module | Where-Object Name -eq $script:ModuleName
        if ($loadedModules) {
            Write-UninstallLog "Module is currently loaded in PowerShell sessions. Please close all sessions using the module." -Level Error
            return $false
        }
        
        # Verify module installation
        $moduleInfo = Get-Module -Name $script:ModuleName -ListAvailable
        if (-not $moduleInfo) {
            Write-UninstallLog "Module not found in available modules" -Level Error
            return $false
        }
        
        # Check SecretStore accessibility
        if (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable) {
            try {
                $null = Get-SecretStoreConfiguration -ErrorAction Stop
            }
            catch {
                Write-UninstallLog "Unable to access SecretStore: $_" -Level Warning
            }
        }
        
        Write-UninstallLog "All prerequisites checked successfully" -Level Debug
        return $true
    }
    catch {
        Write-UninstallLog "Error checking prerequisites: $_" -Level Error
        return $false
    }
}

function Backup-ModuleState {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        Write-UninstallLog "Creating module state backup..." -Level Information
        
        # Create backup directory with timestamp
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $script:BackupPath $timestamp
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        
        # Get module info
        $moduleInfo = Get-Module -Name $script:ModuleName -ListAvailable
        $modulePath = $moduleInfo.ModuleBase
        
        # Backup module files
        Copy-Item -Path $modulePath -Destination $backupDir -Recurse -Force
        
        # Export SecretStore configuration if available
        if (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable) {
            try {
                $secretStorePath = Join-Path $backupDir 'SecretStore'
                Export-SecretStoreConfiguration -Path $secretStorePath -ErrorAction Stop
            }
            catch {
                Write-UninstallLog "Unable to backup SecretStore configuration: $_" -Level Warning
            }
        }
        
        # Create backup manifest
        $manifest = @{
            ModuleName = $script:ModuleName
            BackupDate = Get-Date
            ModuleVersion = $moduleInfo.Version
            BackupPath = $backupDir
        }
        
        $manifestPath = Join-Path $backupDir 'backup.json'
        $manifest | ConvertTo-Json | Set-Content -Path $manifestPath
        
        Write-UninstallLog "Module state backed up to: $backupDir" -Level Information
        return $backupDir
    }
    catch {
        Write-UninstallLog "Error creating backup: $_" -Level Error
        return $null
    }
}

function Remove-ModuleFiles {
    [CmdletBinding()]
    param()
    
    try {
        Write-UninstallLog "Removing module files..." -Level Information
        
        # Get module path
        $moduleInfo = Get-Module -Name $script:ModuleName -ListAvailable
        $modulePath = $moduleInfo.ModuleBase
        
        # Create list of files to remove
        $filesToRemove = Get-ChildItem -Path $modulePath -Recurse -File
        
        foreach ($file in $filesToRemove) {
            $retryCount = 0
            $removed = $false
            
            while (-not $removed -and $retryCount -lt $script:RetryAttempts) {
                try {
                    # Secure delete implementation
                    if (Test-Path $file.FullName) {
                        # Overwrite file content with random data
                        $buffer = [byte[]]::new($file.Length)
                        $rng = [RNGCryptoServiceProvider]::new()
                        $rng.GetBytes($buffer)
                        [IO.File]::WriteAllBytes($file.FullName, $buffer)
                        
                        # Remove file
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        $removed = $true
                        Write-UninstallLog "Removed file: $($file.FullName)" -Level Debug
                    }
                }
                catch {
                    $retryCount++
                    if ($retryCount -lt $script:RetryAttempts) {
                        Write-UninstallLog "Retry $retryCount/$script:RetryAttempts removing file: $($file.FullName)" -Level Warning
                        Start-Sleep -Seconds $script:RetryDelay
                    }
                    else {
                        Write-UninstallLog "Failed to remove file after $script:RetryAttempts attempts: $($file.FullName)" -Level Error
                    }
                }
            }
        }
        
        # Remove empty directories
        Get-ChildItem -Path $modulePath -Directory -Recurse | 
            Sort-Object -Property FullName -Descending | 
            ForEach-Object {
                if (-not (Get-ChildItem -Path $_.FullName)) {
                    Remove-Item -Path $_.FullName -Force
                    Write-UninstallLog "Removed directory: $($_.FullName)" -Level Debug
                }
            }
        
        # Remove module root directory
        if (Test-Path $modulePath) {
            Remove-Item -Path $modulePath -Force -Recurse
            Write-UninstallLog "Removed module directory: $modulePath" -Level Information
        }
    }
    catch {
        Write-UninstallLog "Error removing module files: $_" -Level Error
        throw
    }
}

function Remove-ModuleConfiguration {
    [CmdletBinding()]
    param()
    
    try {
        Write-UninstallLog "Removing module configuration..." -Level Information
        
        # Remove SecretStore entries
        if (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable) {
            try {
                $secrets = Get-SecretInfo -Name "PSCompassOne_*"
                foreach ($secret in $secrets) {
                    Remove-Secret -Name $secret.Name -Vault "SecretStore"
                    Write-UninstallLog "Removed secret: $($secret.Name)" -Level Debug
                }
            }
            catch {
                Write-UninstallLog "Error removing SecretStore entries: $_" -Level Warning
            }
        }
        
        # Remove environment variables
        $envVars = Get-ChildItem env: | Where-Object Name -like "COMPASSONE_*"
        foreach ($var in $envVars) {
            Remove-Item env:\$($var.Name) -Force
            Write-UninstallLog "Removed environment variable: $($var.Name)" -Level Debug
        }
        
        # Remove cached data
        $cachePaths = @(
            (Join-Path $env:LOCALAPPDATA "PSCompassOne"),
            (Join-Path $env:TEMP "PSCompassOne_*")
        )
        
        foreach ($path in $cachePaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Force -Recurse
                Write-UninstallLog "Removed cache directory: $path" -Level Debug
            }
        }
        
        # Remove registry entries (Windows only)
        if ($IsWindows) {
            $registryPaths = @(
                "HKCU:\Software\PSCompassOne",
                "HKLM:\Software\PSCompassOne"
            )
            
            foreach ($path in $registryPaths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Force -Recurse
                    Write-UninstallLog "Removed registry key: $path" -Level Debug
                }
            }
        }
        
        Write-UninstallLog "Module configuration removed successfully" -Level Information
    }
    catch {
        Write-UninstallLog "Error removing module configuration: $_" -Level Error
        throw
    }
}

function Unregister-Module {
    [CmdletBinding()]
    param()
    
    try {
        Write-UninstallLog "Unregistering module from PowerShell..." -Level Information
        
        # Remove module from current session if loaded
        if (Get-Module -Name $script:ModuleName) {
            Remove-Module -Name $script:ModuleName -Force
            Write-UninstallLog "Removed module from current session" -Level Debug
        }
        
        # Clear PowerShell module cache
        $moduleCachePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "Microsoft\Windows\PowerShell\Cache"
        if (Test-Path $moduleCachePath) {
            Get-ChildItem -Path $moduleCachePath -Filter "*$script:ModuleName*" -Recurse |
                Remove-Item -Force -Recurse
            Write-UninstallLog "Cleared module cache" -Level Debug
        }
        
        # Update PSModulePath
        $paths = $env:PSModulePath -split [IO.Path]::PathSeparator |
            Where-Object { -not $_.Contains($script:ModuleName) }
        $env:PSModulePath = $paths -join [IO.Path]::PathSeparator
        
        Write-UninstallLog "Module unregistered successfully" -Level Information
    }
    catch {
        Write-UninstallLog "Error unregistering module: $_" -Level Error
        throw
    }
}
#endregion

#region Main Execution
try {
    # Start logging
    Write-UninstallLog "Starting PSCompassOne module uninstallation..." -Level Information
    
    # Check prerequisites
    if (-not (Test-UninstallPrerequisites)) {
        throw "Prerequisites check failed. Please review the log for details."
    }
    
    # Create backup
    $backupPath = Backup-ModuleState
    if (-not $backupPath) {
        $response = Read-Host "Backup creation failed. Continue with uninstallation? (Y/N)"
        if ($response -ne 'Y') {
            throw "Uninstallation cancelled by user after backup failure"
        }
    }
    
    # Remove module files
    Remove-ModuleFiles
    
    # Remove configuration
    Remove-ModuleConfiguration
    
    # Unregister module
    Unregister-Module
    
    Write-UninstallLog "PSCompassOne module uninstallation completed successfully" -Level Information
    Write-UninstallLog "Backup location: $backupPath" -Level Information
    
    exit 0
}
catch {
    Write-UninstallLog "Uninstallation failed: $_" -Level Error
    Write-UninstallLog "Please review the log file at: $script:UninstallLogPath" -Level Error
    exit 1
}
#endregion