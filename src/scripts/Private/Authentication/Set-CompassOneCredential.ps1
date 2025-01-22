using namespace System.Security.Cryptography
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.SecretStore

<#
.SYNOPSIS
    Sets or updates API credentials in the SecretStore for CompassOne authentication.

.DESCRIPTION
    Private function that securely stores and manages API credentials for the CompassOne platform
    using PowerShell SecretStore. Implements secure credential management with enhanced validation,
    encryption, and audit logging capabilities.

.PARAMETER ApiKey
    The API key for CompassOne authentication as a SecureString.

.PARAMETER ApiUrl
    The CompassOne API endpoint URL.

.PARAMETER Force
    Switch to force credential update without confirmation.

.PARAMETER EnableRotation
    Switch to enable automatic credential rotation.

.PARAMETER RotationInterval
    Interval in days for credential rotation (default: 90).

.PARAMETER ErrorAction
    Action to take when an error occurs.

.OUTPUTS
    System.Boolean
    Returns True if credentials were set successfully, False otherwise.

.NOTES
    File Name      : Set-CompassOneCredential.ps1
    Version        : 2.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
    Required Modules: Microsoft.PowerShell.SecretStore v1.0.6
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [SecureString]$ApiKey,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/?.*$')]
    [string]$ApiUrl,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$EnableRotation,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$RotationInterval = 90,

    [Parameter()]
    [ActionPreference]$ErrorAction = $ErrorActionPreference
)

begin {
    # Script-level variables
    $Script:SecretStoreKey = 'CompassOne_ApiCredentials'
    $Script:CredentialVersion = '2.0'
    $Script:MaxRetryAttempts = 3
    $Script:RetryDelaySeconds = 2

    # Generate correlation ID for tracking
    $correlationId = [guid]::NewGuid().ToString()
}

process {
    try {
        # Initialize context for logging
        $logContext = @{
            CorrelationId = $correlationId
            Operation = 'SetCredential'
            Version = $Script:CredentialVersion
            EnableRotation = $EnableRotation.IsPresent
            RotationInterval = $RotationInterval
        }

        Write-CompassOneLog -Message 'Starting credential update operation' `
                           -Level 'Information' `
                           -Source 'CredentialManager' `
                           -Context $logContext

        # Validate API key format
        if (-not $ApiKey.Length -or $ApiKey.Length -lt 32) {
            $errorDetails = @{
                Operation = 'Validation'
                CorrelationId = $correlationId
                RecommendedAction = 'Provide a valid API key with minimum length of 32 characters'
            }
            Write-CompassOneError -ErrorCategory 'ValidationError' `
                                 -ErrorCode 3001 `
                                 -ErrorDetails $errorDetails `
                                 -CorrelationId $correlationId `
                                 -ErrorAction $ErrorAction
            return $false
        }

        # Verify SecretStore is initialized
        $retryCount = 0
        $storeInitialized = $false
        do {
            try {
                $null = Get-SecretStore
                $storeInitialized = $true
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $Script:MaxRetryAttempts) {
                    throw
                }
                Start-Sleep -Seconds $Script:RetryDelaySeconds
            }
        } while ($retryCount -lt $Script:MaxRetryAttempts)

        if (-not $storeInitialized) {
            $errorDetails = @{
                Operation = 'StoreInitialization'
                CorrelationId = $correlationId
                RecommendedAction = 'Initialize SecretStore using Register-SecretVault'
            }
            Write-CompassOneError -ErrorCategory 'SecurityError' `
                                 -ErrorCode 6001 `
                                 -ErrorDetails $errorDetails `
                                 -CorrelationId $correlationId `
                                 -ErrorAction $ErrorAction
            return $false
        }

        # Create credential object with metadata
        $credentialObject = @{
            ApiKey = $ApiKey | ConvertFrom-SecureString
            ApiUrl = $ApiUrl
            Version = $Script:CredentialVersion
            Created = [DateTime]::UtcNow.ToString('o')
            LastRotated = [DateTime]::UtcNow.ToString('o')
            EnableRotation = $EnableRotation.IsPresent
            RotationInterval = $RotationInterval
            CorrelationId = $correlationId
        }

        # Convert to secure string for storage
        $secureCredential = ConvertTo-SecureString `
            -String ($credentialObject | ConvertTo-Json -Compress) `
            -AsPlainText `
            -Force

        # Store credentials with retry logic
        $retryCount = 0
        $stored = $false
        do {
            try {
                if ($Force -or $PSCmdlet.ShouldProcess("CompassOne Credentials", "Set")) {
                    Set-Secret -Name $Script:SecretStoreKey `
                              -SecureStringSecret $secureCredential `
                              -Metadata @{ Version = $Script:CredentialVersion }
                    $stored = $true
                    break
                }
            }
            catch {
                $retryCount++
                if ($retryCount -ge $Script:MaxRetryAttempts) {
                    throw
                }
                Start-Sleep -Seconds ($Script:RetryDelaySeconds * $retryCount)
            }
        } while ($retryCount -lt $Script:MaxRetryAttempts)

        if ($stored) {
            Write-CompassOneLog -Message 'Successfully updated credentials' `
                               -Level 'Information' `
                               -Source 'CredentialManager' `
                               -Context $logContext

            return $true
        }
        else {
            $errorDetails = @{
                Operation = 'Storage'
                CorrelationId = $correlationId
                RecommendedAction = 'Retry operation or check SecretStore permissions'
            }
            Write-CompassOneError -ErrorCategory 'StorageError' `
                                 -ErrorCode 6002 `
                                 -ErrorDetails $errorDetails `
                                 -CorrelationId $correlationId `
                                 -ErrorAction $ErrorAction
            return $false
        }
    }
    catch {
        $errorDetails = @{
            Operation = 'SetCredential'
            CorrelationId = $correlationId
            Exception = $_.Exception.Message
            RecommendedAction = 'Check error details and retry operation'
        }
        Write-CompassOneError -ErrorCategory 'SecurityError' `
                             -ErrorCode 6003 `
                             -ErrorDetails $errorDetails `
                             -CorrelationId $correlationId `
                             -ErrorAction $ErrorAction
        return $false
    }
    finally {
        # Clean up sensitive data
        if ($secureCredential) {
            $secureCredential.Dispose()
        }
        if ($credentialObject) {
            $credentialObject.ApiKey = $null
            $credentialObject.Clear()
        }
        [System.GC]::Collect()
    }
}