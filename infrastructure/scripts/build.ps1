#Requires -Version 7.0
#Requires -Modules @{ModuleName='PSScriptAnalyzer';ModuleVersion='1.20.0'}, @{ModuleName='platyPS';ModuleVersion='0.14.2'}

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Configuration = 'Release',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = '../out',

    [Parameter()]
    [switch]$Parallel,

    [Parameter()]
    [switch]$Incremental,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CertificatePath,

    [Parameter()]
    [hashtable]$BuildParameters = @{}
)

# Import build configuration
$BuildConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../templates/module.build.psd1')

# Global variables
$script:BuildVersion = $BuildConfig.ModuleVersion
$script:BuildConfiguration = $Configuration
$script:SourcePath = '../../src/scripts'

function Initialize-InfrastructureBuild {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CertificatePath,
        [Parameter()]
        [hashtable]$BuildParameters
    )

    try {
        Write-Verbose "Initializing infrastructure build environment..."

        # Validate PowerShell version
        $requiredVersion = [version]$BuildConfig.MinimumPowerShellVersion
        $currentVersion = $PSVersionTable.PSVersion
        if ($currentVersion -lt $requiredVersion) {
            throw "PowerShell version $requiredVersion or higher is required. Current version: $currentVersion"
        }

        # Validate and import required modules
        foreach ($module in $BuildConfig.RequiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                throw "Required module not found: $module"
            }
            Import-Module -Name $module -Force
        }

        # Verify code signing certificate if specified
        if ($CertificatePath) {
            if (-not (Test-Path $CertificatePath)) {
                throw "Code signing certificate not found at: $CertificatePath"
            }
            $script:SigningCertificate = Get-PfxCertificate -FilePath $CertificatePath
        }

        # Create and secure output directories
        $paths = @($OutputPath, "$OutputPath\bin", "$OutputPath\docs", "$OutputPath\test")
        foreach ($path in $paths) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
            # Set appropriate ACLs
            $acl = Get-Acl $path
            $acl.SetAccessRuleProtection($true, $false)
            Set-Acl -Path $path -AclObject $acl
        }

        # Initialize logging
        $logPath = Join-Path $OutputPath 'build.log'
        Start-Transcript -Path $logPath -Force

        Write-Verbose "Infrastructure build environment initialized successfully"
        return $true
    }
    catch {
        Write-Error "Failed to initialize infrastructure build: $_"
        return $false
    }
}

function Invoke-InfrastructureBuild {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Configuration,
        [Parameter()]
        [string]$OutputPath,
        [Parameter()]
        [switch]$Parallel,
        [Parameter()]
        [switch]$Incremental
    )

    try {
        Write-Verbose "Starting infrastructure build process..."

        # Initialize build environment
        if (-not (Initialize-InfrastructureBuild -CertificatePath $CertificatePath -BuildParameters $BuildParameters)) {
            throw "Build initialization failed"
        }

        # Clean output directory if not incremental
        if (-not $Incremental) {
            Write-Verbose "Cleaning output directory..."
            Get-ChildItem -Path $OutputPath -Recurse | Remove-Item -Force -Recurse
        }

        # Process build tasks
        $buildTasks = @(
            @{
                Name = "Validate Source"
                ScriptBlock = {
                    Write-Verbose "Validating source code..."
                    $results = Invoke-ScriptAnalyzer -Path $SourcePath -Settings PSGallery -Recurse
                    if ($results) {
                        throw "PSScriptAnalyzer found $($results.Count) issues"
                    }
                }
            },
            @{
                Name = "Build Module"
                ScriptBlock = {
                    Write-Verbose "Building module..."
                    & "$SourcePath/build.ps1" -Configuration $Configuration -OutputPath $OutputPath
                }
            },
            @{
                Name = "Generate Documentation"
                ScriptBlock = {
                    Write-Verbose "Generating documentation..."
                    $docsPath = Join-Path $OutputPath 'docs'
                    New-MarkdownHelp -Module PSCompassOne -OutputFolder $docsPath -Force
                }
            }
        )

        # Execute build tasks
        if ($Parallel) {
            $jobs = $buildTasks | ForEach-Object {
                Start-Job -ScriptBlock $_.ScriptBlock -Name $_.Name
            }
            $jobs | Wait-Job | Receive-Job
        }
        else {
            foreach ($task in $buildTasks) {
                & $task.ScriptBlock
            }
        }

        # Sign module files if certificate is present
        if ($script:SigningCertificate) {
            Write-Verbose "Signing module files..."
            Get-ChildItem -Path $OutputPath -Include *.ps1,*.psm1,*.psd1 -Recurse |
                ForEach-Object {
                    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $script:SigningCertificate
                }
        }

        # Test build output
        if (-not (Test-InfrastructureBuild -BuildPath $OutputPath)) {
            throw "Build validation failed"
        }

        Write-Verbose "Infrastructure build completed successfully"
        return $true
    }
    catch {
        Write-Error "Infrastructure build failed: $_"
        return $false
    }
    finally {
        Stop-Transcript
    }
}

function Test-InfrastructureBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildPath,
        [Parameter()]
        [hashtable]$ValidationRules = @{}
    )

    try {
        Write-Verbose "Validating build output..."

        # Verify module manifest
        $manifestPath = Join-Path $BuildPath "PSCompassOne.psd1"
        if (-not (Test-ModuleManifest -Path $manifestPath)) {
            throw "Invalid module manifest"
        }

        # Verify required files
        $requiredFiles = @('PSCompassOne.psm1', 'PSCompassOne.psd1', 'about_PSCompassOne.help.txt')
        foreach ($file in $requiredFiles) {
            if (-not (Test-Path (Join-Path $BuildPath $file))) {
                throw "Required file missing: $file"
            }
        }

        # Verify documentation
        $docsPath = Join-Path $BuildPath 'docs'
        if (-not (Test-Path $docsPath)) {
            throw "Documentation folder missing"
        }

        # Verify file signatures if signing was enabled
        if ($script:SigningCertificate) {
            Get-ChildItem -Path $BuildPath -Include *.ps1,*.psm1,*.psd1 -Recurse |
                ForEach-Object {
                    $sig = Get-AuthenticodeSignature -FilePath $_.FullName
                    if ($sig.Status -ne 'Valid') {
                        throw "Invalid signature on file: $($_.Name)"
                    }
                }
        }

        Write-Verbose "Build validation completed successfully"
        return $true
    }
    catch {
        Write-Error "Build validation failed: $_"
        return $false
    }
}

# Export the main build function
Export-ModuleMember -Function Invoke-InfrastructureBuild