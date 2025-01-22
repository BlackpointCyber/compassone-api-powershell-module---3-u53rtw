#Requires -Version 5.1
using namespace System
using namespace System.IO
using namespace System.Security.Cryptography

# Version: Microsoft.PowerShell.Core 7.0.0
# Version: Microsoft.PowerShell.SecretStore 1.0.0

#region Script Variables
$script:ModuleName = 'PSCompassOne'
$script:MinimumPowerShellVersion = [Version]'5.1'
$script:RecommendedPowerShellVersion = [Version]'7.0'
$script:RetryAttempts = 3
$script:RetryDelaySeconds = 5
$script:SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#endregion

#region Helper Functions
function Test-Prerequisites {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$InstallPath,
        
        [Parameter()]
        [switch]$Force
    )

    try {
        Write-Verbose "Validating installation prerequisites..."

        # Check PowerShell version
        $currentVersion = $PSVersionTable.PSVersion
        if ($currentVersion -lt $script:MinimumPowerShellVersion) {
            throw "PowerShell version $script:MinimumPowerShellVersion or later is required. Current version: $currentVersion"
        }

        # Check execution policy
        $policy = Get-ExecutionPolicy
        if ($policy -in @('Restricted', 'Undefined')) {
            throw "PowerShell execution policy must allow script execution. Current policy: $policy"
        }

        # Check administrative privileges if needed
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin -and -not $Force) {
            $programFiles = [Environment]::GetFolderPath('ProgramFiles')
            if ($InstallPath.StartsWith($programFiles, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Administrative privileges required for installation in Program Files"
            }
        }

        # Verify PowerShell Gallery access
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
        if ($gallery.InstallationPolicy -ne 'Trusted' -and -not $Force) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        # Check disk space (minimum 100MB free)
        $drive = Split-Path -Path $InstallPath -Qualifier
        $freeSpace = (Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop).Free
        if ($freeSpace -lt 100MB) {
            throw "Insufficient disk space. Required: 100MB, Available: $([math]::Round($freeSpace / 1MB, 2))MB"
        }

        Write-Verbose "All prerequisites validated successfully"
        return $true
    }
    catch {
        Write-Error -Message "Prerequisite check failed: $_" -Category InvalidOperation
        return $false
    }
}

function Install-Dependencies {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [int]$RetryCount = $script:RetryAttempts,
        
        [Parameter()]
        [int]$RetryDelay = $script:RetryDelaySeconds
    )

    try {
        Write-Verbose "Installing required dependencies..."

        # Set TLS 1.2 for PowerShell Gallery access
        [Net.ServicePointManager]::SecurityProtocol = $script:SecurityProtocol

        # Install SecretStore module with retry logic
        $attempt = 0
        $installed = $false
        do {
            $attempt++
            try {
                $params = @{
                    Name = 'Microsoft.PowerShell.SecretStore'
                    MinimumVersion = '1.0.0'
                    Force = $Force
                    ErrorAction = 'Stop'
                }
                Install-Module @params
                $installed = $true
                Write-Verbose "SecretStore module installed successfully"
            }
            catch {
                if ($attempt -ge $RetryCount) {
                    throw "Failed to install SecretStore module after $RetryCount attempts: $_"
                }
                Write-Warning "Attempt $attempt of $RetryCount failed. Retrying in $RetryDelay seconds..."
                Start-Sleep -Seconds $RetryDelay
            }
        } while (-not $installed -and $attempt -lt $RetryCount)

        # Initialize SecretStore with secure defaults
        if (-not (Get-SecretVault -Name $script:ModuleName -ErrorAction SilentlyContinue)) {
            Register-SecretVault -Name $script:ModuleName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
            Set-SecretStoreConfiguration -Scope CurrentUser -Authentication None -Interaction None
            Write-Verbose "SecretStore initialized for $script:ModuleName"
        }
    }
    catch {
        throw "Dependency installation failed: $_"
    }
}

