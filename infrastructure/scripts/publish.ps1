#Requires -Version 7.0
#Requires -Modules @{ ModuleName="PowerShellGet"; ModuleVersion="2.2.5" }

using namespace System
using namespace System.Management.Automation
using namespace System.Collections.Generic

<#
.SYNOPSIS
    Publishes the PSCompassOne module to PowerShell Gallery and other configured targets.
.DESCRIPTION
    Handles secure publication and distribution of the PSCompassOne module with comprehensive
    validation, multi-target support, and rollback capabilities.
#>

# Import build configuration
$buildConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../templates/module.build.psd1')
$manifestPath = Join-Path $PSScriptRoot '../../src/scripts/PSCompassOne.psd1'

function Initialize-ModulePublish {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Configuration,

        [Parameter(Mandatory)]
        [hashtable]$Credentials
    )

    try {
        Write-Verbose "Initializing module publish environment for configuration: $Configuration"

        # Validate PowerShellGet version
        $psGetModule = Get-Module -Name PowerShellGet -ListAvailable | 
            Sort-Object Version -Descending | 
            Select-Object -First 1
        
        if ($psGetModule.Version -lt [Version]'2.2.5') {
            throw "PowerShellGet 2.2.5 or higher is required. Current version: $($psGetModule.Version)"
        }

        # Validate credentials
        foreach ($target in $Credentials.Keys) {
            if ([string]::IsNullOrWhiteSpace($Credentials[$target])) {
                throw "Missing API key for target: $target"
            }
        }

        # Load and validate manifest
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        if (-not $manifest.ModuleVersion) {
            throw "Invalid module manifest: Version not found"
        }

        # Initialize publishing context
        $context = @{
            Configuration = $Configuration
            Version = $manifest.ModuleVersion
            Manifest = $manifest
            BuildPath = $buildConfig.BuildOutputPath
            Credentials = $Credentials
            Timestamp = [DateTime]::UtcNow
        }

        Write-Verbose "Module publish environment initialized successfully"
        return $context
    }
    catch {
        Write-Error "Failed to initialize module publish environment: $_"
        throw
    }
}

