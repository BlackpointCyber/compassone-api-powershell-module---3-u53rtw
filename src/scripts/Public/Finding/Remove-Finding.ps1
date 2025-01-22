using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Removes a finding from the CompassOne platform.

.DESCRIPTION
    Securely removes a finding from the CompassOne platform with comprehensive validation,
    audit logging, and compliance tracking. Implements high-impact confirmation prompts
    and secure cleanup procedures.

.PARAMETER Id
    The unique identifier of the finding to remove.

.PARAMETER InputObject
    A Finding object to remove, supporting pipeline input.

.PARAMETER Force
    Suppresses the confirmation prompt before removing the finding.

.PARAMETER PassThru
    Returns the deleted finding object. By default, no output is produced.

.EXAMPLE
    Remove-Finding -Id "12345678-1234-5678-1234-567812345678"

.EXAMPLE
    Get-Finding -Status Resolved | Remove-Finding -Force

.NOTES
    File Name      : Remove-Finding.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
[OutputType([void], [PSCompassOne.Finding])]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ById')]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'ByObject')]
    [ValidateNotNull()]
    [Finding]$InputObject,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$PassThru
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [Guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting finding removal operation" `
                       -Level Information `
                       -Source "FindingManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "RemoveFinding"
                           Force = $Force.IsPresent
                           PassThru = $PassThru.IsPresent
                       }
}

process {
    try {
        # Extract finding ID based on parameter set
        $findingId = switch ($PSCmdlet.ParameterSetName) {
            'ById' { $Id }
            'ByObject' { $InputObject.Id }
        }

        # Validate finding ID format
        if (-not [Guid]::TryParse($findingId, [ref]$null)) {
            Write-CompassOneError -ErrorCategory ValidationError `
                                -ErrorCode 3001 `
                                -ErrorDetails @{
                                    Message = "Invalid finding ID format"
                                    FindingId = $findingId
                                    CorrelationId = $correlationId
                                } `
                                -ErrorAction Stop
            return
        }

        # Get finding details for confirmation and audit
        $finding = $null
        try {
            $apiResponse = Invoke-CompassOneApi -EndpointPath "/findings/$findingId" `
                                              -Method GET `
                                              -CorrelationId $correlationId

            if ($apiResponse) {
                $finding = $apiResponse
            }
            else {
                Write-CompassOneError -ErrorCategory ResourceNotFound `
                                    -ErrorCode 4001 `
                                    -ErrorDetails @{
                                        Message = "Finding not found"
                                        FindingId = $findingId
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
                return
            }
        }
        catch {
            Write-CompassOneError -ErrorCategory ConnectionError `
                                -ErrorCode 2001 `
                                -ErrorDetails @{
                                    Message = "Failed to retrieve finding details"
                                    FindingId = $findingId
                                    CorrelationId = $correlationId
                                    Error = $_.Exception.Message
                                } `
                                -ErrorAction Stop
            return
        }

        # Build confirmation message
        $confirmMessage = @"
Are you sure you want to remove this finding?
ID: $($finding.Id)
Title: $($finding.Title)
Class: $($finding.FindingClass)
Severity: $($finding.Severity)
Status: $($finding.Status)
"@

        # Check if operation should proceed
        if ($Force -or $PSCmdlet.ShouldProcess($confirmMessage, "Remove Finding")) {
            # Log pre-deletion audit entry
            Write-CompassOneLog -Message "Removing finding" `
                               -Level Information `
                               -Source "FindingManagement" `
                               -Context @{
                                   CorrelationId = $correlationId
                                   Operation = "RemoveFinding"
                                   FindingId = $findingId
                                   FindingDetails = $finding
                               }

            # Execute deletion
            try {
                $null = Invoke-CompassOneApi -EndpointPath "/findings/$findingId" `
                                           -Method DELETE `
                                           -CorrelationId $correlationId

                # Log successful deletion
                Write-CompassOneLog -Message "Finding removed successfully" `
                                   -Level Information `
                                   -Source "FindingManagement" `
                                   -Context @{
                                       CorrelationId = $correlationId
                                       Operation = "RemoveFinding"
                                       FindingId = $findingId
                                       Success = $true
                                   }

                # Return deleted finding if PassThru specified
                if ($PassThru) {
                    return $finding
                }
            }
            catch {
                Write-CompassOneError -ErrorCategory InvalidOperation `
                                    -ErrorCode 7001 `
                                    -ErrorDetails @{
                                        Message = "Failed to remove finding"
                                        FindingId = $findingId
                                        CorrelationId = $correlationId
                                        Error = $_.Exception.Message
                                    } `
                                    -ErrorAction Stop
                return
            }
        }
    }
    catch {
        # Handle unexpected errors
        Write-CompassOneError -ErrorCategory InvalidOperation `
                            -ErrorCode 7999 `
                            -ErrorDetails @{
                                Message = "Unexpected error during finding removal"
                                FindingId = $findingId
                                CorrelationId = $correlationId
                                Error = $_.Exception.Message
                            } `
                            -ErrorAction Stop
    }
    finally {
        # Clean up sensitive data
        if ($finding) {
            $finding = $null
        }
        [System.GC]::Collect()
    }
}

end {
    Write-CompassOneLog -Message "Completed finding removal operation" `
                       -Level Information `
                       -Source "FindingManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "RemoveFinding"
                           Completed = $true
                       }
}