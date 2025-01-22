using namespace System.Collections.Concurrent
using namespace System.Security.Cryptography

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Retrieves PSCompassOne module configuration settings with secure access controls.

.DESCRIPTION
    Public cmdlet that provides secure, performant access to PSCompassOne module configuration
    settings. Implements caching optimization, sensitive data protection, and comprehensive
    security controls for configuration management.

.PARAMETER Name
    Optional. The specific configuration setting name to retrieve.

.PARAMETER AsHashtable
    Optional. Returns the configuration as a hashtable instead of PSObject.

.PARAMETER Force
    Optional. Bypasses the cache and reloads configuration from disk.

.OUTPUTS
    PSObject
    Returns configuration settings with sensitive data properly masked.

.EXAMPLE
    Get-CompassOneConfig
    Returns all configuration settings with masked sensitive data.

.EXAMPLE
    Get-CompassOneConfig -Name 'ApiUrl'
    Returns specific setting with validation.

.EXAMPLE
    Get-CompassOneConfig -AsHashtable
    Returns settings as hashtable with protected values.

.NOTES
    File Name      : Get-CompassOneConfig.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: Microsoft.PowerShell.Security v7.0.0
#>

[CmdletBinding()]
[OutputType([PSObject])]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter()]
    [switch]$AsHashtable,

    [Parameter()]
    [switch]$Force
)

begin {
    # Constants for configuration management
    $script:ConfigCacheKey = 'PSCompassOne_Config'
    $script:ConfigCacheDuration = New-TimeSpan -Minutes 5
    $script:SensitiveKeys = @('ApiKey', 'Secret', 'Password', 'Token', 'Credential')
    $script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Config\PSCompassOne.config.psd1'
}

process {
    try {
        Write-Verbose "Retrieving configuration settings"
        $startTime = [System.Diagnostics.Stopwatch]::StartNew()

        # Check cache first unless Force is specified
        $config = $null
        if (-not $Force) {
            $config = Get-CompassOneCache -Key $script:ConfigCacheKey
        }

        # Load configuration if not in cache or Force specified
        if (-not $config) {
            Write-Verbose "Loading configuration from disk"

            # Verify configuration file exists
            if (-not (Test-Path -Path $script:ConfigPath)) {
                throw "Configuration file not found: $script:ConfigPath"
            }

            # Import configuration with error handling
            try {
                $config = Import-PowerShellDataFile -Path $script:ConfigPath
            }
            catch {
                throw "Failed to load configuration: $_"
            }

            # Validate configuration schema
            if (-not $config -or -not ($config -is [hashtable])) {
                throw "Invalid configuration format"
            }

            # Create thread-safe copy of configuration
            $threadSafeConfig = [hashtable]::Synchronized($config)

            # Store in module-level variable for fast access
            $Script:CompassOneConfig = $threadSafeConfig

            # Cache the configuration
            $cacheEntry = @{
                Value = $threadSafeConfig.Clone()
                Expiration = [DateTime]::UtcNow.Add($script:ConfigCacheDuration)
            }
            $Script:ConfigurationCache = [ConcurrentDictionary[string, object]]::new()
            $null = $Script:ConfigurationCache.TryAdd($script:ConfigCacheKey, $cacheEntry)

            Write-CompassOneLog -Message "Configuration loaded from disk" -Level Information -Source "Configuration" -Context @{
                Operation = "Load"
                Path = $script:ConfigPath
                Settings = ($config.Keys -join ',')
            }
        }

        # Create output object
        $output = $config.Clone()

        # Mask sensitive values
        foreach ($key in $script:SensitiveKeys) {
            if ($output.ContainsKey($key) -and $output[$key]) {
                $output[$key] = '********'
            }
        }

        # Filter by name if specified
        if ($Name) {
            if (-not $output.ContainsKey($Name)) {
                throw "Configuration setting not found: $Name"
            }
            $output = $output[$Name]
        }

        # Convert to appropriate output type
        if ($AsHashtable) {
            $result = $output
        }
        else {
            $result = [PSCustomObject]$output
        }

        # Log access with performance metrics
        $elapsed = $startTime.ElapsedMilliseconds
        Write-CompassOneLog -Message "Configuration retrieved successfully" -Level Verbose -Source "Configuration" -Context @{
            Operation = "Get"
            Name = $Name
            AsHashtable = $AsHashtable
            Force = $Force
            ElapsedMs = $elapsed
            CacheHit = ($null -ne $config)
        }

        return $result
    }
    catch {
        # Log error with full context
        Write-CompassOneLog -Message "Failed to retrieve configuration: $_" -Level Error -Source "Configuration" -Context @{
            Operation = "Get"
            Name = $Name
            Exception = $_.Exception.ToString()
        }
        throw
    }
    finally {
        if ($startTime) {
            $startTime.Stop()
        }
    }
}