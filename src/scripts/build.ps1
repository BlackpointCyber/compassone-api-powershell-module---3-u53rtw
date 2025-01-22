#Requires -Version 7.0
using namespace System
using namespace System.IO
using namespace System.Security.Cryptography.X509Certificates

# Version: Microsoft.PowerShell.Core 7.0.0
# Version: PSScriptAnalyzer 1.20.0
# Version: platyPS 0.14.2
# Version: Pester 5.3.1

#region Script Variables
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Debug', 'Release')]
    [string]$BuildConfiguration = 'Release',

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$BuildVersion = '1.0.0',

    [Parameter()]
    [string]$OutputPath = './out',

    [Parameter()]
    [string]$BuildLog = './logs/build.log',

    [Parameter()]
    [string]$TestResultsPath = './out/tests',

    [Parameter()]
    [string]$DocumentationPath = './out/docs'
)

#region Build Functions
function Initialize-BuildEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Configuration,
        
        [Parameter(Mandatory)]
        [string]$BuildPath
    )

    try {
        Write-Verbose "Initializing build environment with configuration: $Configuration"
        
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion -lt [Version]'7.0') {
            throw "PowerShell 7.0 or higher is required for the build process"
        }

        # Create build directory structure
        $paths = @(
            $BuildPath,
            $TestResultsPath,
            $DocumentationPath,
            (Split-Path -Parent $BuildLog)
        )

        foreach ($path in $paths) {
            if (-not (Test-Path -Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $path"
            }
        }

        # Import required modules
        $requiredModules = @(
            @{Name='PSScriptAnalyzer'; Version='1.20.0'},
            @{Name='platyPS'; Version='0.14.2'},
            @{Name='Pester'; Version='5.3.1'}
        )

        foreach ($module in $requiredModules) {
            if (-not (Get-Module -Name $module.Name -ListAvailable | 
                    Where-Object Version -ge $module.Version)) {
                Install-Module -Name $module.Name -MinimumVersion $module.Version -Force -Scope CurrentUser
            }
            Import-Module -Name $module.Name -MinimumVersion $module.Version -Force
            Write-Verbose "Imported module: $($module.Name) v$($module.Version)"
        }

        # Load build configuration
        $buildConfig = Import-PowerShellDataFile -Path "$PSScriptRoot/../../infrastructure/templates/module.build.psd1"
        $buildConfig.BuildConfiguration = $Configuration
        $buildConfig.ModuleVersion = $BuildVersion

        Write-Verbose "Build environment initialized successfully"
        return $buildConfig
    }
    catch {
        Write-Error "Failed to initialize build environment: $_"
        throw
    }
}

