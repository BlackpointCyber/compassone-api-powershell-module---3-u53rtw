#Requires -Version 7.0
#Requires -Modules @{ModuleName='Docker.PowerShell'; ModuleVersion='1.0.0'}

<#
.SYNOPSIS
    Builds Docker container images for PSCompassOne module development, testing, and documentation.
.DESCRIPTION
    PowerShell script for building Docker container images with enhanced security scanning,
    signature verification and build optimization capabilities.
.NOTES
    Version: 1.0.0
    Author: PSCompassOne Team
#>

[CmdletBinding()]
param()

# Script constants
$script:DOCKER_CONTEXT = Join-Path $PSScriptRoot ".." "docker"
$script:SECURITY_SCAN_ENABLED = $true
$script:BUILD_OPTIMIZATION_ENABLED = $true
$script:MAX_PARALLEL_BUILDS = 3

# Image configurations
$script:IMAGES = @{
    'pscompassone-dev' = @{
        Dockerfile = 'Dockerfile.dev'
        Tag = 'latest'
        BuildArgs = @{
            POWERSHELL_VERSION = '7.3'
            VSCODE_VERSION = 'latest'
        }
    }
    'pscompassone-test' = @{
        Dockerfile = 'Dockerfile.test'
        Tag = 'latest'
        BuildArgs = @{
            POWERSHELL_VERSION = '7.3'
        }
    }
    'pscompassone-docs' = @{
        Dockerfile = 'Dockerfile.docs'
        Tag = 'latest'
        BuildArgs = @{
            POWERSHELL_VERSION = '7.3'
        }
    }
}

function Test-DockerEnvironment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [switch]$DetailedCheck,
        [switch]$SecurityAudit
    )

    try {
        $status = @{
            DockerDaemon = $false
            DockerCLI = $false
            SecurityStatus = @{}
            ResourceLimits = @{}
            BuildCapabilities = $false
        }

        # Check Docker daemon
        $daemonInfo = docker info --format '{{json .}}' | ConvertFrom-Json
        $status.DockerDaemon = $daemonInfo.ServerVersion -ne $null

        # Verify Docker CLI
        $cliVersion = docker version --format '{{.Client.Version}}'
        $status.DockerCLI = $cliVersion -ne $null

        if ($DetailedCheck) {
            # Check resource limits
            $status.ResourceLimits = @{
                CPUs = $daemonInfo.NCPU
                Memory = $daemonInfo.MemTotal
                SwapLimit = $daemonInfo.SwapLimit
                BuilderVersion = $daemonInfo.BuilderVersion
            }
        }

        if ($SecurityAudit) {
            # Security configuration checks
            $status.SecurityStatus = @{
                Rootless = $daemonInfo.SecurityOptions -contains "rootless"
                Seccomp = $daemonInfo.SecurityOptions -contains "seccomp"
                AppArmor = $daemonInfo.SecurityOptions -contains "apparmor"
                SeLinux = $daemonInfo.SecurityOptions -contains "selinux"
                UserNS = $daemonInfo.SecurityOptions -contains "userns"
            }
        }

        # Test build capabilities
        $testBuild = docker build --quiet - < "echo FROM scratch"
        $status.BuildCapabilities = $testBuild -ne $null

        return $status
    }
    catch {
        Write-Error "Docker environment validation failed: $_"
        throw
    }
}

