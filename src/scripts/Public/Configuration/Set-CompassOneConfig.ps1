#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic
using namespace System.Security

# Version: Microsoft.PowerShell.Core 7.0.0

# Import required validation functions
. "$PSScriptRoot/../../Private/Validation/Test-CompassOneParameter.ps1"
. "$PSScriptRoot/../../Private/Validation/ConvertTo-CompassOneParameter.ps1"

<#
.SYNOPSIS
    Sets configuration values for the PSCompassOne module with enhanced security and compliance features.
.DESCRIPTION
    Modifies PSCompassOne module configuration settings including API endpoints, security settings,
    performance optimizations, and compliance configurations. Implements comprehensive validation
    and secure parameter handling.
.PARAMETER ApiUrl
    The CompassOne API endpoint URL. Must be HTTPS.
.PARAMETER ApiVersion
    The API version to use (e.g., 'v1').
.PARAMETER Timeout
    Request timeout in seconds (default: 30).
.PARAMETER MaxRetry
    Maximum number of retry attempts for failed requests (default: 3).
.PARAMETER LogLevel
    Logging detail level (Debug, Information, Warning, Error).
.PARAMETER CacheTTL
    Cache time-to-live in seconds (default: 300).
.PARAMETER TlsVersion
    Minimum TLS version required (default: 1.2).
.PARAMETER CertificateValidation
    Enable/disable certificate chain validation.
.PARAMETER ConnectionPoolSize
    Size of the connection pool (default: 10).
.PARAMETER AuditLogEnabled
    Enable/disable audit logging.
.PARAMETER AuditLogPath
    Path for audit log files.
.PARAMETER PassThru
    Return the updated configuration object.
.PARAMETER Force
    Skip confirmation prompts for sensitive settings.
#>
function Set-CompassOneConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ApiUrl,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ApiVersion,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$Timeout,

        [Parameter()]
        [ValidateRange(0, 10)]
        [int]$MaxRetry,

        [Parameter()]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string]$LogLevel,

        [Parameter()]
        [ValidateRange(60, 3600)]
        [int]$CacheTTL,

        [Parameter()]
        [ValidateSet('1.2', '1.3')]
        [string]$TlsVersion,

        [Parameter()]
        [bool]$CertificateValidation,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$ConnectionPoolSize,

        [Parameter()]
        [bool]$AuditLogEnabled,

        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -IsValid })]
        [string]$AuditLogPath,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Write-Verbose "Initializing Set-CompassOneConfig"
        $configPath = "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
        $currentConfig = Import-PowerShellDataFile -Path $configPath

        # Initialize secure configuration container
        $secureConfig = @{}
    }

    process {
        try {
            # Validate API URL security
            if ($PSBoundParameters.ContainsKey('ApiUrl')) {
                if (-not $ApiUrl.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
                    throw "API URL must use HTTPS protocol"
                }
                $secureConfig['ApiUrl'] = $ApiUrl
            }

            # Validate and set API version
            if ($PSBoundParameters.ContainsKey('ApiVersion')) {
                if (-not (Test-CompassOneParameter -Value $ApiVersion -ParameterType 'NonEmptyString')) {
                    throw "Invalid API version format"
                }
                $secureConfig['ApiVersion'] = $ApiVersion
            }

            # Configure security settings
            if ($PSBoundParameters.ContainsKey('TlsVersion')) {
                if ([version]$TlsVersion -lt [version]'1.2') {
                    throw "TLS version must be 1.2 or higher for security compliance"
                }
                $secureConfig['TlsVersion'] = $TlsVersion
            }

            # Configure certificate validation
            if ($PSBoundParameters.ContainsKey('CertificateValidation')) {
                if (-not $CertificateValidation -and -not $Force) {
                    if (-not $PSCmdlet.ShouldContinue(
                        "Disabling certificate validation reduces security. Are you sure?",
                        "Security Warning")) {
                        throw "Certificate validation change cancelled by user"
                    }
                }
                $secureConfig['CertificateValidation'] = $CertificateValidation
            }

            # Configure performance settings
            if ($PSBoundParameters.ContainsKey('Timeout')) {
                $secureConfig['Timeout'] = $Timeout
            }

            if ($PSBoundParameters.ContainsKey('MaxRetry')) {
                $secureConfig['MaxRetry'] = $MaxRetry
            }

            if ($PSBoundParameters.ContainsKey('ConnectionPoolSize')) {
                $secureConfig['ConnectionPoolSize'] = $ConnectionPoolSize
            }

            if ($PSBoundParameters.ContainsKey('CacheTTL')) {
                $secureConfig['CacheTTL'] = $CacheTTL
            }

            # Configure audit logging
            if ($PSBoundParameters.ContainsKey('AuditLogEnabled')) {
                $secureConfig['AuditLogEnabled'] = $AuditLogEnabled
            }

            if ($PSBoundParameters.ContainsKey('AuditLogPath')) {
                if (-not (Test-Path -Path $AuditLogPath -IsValid)) {
                    throw "Invalid audit log path specified"
                }
                $secureConfig['AuditLogPath'] = $AuditLogPath
            }

            if ($PSBoundParameters.ContainsKey('LogLevel')) {
                $secureConfig['LogLevel'] = $LogLevel
            }

            # Apply configuration changes if confirmed
            if ($PSCmdlet.ShouldProcess("PSCompassOne Configuration", "Update configuration settings")) {
                # Update configuration with secure values
                foreach ($key in $secureConfig.Keys) {
                    $currentConfig[$key] = $secureConfig[$key]
                }

                # Apply FIPS compliance settings
                $currentConfig['SecuritySettings']['Compliance']['EnforceFips'] = $true

                # Update connection pool settings
                if ($ConnectionPoolSize) {
                    $currentConfig['ConnectionSettings']['ConnectionPooling']['MaxPoolSize'] = $ConnectionPoolSize
                }

                # Save configuration securely
                $currentConfig | Export-PowerShellDataFile -Path $configPath

                Write-Verbose "Configuration updated successfully"

                # Log configuration changes to audit log if enabled
                if ($AuditLogEnabled) {
                    $auditMessage = @{
                        Timestamp = [DateTime]::UtcNow
                        Action = "ConfigurationUpdate"
                        User = $env:USERNAME
                        Changes = $secureConfig
                    }
                    Write-Verbose "Logging configuration changes to audit log"
                    # Add audit log implementation here
                }
            }

            # Return updated configuration if PassThru specified
            if ($PassThru) {
                return $currentConfig
            }
        }
        catch {
            Write-Error "Failed to update configuration: $_"
            throw
        }
    }

    end {
        Write-Verbose "Completed Set-CompassOneConfig"
    }
}

# Export the configuration cmdlet
Export-ModuleMember -Function Set-CompassOneConfig