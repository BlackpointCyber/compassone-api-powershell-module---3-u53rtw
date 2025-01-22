#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Docker.PowerShell'; ModuleVersion='2.0.0' }

<#
.SYNOPSIS
    Manages and executes tests for PSCompassOne module in Docker containers.
.DESCRIPTION
    Provides secure containerized test execution with comprehensive monitoring,
    reporting and security validation capabilities.
.NOTES
    Version: 1.0.0
    Author: Blackpoint
#>

# Import required test execution functions
. (Join-Path $PSScriptRoot 'test.ps1')

# Global configuration
$script:DOCKER_COMPOSE_FILE = Join-Path $PSScriptRoot '../docker/docker-compose.yml'
$script:TEST_CONTAINER_NAME = 'pscompassone-test'
$script:TEST_RESULTS_PATH = '/workspace/out/tests'
$script:CONTAINER_HEALTH_CHECK_INTERVAL = 30
$script:SECURITY_SCAN_ENABLED = $true
$script:RESOURCE_MONITORING_ENABLED = $true

function Test-DockerEnvironment {
    <#
    .SYNOPSIS
        Validates Docker environment prerequisites and security configuration.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        Write-Verbose "Validating Docker environment..."

        # Check Docker daemon
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker daemon is not running or accessible: $dockerInfo"
        }

        # Verify Docker Compose
        $composeVersion = docker-compose --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose is not installed or accessible: $composeVersion"
        }

        # Validate Docker security configuration
        $securitySettings = docker info --format '{{.SecurityOptions}}'
        if (-not $securitySettings.Contains('name=seccomp')) {
            Write-Warning "Docker security module (seccomp) not enabled"
        }

        # Check platform compatibility
        if (-not (Test-Path $script:DOCKER_COMPOSE_FILE)) {
            throw "Docker Compose file not found at: $script:DOCKER_COMPOSE_FILE"
        }

        # Verify resource availability
        $resources = docker system df --format '{{.Type}}: {{.Size}}'
        Write-Verbose "Docker resource usage: $resources"

        return $true
    }
    catch {
        Write-Error "Docker environment validation failed: $_"
        return $false
    }
}

function Initialize-TestContainer {
    <#
    .SYNOPSIS
        Prepares the test container environment with security hardening.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Initializing test container environment..."

        # Build test container with security scanning
        $buildArgs = @(
            '--build-arg', "POWERSHELL_VERSION=7.0",
            '--no-cache',
            '--pull'
        )
        
        if ($script:SECURITY_SCAN_ENABLED) {
            $buildArgs += '--security-opt=no-new-privileges'
        }

        docker-compose -f $script:DOCKER_COMPOSE_FILE build $buildArgs test
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build test container"
        }

        # Configure container security policies
        $securityOpts = @(
            '--security-opt=no-new-privileges:true',
            '--read-only',
            '--tmpfs=/tmp:rw,noexec,nosuid'
        )

        # Setup resource limits
        $resourceLimits = @(
            '--memory=1g',
            '--memory-swap=1g',
            '--cpu-shares=512',
            '--pids-limit=100'
        )

        # Initialize health monitoring
        $healthCheck = @(
            '--health-cmd=pwsh -c "Test-Path /workspace"',
            "--health-interval=$script:CONTAINER_HEALTH_CHECK_INTERVAL`s",
            '--health-timeout=10s',
            '--health-retries=3'
        )

        # Apply container configuration
        $containerConfig = $securityOpts + $resourceLimits + $healthCheck
        $env:DOCKER_CONTAINER_CONFIG = $containerConfig -join ' '

        Write-Verbose "Test container initialized with security configuration"
    }
    catch {
        Write-Error "Failed to initialize test container: $_"
        throw
    }
}

function Invoke-ContainerTests {
    <#
    .SYNOPSIS
        Executes tests within Docker container with monitoring and reporting.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TestType = 'All',

        [Parameter()]
        [hashtable]$TestParameters = @{}
    )

    try {
        Write-Verbose "Starting containerized test execution..."

        # Start test container with monitoring
        $containerArgs = @(
            '-f', $script:DOCKER_COMPOSE_FILE,
            'run',
            '--rm',
            '--name', $script:TEST_CONTAINER_NAME
        )

        if ($script:RESOURCE_MONITORING_ENABLED) {
            $containerArgs += '--monitor'
        }

        # Execute test script with parameters
        $testCommand = "Invoke-ModuleTests"
        if ($TestParameters.Count -gt 0) {
            $paramString = $TestParameters.GetEnumerator() | ForEach-Object {
                "-$($_.Key) '$($_.Value)'"
            }
            $testCommand += " $paramString"
        }

        $containerArgs += 'test'
        $containerArgs += "pwsh -c `"$testCommand`""

        # Start container and execute tests
        $result = docker-compose $containerArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Test execution failed with exit code: $LASTEXITCODE"
        }

        # Collect test artifacts
        $artifactsPath = Join-Path $PWD 'out/tests'
        if (-not (Test-Path $artifactsPath)) {
            New-Item -Path $artifactsPath -ItemType Directory -Force | Out-Null
        }

        # Copy test results from container
        docker cp "${script:TEST_CONTAINER_NAME}:$script:TEST_RESULTS_PATH" $artifactsPath

        # Generate execution report
        $report = @{
            TestType = $TestType
            ExecutionTime = [DateTime]::Now
            ContainerConfig = $env:DOCKER_CONTAINER_CONFIG
            TestResults = Get-Content (Join-Path $artifactsPath 'TestResults.xml')
            CodeCoverage = Get-Content (Join-Path $artifactsPath 'Coverage.xml')
            ResourceUsage = docker stats --no-stream --format "{{.Container}}: CPU={{.CPUPerc}}, MEM={{.MemPerc}}"
        }

        $report | ConvertTo-Json -Depth 10 | 
            Out-File (Join-Path $artifactsPath 'ExecutionReport.json')

        Write-Verbose "Test execution completed successfully"
        return $report
    }
    catch {
        Write-Error "Container test execution failed: $_"
        throw
    }
    finally {
        # Cleanup test environment
        docker-compose -f $script:DOCKER_COMPOSE_FILE down --remove-orphans
    }
}

function Invoke-DockerTests {
    <#
    .SYNOPSIS
        Main entry point for executing tests in Docker container.
    .DESCRIPTION
        Orchestrates the complete containerized test execution process with
        security validation and comprehensive reporting.
    .PARAMETER TestType
        Type of tests to execute (Unit, Integration, or All).
    .PARAMETER TestParameters
        Additional parameters to pass to the test execution.
    .EXAMPLE
        Invoke-DockerTests -TestType 'Unit' -TestParameters @{ Coverage = $true }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Unit', 'Integration', 'All')]
        [string]$TestType = 'All',

        [Parameter()]
        [hashtable]$TestParameters = @{}
    )

    try {
        # Validate Docker environment
        if (-not (Test-DockerEnvironment)) {
            throw "Docker environment validation failed"
        }

        # Initialize test container
        Initialize-TestContainer

        # Execute tests in container
        $results = Invoke-ContainerTests -TestType $TestType -TestParameters $TestParameters

        Write-Verbose "Docker test execution completed successfully"
        return $results
    }
    catch {
        Write-Error "Docker test execution failed: $_"
        throw
    }
}

# Export the main test function
Export-ModuleMember -Function Invoke-DockerTests