function Invoke-ModuleBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Configuration,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter(Mandatory)]
        [string]$Version,
        
        [Parameter()]
        [switch]$Sign
    )

    try {
        Write-Verbose "Starting module build process"
        $buildStart = Get-Date
        
        # Initialize build environment
        $buildConfig = Initialize-BuildEnvironment -Configuration $Configuration -BuildPath $OutputPath
        
        # Clean output directory
        if (Test-Path -Path $OutputPath) {
            Remove-Item -Path $OutputPath\* -Recurse -Force
            Write-Verbose "Cleaned output directory: $OutputPath"
        }

        # Copy source files
        $sourcePath = Join-Path $PSScriptRoot '..'
        Copy-Item -Path "$sourcePath\*" -Destination $OutputPath -Recurse -Exclude @('*.tests.ps1')
        Write-Verbose "Copied source files to: $OutputPath"

        # Update module manifest
        $manifestPath = Join-Path $OutputPath 'PSCompassOne.psd1'
        $manifestContent = Get-Content -Path $manifestPath -Raw
        $newManifest = $manifestContent -replace "ModuleVersion = '.*'", "ModuleVersion = '$Version'"
        Set-Content -Path $manifestPath -Value $newManifest
        Write-Verbose "Updated module version to: $Version"

        # Run PSScriptAnalyzer
        $analysisResults = Invoke-ScriptAnalyzer -Path $OutputPath -Recurse -Settings PSGallery
        if ($analysisResults) {
            $analysisResults | Format-Table -AutoSize
            throw "PSScriptAnalyzer found $($analysisResults.Count) issues"
        }
        Write-Verbose "PSScriptAnalyzer validation passed"

        # Run Pester tests
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = "$sourcePath\tests"
        $pesterConfig.Run.Exit = $true
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputPath = Join-Path $TestResultsPath "PesterResults.xml"
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = "$OutputPath\*.ps1"
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $TestResultsPath "CodeCoverage.xml"

        $testResults = Invoke-Pester -Configuration $pesterConfig
        if ($testResults.FailedCount -gt 0) {
            throw "Pester tests failed: $($testResults.FailedCount) failures"
        }
        Write-Verbose "Pester tests passed successfully"

        # Generate documentation
        $null = New-MarkdownHelp -Module PSCompassOne -OutputFolder $DocumentationPath -Force
        Write-Verbose "Generated module documentation"

        # Sign module files if requested
        if ($Sign) {
            $filesToSign = Get-ChildItem -Path $OutputPath -Recurse -Include @('*.ps1', '*.psm1', '*.psd1')
            foreach ($file in $filesToSign) {
                $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
                if ($cert) {
                    Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert
                    Write-Verbose "Signed file: $($file.Name)"
                }
                else {
                    throw "No code signing certificate found"
                }
            }
        }

        # Create module package
        $packagePath = New-ModulePackage -SourcePath $OutputPath -OutputPath $buildConfig.BuildOutputPath -Version $Version
        Write-Verbose "Created module package: $packagePath"

        # Generate build report
        $buildEnd = Get-Date
        $buildDuration = $buildEnd - $buildStart
        $buildReport = @{
            Version = $Version
            Configuration = $Configuration
            StartTime = $buildStart
            EndTime = $buildEnd
            Duration = $buildDuration
            TestsPassed = $testResults.PassedCount
            CodeCoverage = $testResults.CodeCoverage.CoveragePercent
        }

        return [PSCustomObject]$buildReport
    }
    catch {
        Write-Error "Build process failed: $_"
        throw
    }
}

function New-ModulePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter(Mandatory)]
        [string]$Version
    )

    try {
        Write-Verbose "Creating module package"
        
        # Prepare package directory
        $packageName = "PSCompassOne_$Version"
        $packagePath = Join-Path $OutputPath $packageName
        
        if (Test-Path $packagePath) {
            Remove-Item $packagePath -Recurse -Force
        }
        
        New-Item -Path $packagePath -ItemType Directory | Out-Null

        # Copy module files
        Copy-Item -Path "$SourcePath\*" -Destination $packagePath -Recurse
        Write-Verbose "Copied module files to package directory"

        # Create package manifest
        $manifestPath = Join-Path $packagePath "PSCompassOne.psd1"
        $manifest = Import-PowerShellDataFile $manifestPath
        $manifest.ModuleVersion = $Version
        
        New-ModuleManifest -Path $manifestPath @manifest
        Write-Verbose "Created package manifest"

        # Compress package
        $archivePath = "$packagePath.zip"
        Compress-Archive -Path $packagePath -DestinationPath $archivePath -Force
        Write-Verbose "Created package archive: $archivePath"

        return $archivePath
    }
    catch {
        Write-Error "Failed to create module package: $_"
        throw
    }
}

function Publish-ModulePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,
        
        [Parameter(Mandatory)]
        [string]$Repository,
        
        [Parameter(Mandatory)]
        [securestring]$ApiKey
    )

    try {
        Write-Verbose "Publishing module package to repository: $Repository"

        # Validate package
        if (-not (Test-Path $PackagePath)) {
            throw "Package not found: $PackagePath"
        }

        # Publish to repository
        $publishParams = @{
            Path = $PackagePath
            NuGetApiKey = $ApiKey
            Repository = $Repository
            Force = $true
            ErrorAction = 'Stop'
        }

        Publish-Module @publishParams
        Write-Verbose "Successfully published module package"

        return $true
    }
    catch {
        Write-Error "Failed to publish module package: $_"
        throw
    }
}

#endregion

#region Main Execution
try {
    # Start transcript logging
    Start-Transcript -Path $BuildLog -Force

    # Execute build process
    $buildResult = Invoke-ModuleBuild -Configuration $BuildConfiguration `
                                    -OutputPath $OutputPath `
                                    -Version $BuildVersion

    # Output build results
    $buildResult | Format-Table -AutoSize

    Write-Output "Build completed successfully"
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
#endregion