function Test-ModulePublishRequirements {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseType,

        [Parameter(Mandatory)]
        [hashtable]$ValidationRules
    )

    try {
        Write-Verbose "Validating module publish requirements for release type: $ReleaseType"

        # Verify build path exists
        if (-not (Test-Path -Path $BuildPath -PathType Container)) {
            throw "Build path not found: $BuildPath"
        }

        # Verify module manifest
        $manifestPath = Join-Path $BuildPath 'PSCompassOne.psd1'
        if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
            throw "Module manifest not found in build path"
        }

        # Test module manifest
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        if (-not $manifest) {
            throw "Invalid module manifest"
        }

        # Validate version format based on release type
        $version = $manifest.Version
        switch ($ReleaseType) {
            'Production' {
                if ($version -match '-') {
                    throw "Production release cannot have prerelease version: $version"
                }
            }
            'Preview' {
                if (-not ($version -match '-preview')) {
                    throw "Preview release must have -preview suffix: $version"
                }
            }
            'Hotfix' {
                if (-not ($version -match '-hotfix')) {
                    throw "Hotfix release must have -hotfix suffix: $version"
                }
            }
        }

        # Verify required files
        $requiredFiles = @(
            'PSCompassOne.psm1',
            'Config/PSCompassOne.types.ps1xml',
            'Config/PSCompassOne.format.ps1xml'
        )

        foreach ($file in $requiredFiles) {
            $filePath = Join-Path $BuildPath $file
            if (-not (Test-Path -Path $filePath -PathType Leaf)) {
                throw "Required file not found: $file"
            }
        }

        # Validate module loads in isolation
        $testResult = Test-ModuleInIsolation -BuildPath $BuildPath
        if (-not $testResult.Success) {
            throw "Module failed to load in isolation: $($testResult.Error)"
        }

        Write-Verbose "Module publish requirements validated successfully"
        return @{
            Success = $true
            Manifest = $manifest
            ValidationResults = $testResult
        }
    }
    catch {
        Write-Error "Module publish requirements validation failed: $_"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-ModuleInIsolation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BuildPath
    )

    try {
        $result = Start-Job -ScriptBlock {
            param($Path)
            
            try {
                Import-Module $Path -Force -ErrorAction Stop
                @{
                    Success = $true
                    ModuleInfo = Get-Module PSCompassOne
                }
            }
            catch {
                @{
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        } -ArgumentList $BuildPath | Wait-Job | Receive-Job

        return $result
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Publish-PSCompassOneModule {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Credentials,

        [Parameter(Mandatory)]
        [ValidateSet('Production', 'Preview', 'Hotfix')]
        [string]$ReleaseType,

        [Parameter()]
        [string[]]$Targets = @('PSGallery')
    )

    try {
        # Initialize publishing environment
        $context = Initialize-ModulePublish -Configuration $ReleaseType -Credentials $Credentials
        if (-not $context) {
            throw "Failed to initialize publishing environment"
        }

        # Validate requirements
        $validationResult = Test-ModulePublishRequirements -BuildPath $Path -ReleaseType $ReleaseType -ValidationRules $buildConfig
        if (-not $validationResult.Success) {
            throw "Failed to validate module requirements: $($validationResult.Error)"
        }

        # Create backup for rollback
        $backupPath = Join-Path $Path "../backup/$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $Path -Destination $backupPath -Recurse -Force

        # Publish to each target
        $publishResults = @{}
        foreach ($target in $Targets) {
            if ($PSCmdlet.ShouldProcess($target, "Publish module")) {
                try {
                    $publishParams = @{
                        Path = $Path
                        NuGetApiKey = $Credentials[$target]
                        Repository = $target
                        Force = $true
                        ErrorAction = 'Stop'
                    }

                    Write-Verbose "Publishing to $target..."
                    Publish-Module @publishParams

                    # Verify publication
                    $verifyParams = @{
                        Name = 'PSCompassOne'
                        RequiredVersion = $context.Version
                        Repository = $target
                        ErrorAction = 'Stop'
                    }
                    
                    Start-Sleep -Seconds 30  # Allow for repository indexing
                    $published = Find-Module @verifyParams
                    
                    if ($published) {
                        $publishResults[$target] = @{
                            Success = $true
                            Version = $published.Version
                            PublishedOn = [DateTime]::UtcNow
                        }
                        Write-Verbose "Successfully published to $target"
                    }
                    else {
                        throw "Module verification failed"
                    }
                }
                catch {
                    $publishResults[$target] = @{
                        Success = $false
                        Error = $_.Exception.Message
                    }
                    Write-Error "Failed to publish to $target: $_"
                    
                    # Initiate rollback for failed target
                    Write-Warning "Initiating rollback for $target..."
                    try {
                        if ($published) {
                            Unregister-PSRepository -Name $target -ErrorAction Stop
                            Register-PSRepository -Name $target -ErrorAction Stop
                        }
                    }
                    catch {
                        Write-Error "Rollback failed for $target: $_"
                    }
                }
            }
        }

        # Generate publication report
        $report = @{
            ReleaseType = $ReleaseType
            Version = $context.Version
            PublishDate = $context.Timestamp
            Results = $publishResults
            ValidationResults = $validationResult
        }

        # Cleanup sensitive data
        $Credentials.Clear()
        Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue

        return [PSCustomObject]$report
    }
    catch {
        Write-Error "Module publication failed: $_"
        
        # Attempt rollback if backup exists
        if (Test-Path $backupPath) {
            Write-Warning "Attempting to restore from backup..."
            try {
                Remove-Item -Path $Path -Recurse -Force
                Copy-Item -Path $backupPath -Destination $Path -Recurse -Force
                Write-Warning "Rollback completed successfully"
            }
            catch {
                Write-Error "Rollback failed: $_"
            }
        }
        
        throw
    }
}

# Export the main publication function
Export-ModuleMember -Function Publish-PSCompassOneModule