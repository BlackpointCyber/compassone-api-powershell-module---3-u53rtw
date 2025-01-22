using namespace System.Management.Automation # Version 7.0.0

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Writes standardized error records for the PSCompassOne module.

.DESCRIPTION
    Private function that writes standardized error records with appropriate error categories,
    logging, and error handling. Provides consistent error reporting across the module with
    enhanced security, correlation tracking, and compliance features.

.PARAMETER ErrorCategory
    The category of the error (AuthenticationError, ConnectionError, etc.).

.PARAMETER ErrorCode
    The numeric error code (1000-9999) that identifies the specific error.

.PARAMETER ErrorDetails
    Optional hashtable containing additional error details to be included in the message.

.PARAMETER TargetObject
    The object that was being processed when the error occurred.

.PARAMETER CorrelationId
    Optional correlation ID for tracking related operations.

.PARAMETER ErrorAction
    Determines how the cmdlet responds to a non-terminating error.

.NOTES
    File Name      : Write-CompassOneError.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'AuthenticationError',
        'ConnectionError',
        'ValidationError',
        'ResourceNotFound',
        'OperationTimeout',
        'SecurityError',
        'InvalidOperation',
        'LimitExceeded'
    )]
    [string]$ErrorCategory,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1000, 9999)]
    [int]$ErrorCode,

    [Parameter()]
    [hashtable]$ErrorDetails = @{},

    [Parameter()]
    [object]$TargetObject,

    [Parameter()]
    [string]$CorrelationId = [Guid]::NewGuid().ToString(),

    [Parameter()]
    [System.Management.Automation.ActionPreference]
    $ErrorAction = $ErrorActionPreference
)

begin {
    # Error category mapping
    $errorCategoryMap = @{
        'AuthenticationError' = [ErrorCategory]::AuthenticationError
        'ConnectionError'     = [ErrorCategory]::ConnectionError
        'ValidationError'     = [ErrorCategory]::InvalidData
        'ResourceNotFound'    = [ErrorCategory]::ObjectNotFound
        'OperationTimeout'    = [ErrorCategory]::OperationTimeout
        'SecurityError'       = [ErrorCategory]::SecurityError
        'InvalidOperation'    = [ErrorCategory]::InvalidOperation
        'LimitExceeded'      = [ErrorCategory]::LimitsExceeded
    }
}

process {
    try {
        # Add correlation ID to error details
        $ErrorDetails['CorrelationId'] = $CorrelationId

        # Remove any sensitive information from error details
        foreach ($key in @($ErrorDetails.Keys)) {
            if ($key -match '(password|secret|key|token|credential)') {
                $ErrorDetails[$key] = '***REDACTED***'
            }
        }

        # Get formatted error message
        $errorMessage = Get-CompassOneErrorMessage -ErrorCategory $ErrorCategory `
                                                 -ErrorCode $ErrorCode `
                                                 -ErrorDetails $ErrorDetails

        # Create exception with security-enhanced properties
        $exception = New-Object System.Security.SecurityException $errorMessage
        $exception.Data.Add('ErrorCode', $ErrorCode)
        $exception.Data.Add('CorrelationId', $CorrelationId)
        $exception.Data.Add('Timestamp', [DateTime]::UtcNow.ToString('o'))

        # Create error record with enhanced properties
        $errorRecord = New-Object System.Management.Automation.ErrorRecord(
            $exception,
            "COMPASSONE_${ErrorCode}",
            $errorCategoryMap[$ErrorCategory],
            $TargetObject
        )

        # Add enhanced error properties
        $errorRecord.ErrorDetails = New-Object System.Management.Automation.ErrorDetails $errorMessage
        $errorRecord.ErrorDetails.RecommendedAction = $ErrorDetails['RecommendedAction']
        
        # Log error with secure audit trail
        $logContext = @{
            'CorrelationId' = $CorrelationId
            'ErrorCode'     = $ErrorCode
            'ErrorCategory' = $ErrorCategory
            'TargetObject'  = if ($TargetObject) { $TargetObject.ToString() } else { $null }
            'CommandName'   = $MyInvocation.MyCommand.Name
            'ScriptName'    = $MyInvocation.ScriptName
            'ScriptLine'    = $MyInvocation.ScriptLineNumber
        }

        Write-CompassOneLog -Message $errorMessage `
                           -Level 'Error' `
                           -Source 'ErrorHandler' `
                           -Context $logContext

        # Write error based on error action preference
        switch ($ErrorAction) {
            'Stop' {
                throw $errorRecord
            }
            'Continue' {
                $PSCmdlet.WriteError($errorRecord)
            }
            'SilentlyContinue' {
                # Do nothing
            }
            default {
                $PSCmdlet.WriteError($errorRecord)
            }
        }
    }
    catch {
        # Handle error writing failures
        $fallbackError = "Failed to write error record: $_"
        Write-Warning $fallbackError

        # Attempt to log failure
        try {
            Write-CompassOneLog -Message $fallbackError `
                               -Level 'Error' `
                               -Source 'ErrorHandler' `
                               -Context @{ 'CorrelationId' = $CorrelationId }
        }
        catch {
            # Suppress logging failures
        }

        # Ensure original error is not lost
        if ($ErrorAction -eq 'Stop') {
            throw $_
        }
        else {
            Write-Error -Message $fallbackError
        }
    }
    finally {
        # Clean up sensitive data
        if ($ErrorDetails) {
            foreach ($key in @($ErrorDetails.Keys)) {
                $ErrorDetails[$key] = $null
            }
            $ErrorDetails.Clear()
        }
        [System.GC]::Collect()
    }
}