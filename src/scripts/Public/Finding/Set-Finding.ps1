#Requires -Version 7.0
using namespace System.Security
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Core 7.0.0

<#
.SYNOPSIS
    Updates an existing finding in the CompassOne platform with comprehensive validation and security controls.

.DESCRIPTION
    Updates a finding's properties with full validation, error handling, and audit logging.
    Supports pipeline operations and implements secure parameter validation with proper cleanup
    of sensitive data. Ensures thread safety and proper API rate limiting compliance.

.PARAMETER Id
    The unique identifier of the finding to update.

.PARAMETER Title
    The updated title of the finding.

.PARAMETER Class
    The updated classification of the finding (Alert, Event, Vulnerability, Compliance, Performance).

.PARAMETER Severity
    The updated severity level (Critical, High, Medium, Low, Info).

.PARAMETER Status
    The updated status (New, InProgress, Resolved, Closed, FalsePositive).

.PARAMETER Score
    The updated risk score (0.0-10.0).

.PARAMETER Description
    The updated detailed description of the finding.

.PARAMETER RelatedAssetIds
    The updated list of related asset IDs.

.PARAMETER Recommendation
    The updated remediation recommendation.

.PARAMETER PassThru
    If specified, returns the updated finding object.

.PARAMETER Force
    Suppresses confirmation prompts.

.OUTPUTS
    PSCompassOne.Finding
    Returns the updated finding object if -PassThru is specified.

.NOTES
    File Name      : Set-Finding.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [FindingClass]$Class,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [FindingSeverity]$Severity,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [FindingStatus]$Status,

    [Parameter()]
    [ValidateRange(0.0, 10.0)]
    [float]$Score,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string[]]$RelatedAssetIds,

    [Parameter()]
    [string]$Recommendation,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [switch]$Force
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting finding update operation" `
                       -Level Information `
                       -Source "FindingManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "UpdateFinding"
                       }
}

process {
    try {
        # Validate Id parameter
        if (-not (Test-CompassOneParameter -Value $Id -ParameterType "Guid" -ParameterName "Id")) {
            throw "Invalid finding ID format"
        }

        # Get existing finding to ensure it exists and validate access
        $existingFinding = Invoke-CompassOneApi -EndpointPath "/findings/$Id" `
                                               -Method "GET" `
                                               -UseCache:$false `
                                               -CorrelationId $correlationId

        if (-not $existingFinding) {
            Write-CompassOneError -ErrorCategory ResourceNotFound `
                                 -ErrorCode 4001 `
                                 -ErrorDetails @{
                                     Message = "Finding not found"
                                     Id = $Id
                                     CorrelationId = $correlationId
                                 } `
                                 -ErrorAction Stop
            return
        }

        # Create update payload with only modified properties
        $updatePayload = @{}

        if ($PSBoundParameters.ContainsKey('Title')) {
            if (-not (Test-CompassOneParameter -Value $Title -ParameterType "NonEmptyString" -ParameterName "Title")) {
                throw "Invalid title format"
            }
            $updatePayload['Title'] = $Title
        }

        if ($PSBoundParameters.ContainsKey('Class')) {
            if (-not (Test-CompassOneParameter -Value $Class -ParameterType "FindingClass" -ParameterName "Class")) {
                throw "Invalid finding class"
            }
            $updatePayload['Class'] = $Class.ToString()
        }

        if ($PSBoundParameters.ContainsKey('Severity')) {
            if (-not (Test-CompassOneParameter -Value $Severity -ParameterType "FindingSeverity" -ParameterName "Severity")) {
                throw "Invalid severity level"
            }
            $updatePayload['Severity'] = $Severity.ToString()
        }

        if ($PSBoundParameters.ContainsKey('Status')) {
            if (-not (Test-CompassOneParameter -Value $Status -ParameterType "FindingStatus" -ParameterName "Status")) {
                throw "Invalid status"
            }
            $updatePayload['Status'] = $Status.ToString()
        }

        if ($PSBoundParameters.ContainsKey('Score')) {
            $updatePayload['Score'] = $Score
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $updatePayload['Description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('RelatedAssetIds')) {
            foreach ($assetId in $RelatedAssetIds) {
                if (-not (Test-CompassOneParameter -Value $assetId -ParameterType "Guid" -ParameterName "RelatedAssetId")) {
                    throw "Invalid asset ID format: $assetId"
                }
            }
            $updatePayload['RelatedAssetIds'] = $RelatedAssetIds
        }

        if ($PSBoundParameters.ContainsKey('Recommendation')) {
            $updatePayload['Recommendation'] = $Recommendation
        }

        # Add audit information
        $updatePayload['UpdatedOn'] = [DateTime]::UtcNow.ToString('o')
        $updatePayload['UpdatedBy'] = $env:USERNAME

        # Confirm update operation
        $confirmMessage = "Are you sure you want to update finding '$($existingFinding.Title)' ($Id)?"
        if ($Force -or $PSCmdlet.ShouldProcess($confirmMessage, "Update Finding")) {
            # Update finding with retry logic
            $updatedFinding = Invoke-CompassOneApi -EndpointPath "/findings/$Id" `
                                                  -Method "PUT" `
                                                  -Body $updatePayload `
                                                  -RetryCount 3 `
                                                  -CorrelationId $correlationId

            Write-CompassOneLog -Message "Finding updated successfully" `
                               -Level Information `
                               -Source "FindingManagement" `
                               -Context @{
                                   CorrelationId = $correlationId
                                   FindingId = $Id
                                   Operation = "UpdateFinding"
                               }

            # Return updated finding if PassThru specified
            if ($PassThru) {
                return $updatedFinding
            }
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'validation' { 3001 }
            'not found' { 4001 }
            'access denied' { 6001 }
            default { 7001 }
        }

        Write-CompassOneError -ErrorCategory InvalidOperation `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to update finding: $($_.Exception.Message)"
                                 FindingId = $Id
                                 CorrelationId = $correlationId
                             } `
                             -ErrorAction Stop
    }
    finally {
        # Clean up sensitive data
        if ($updatePayload) {
            $updatePayload.Clear()
        }
        [System.GC]::Collect()
    }
}

end {
    Write-CompassOneLog -Message "Completed finding update operation" `
                       -Level Information `
                       -Source "FindingManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "UpdateFinding"
                       }
}