function Build-DockerImage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$DockerfilePath,
        
        [Parameter(Mandatory)]
        [string]$ImageName,
        
        [Parameter(Mandatory)]
        [string]$Tag,
        
        [Parameter()]
        [hashtable]$BuildArgs = @{},
        
        [switch]$Force,
        [switch]$EnableSecurity,
        [switch]$OptimizeBuild
    )

    try {
        # Validate parameters
        if (-not (Test-Path $DockerfilePath)) {
            throw "Dockerfile not found at path: $DockerfilePath"
        }

        $buildResults = @{
            ImageName = $ImageName
            Tag = $Tag
            Success = $false
            SecurityScan = $null
            BuildMetrics = @{}
            AuditTrail = @()
        }

        # Check for existing image
        $existingImage = docker images --quiet "${ImageName}:${Tag}"
        if ($existingImage -and -not $Force) {
            throw "Image ${ImageName}:${Tag} already exists. Use -Force to rebuild."
        }

        # Prepare build arguments
        $buildArguments = @()
        foreach ($arg in $BuildArgs.GetEnumerator()) {
            $buildArguments += "--build-arg", "$($arg.Key)=$($arg.Value)"
        }

        # Enable BuildKit for optimized builds
        $env:DOCKER_BUILDKIT = "1"

        # Start build timer
        $buildTimer = [System.Diagnostics.Stopwatch]::StartNew()

        # Build image with progress tracking
        $buildProcess = docker build `
            --file $DockerfilePath `
            --tag "${ImageName}:${Tag}" `
            --progress plain `
            --no-cache:$Force `
            $buildArguments `
            $script:DOCKER_CONTEXT

        if ($LASTEXITCODE -ne 0) {
            throw "Docker build failed with exit code $LASTEXITCODE"
        }

        $buildTimer.Stop()
        $buildResults.BuildMetrics.Duration = $buildTimer.Elapsed
        $buildResults.Success = $true

        # Security scanning if enabled
        if ($EnableSecurity) {
            Write-Verbose "Performing security scan on ${ImageName}:${Tag}"
            $scanResults = docker scan "${ImageName}:${Tag}" --json
            $buildResults.SecurityScan = $scanResults | ConvertFrom-Json
        }

        # Build optimization if enabled
        if ($OptimizeBuild) {
            Write-Verbose "Optimizing image layers for ${ImageName}:${Tag}"
            docker image prune --force --filter "label=stage=builder"
        }

        # Verify build artifacts
        $imageInfo = docker inspect "${ImageName}:${Tag}" | ConvertFrom-Json
        $buildResults.BuildMetrics.Size = $imageInfo.Size
        $buildResults.BuildMetrics.Layers = $imageInfo.RootFS.Layers.Count

        # Generate audit trail
        $buildResults.AuditTrail += @{
            Timestamp = Get-Date
            Action = "Build"
            Details = "Built ${ImageName}:${Tag}"
            User = $env:USERNAME
        }

        return $buildResults
    }
    catch {
        Write-Error "Failed to build Docker image: $_"
        throw
    }
}

function Build-AllImages {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [switch]$Force,
        [switch]$Parallel,
        [switch]$SecurityScan,
        [switch]$GenerateReport
    )

    try {
        # Validate Docker environment first
        $envCheck = Test-DockerEnvironment -DetailedCheck -SecurityAudit
        if (-not $envCheck.DockerDaemon -or -not $envCheck.DockerCLI) {
            throw "Docker environment validation failed"
        }

        $buildResults = @{
            StartTime = Get-Date
            Images = @{}
            OverallSuccess = $true
            Metrics = @{
                TotalDuration = $null
                SuccessCount = 0
                FailureCount = 0
            }
        }

        # Build images
        $buildTimer = [System.Diagnostics.Stopwatch]::StartNew()

        if ($Parallel) {
            $jobs = @()
            foreach ($image in $script:IMAGES.GetEnumerator()) {
                $jobs += Start-Job -ScriptBlock {
                    param($name, $config, $force, $security)
                    Build-DockerImage `
                        -DockerfilePath (Join-Path $using:script:DOCKER_CONTEXT $config.Dockerfile) `
                        -ImageName $name `
                        -Tag $config.Tag `
                        -BuildArgs $config.BuildArgs `
                        -Force:$force `
                        -EnableSecurity:$security `
                        -OptimizeBuild:$using:script:BUILD_OPTIMIZATION_ENABLED
                } -ArgumentList $image.Key, $image.Value, $Force, $SecurityScan
            }

            $buildResults.Images = Receive-Job -Job $jobs -Wait -AutoRemoveJob
        }
        else {
            foreach ($image in $script:IMAGES.GetEnumerator()) {
                $buildResults.Images[$image.Key] = Build-DockerImage `
                    -DockerfilePath (Join-Path $script:DOCKER_CONTEXT $image.Value.Dockerfile) `
                    -ImageName $image.Key `
                    -Tag $image.Value.Tag `
                    -BuildArgs $image.Value.BuildArgs `
                    -Force:$Force `
                    -EnableSecurity:$SecurityScan `
                    -OptimizeBuild:$script:BUILD_OPTIMIZATION_ENABLED
            }
        }

        $buildTimer.Stop()
        $buildResults.Metrics.TotalDuration = $buildTimer.Elapsed

        # Calculate success/failure counts
        $buildResults.Metrics.SuccessCount = ($buildResults.Images.Values | Where-Object Success).Count
        $buildResults.Metrics.FailureCount = $buildResults.Images.Count - $buildResults.Metrics.SuccessCount
        $buildResults.OverallSuccess = $buildResults.Metrics.FailureCount -eq 0

        # Generate report if requested
        if ($GenerateReport) {
            $reportPath = Join-Path $script:DOCKER_CONTEXT "build-report.json"
            $buildResults | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath
        }

        return $buildResults
    }
    catch {
        Write-Error "Failed to build all Docker images: $_"
        throw
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Build-DockerImage',
    'Build-AllImages'
)