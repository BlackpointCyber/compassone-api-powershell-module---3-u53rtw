#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }, @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.20.0' }

<#
.SYNOPSIS
    Comprehensive test orchestration script for PSCompassOne module.
.DESCRIPTION
    Executes automated testing for the PSCompassOne module including unit tests,
    integration tests, code coverage analysis, and quality validation with enhanced
    security measures and cross-platform support.
.NOTES
    Version: 1.0.0
    Author: Blackpoint
#>

# Import test configuration from build settings
$TestSettings = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../templates/module.build.psd1')

# Global test configuration
$script:TestConfiguration = 'Release'
$script:TestOutputPath = Join-Path $PSScriptRoot '../out/tests'
$script:CodeCoverageThreshold = 90

function Initialize-TestEnvironment {
    <#
    .SYNOPSIS
        Initializes and validates the test environment.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose "Initializing test environment..."

    # Validate PowerShell version and platform
    if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
        throw "PowerShell version 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)"
    }

    # Verify required modules
    $requiredModules = @(
        @{ Name = 'Pester'; Version = '5.0.0' },
        @{ Name = 'PSScriptAnalyzer'; Version = '1.20.0' }
    )

    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -Name $module.Name -ListAvailable |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $installedModule -or $installedModule.Version -lt [Version]$module.Version) {
            throw "Required module $($module.Name) version $($module.Version) or higher not found"
        }
    }

    # Create and secure test output directory
    if (-not (Test-Path -Path $script:TestOutputPath)) {
        $null = New-Item -Path $script:TestOutputPath -ItemType Directory -Force
    }

    # Set up test logging
    $logPath = Join-Path $script:TestOutputPath 'test.log'
    Start-Transcript -Path $logPath -Force

    Write-Verbose "Test environment initialized successfully"
}

function Invoke-UnitTests {
    <#
    .SYNOPSIS
        Executes unit tests with enhanced coverage collection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestPath,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-Verbose "Configuring unit test execution..."

    # Configure Pester for unit tests
    $config = New-PesterConfiguration
    $config.Run.Path = $TestPath
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $OutputPath 'UnitTestResults.xml'
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.OutputPath = Join-Path $OutputPath 'Coverage.xml'
    $config.CodeCoverage.CoveragePercentageThreshold = $script:CodeCoverageThreshold

    # Execute unit tests
    Write-Verbose "Executing unit tests..."
    $results = Invoke-Pester -Configuration $config

    # Process and validate results
    if ($results.FailedCount -gt 0) {
        throw "Unit tests failed: $($results.FailedCount) tests failed"
    }

    return $results
}

function Invoke-IntegrationTests {
    <#
    .SYNOPSIS
        Executes integration tests with security validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestPath,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-Verbose "Configuring integration test execution..."

    # Configure Pester for integration tests
    $config = New-PesterConfiguration
    $config.Run.Path = $TestPath
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $OutputPath 'IntegrationTestResults.xml'

    # Execute integration tests
    Write-Verbose "Executing integration tests..."
    $results = Invoke-Pester -Configuration $config

    # Process and validate results
    if ($results.FailedCount -gt 0) {
        throw "Integration tests failed: $($results.FailedCount) tests failed"
    }

    return $results
}

function Test-CodeCoverage {
    <#
    .SYNOPSIS
        Validates code coverage against threshold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TestResults,
        
        [Parameter(Mandatory)]
        [int]$Threshold
    )

    Write-Verbose "Analyzing code coverage results..."

    $coverage = $TestResults.CodeCoverage
    $coveragePercent = [math]::Round(($coverage.CommandsExecuted / $coverage.CommandsAnalyzed) * 100, 2)

    # Generate detailed coverage report
    $coverageReport = @{
        CommandsAnalyzed = $coverage.CommandsAnalyzed
        CommandsExecuted = $coverage.CommandsExecuted
        CoveragePercent = $coveragePercent
        MissedCommands = $coverage.MissedCommands
        HitCommands = $coverage.HitCommands
    }

    # Export coverage report
    $coverageReport | ConvertTo-Json -Depth 10 | 
        Out-File (Join-Path $script:TestOutputPath 'CoverageReport.json')

    # Validate against threshold
    if ($coveragePercent -lt $Threshold) {
        throw "Code coverage ($coveragePercent%) is below threshold ($Threshold%)"
    }

    return $true
}

function Invoke-ModuleTests {
    <#
    .SYNOPSIS
        Main test execution function for PSCompassOne module.
    .DESCRIPTION
        Orchestrates the complete testing process including unit tests,
        integration tests, and code coverage validation.
    .EXAMPLE
        Invoke-ModuleTests
    #>
    [CmdletBinding()]
    param()

    try {
        # Initialize test environment
        Initialize-TestEnvironment

        Write-Verbose "Starting PSCompassOne module tests..."

        # Execute unit tests
        $unitTestPath = Join-Path $PSScriptRoot '../../src/scripts/Tests/Unit'
        $unitResults = Invoke-UnitTests -TestPath $unitTestPath -OutputPath $script:TestOutputPath

        # Validate code coverage
        Test-CodeCoverage -TestResults $unitResults -Threshold $script:CodeCoverageThreshold

        # Execute integration tests
        $integrationTestPath = Join-Path $PSScriptRoot '../../src/scripts/Tests/Integration'
        $integrationResults = Invoke-IntegrationTests -TestPath $integrationTestPath -OutputPath $script:TestOutputPath

        # Run PSScriptAnalyzer
        $analysisResults = Invoke-ScriptAnalyzer -Path $unitTestPath, $integrationTestPath -Recurse
        if ($analysisResults) {
            $analysisResults | ConvertTo-Json | Out-File (Join-Path $script:TestOutputPath 'ScriptAnalysis.json')
            throw "PSScriptAnalyzer found $($analysisResults.Count) issues"
        }

        Write-Verbose "All tests completed successfully"
    }
    catch {
        Write-Error "Test execution failed: $_"
        throw
    }
    finally {
        Stop-Transcript
    }
}

# Export the main test function
Export-ModuleMember -Function Invoke-ModuleTests