function Install-ModuleFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$CreateBackup
    )

    try {
        Write-Verbose "Installing module files to: $DestinationPath"

        # Create backup if requested
        if ($CreateBackup -and (Test-Path $DestinationPath)) {
            $backupPath = "$DestinationPath.backup_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -Path $DestinationPath -Destination $backupPath -Recurse -Force
            Write-Verbose "Created backup at: $backupPath"
        }

        # Ensure destination directory exists
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }

        # Copy module files
        $sourceFiles = @(
            'PSCompassOne.psd1'
            'PSCompassOne.psm1'
            'Config/PSCompassOne.format.ps1xml'
            'Config/PSCompassOne.types.ps1xml'
            'Config/PSCompassOne.config.psd1'
        )

        foreach ($file in $sourceFiles) {
            $source = Join-Path $PSScriptRoot $file
            $destination = Join-Path $DestinationPath $file
            
            # Ensure parent directory exists
            $destinationDir = Split-Path -Path $destination -Parent
            if (-not (Test-Path $destinationDir)) {
                New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
            }

            # Copy file with hash verification
            Copy-Item -Path $source -Destination $destination -Force
            
            # Verify file copy
            $sourceHash = Get-FileHash -Path $source -Algorithm SHA256
            $destHash = Get-FileHash -Path $destination -Algorithm SHA256
            if ($sourceHash.Hash -ne $destHash.Hash) {
                throw "File integrity verification failed for: $file"
            }
            
            Write-Verbose "Copied and verified: $file"
        }

        # Set appropriate permissions
        $acl = Get-Acl -Path $DestinationPath
        $acl.SetAccessRuleProtection($true, $true)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            'BUILTIN\Users',
            'ReadAndExecute',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $DestinationPath -AclObject $acl

        Write-Verbose "Module files installed successfully"
    }
    catch {
        # Attempt rollback if backup exists
        if ($CreateBackup -and (Test-Path $backupPath)) {
            Write-Warning "Installation failed, attempting rollback..."
            Remove-Item -Path $DestinationPath -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path $backupPath -Destination $DestinationPath -Recurse -Force
            Remove-Item -Path $backupPath -Recurse -Force
        }
        throw "Module file installation failed: $_"
    }
}

function Register-Module {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ModulePath,
        
        [Parameter()]
        [switch]$NoCache
    )

    try {
        Write-Verbose "Registering module..."

        # Clear PowerShell module cache if requested
        if ($NoCache) {
            $env:PSModulePath -split [IO.Path]::PathSeparator | ForEach-Object {
                $cachePath = Join-Path $_ "ModuleAnalysisCache"
                if (Test-Path $cachePath) {
                    Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Import module to verify installation
        Import-Module -Name $ModulePath -Force -ErrorAction Stop

        # Verify module commands are available
        $commands = Get-Command -Module $script:ModuleName -ErrorAction Stop
        if ($commands.Count -eq 0) {
            throw "No commands found in module"
        }

        # Test basic functionality
        $null = Get-Module -Name $script:ModuleName -ErrorAction Stop
        Write-Verbose "Module registered successfully with $($commands.Count) commands available"

        # Display success message
        Write-Host @"
PSCompassOne module installed successfully!
Module Path: $ModulePath
PowerShell Version: $($PSVersionTable.PSVersion)
Commands Available: $($commands.Count)

To get started, run:
    Get-Command -Module PSCompassOne
    Get-Help Connect-CompassOne
"@ -ForegroundColor Green
    }
    catch {
        throw "Module registration failed: $_"
    }
}
#endregion

#region Main Installation Logic
try {
    # Display banner
    Write-Host @"
PSCompassOne Module Installer
Version: 1.0.0
"@ -ForegroundColor Cyan

    # Determine installation path
    $defaultPath = if ($IsWindows) {
        Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell\Modules\$script:ModuleName"
    }
    else {
        Join-Path $HOME ".local/share/powershell/Modules/$script:ModuleName"
    }

    # Validate prerequisites
    if (-not (Test-Prerequisites -InstallPath $defaultPath)) {
        throw "Prerequisites not met. Please review the error messages above."
    }

    # Install dependencies
    Write-Progress -Activity "Installing PSCompassOne" -Status "Installing dependencies..." -PercentComplete 25
    Install-Dependencies -Force

    # Install module files
    Write-Progress -Activity "Installing PSCompassOne" -Status "Copying module files..." -PercentComplete 50
    Install-ModuleFiles -DestinationPath $defaultPath -Force -CreateBackup

    # Register module
    Write-Progress -Activity "Installing PSCompassOne" -Status "Registering module..." -PercentComplete 75
    Register-Module -ModulePath $defaultPath -NoCache

    Write-Progress -Activity "Installing PSCompassOne" -Status "Installation complete" -PercentComplete 100
}
catch {
    Write-Error -Message "Installation failed: $_" -Category InvalidOperation
    exit 1
}
finally {
    Write-Progress -Activity "Installing PSCompassOne" -Completed
}
#endregion