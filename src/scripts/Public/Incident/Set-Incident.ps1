using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Updates an existing incident in the CompassOne platform with enhanced security and validation.

.DESCRIPTION
    Updates an incident with comprehensive validation, secure workflow transitions, and audit logging.
    Implements performance optimization through caching and supports pipeline input for bulk operations.

.PARAMETER Id
    The unique identifier of the incident to update.

.PARAMETER Title
    The updated title of the incident.

.PARAMETER Priority
    The updated priority level (P1-P5) of the incident.

.PARAMETER Status
    The updated status of the incident, following valid workflow transitions.

.PARAMETER Description
    The updated description of the incident.

.PARAMETER RelatedFindingIds
    Array of finding IDs related to this incident.

.PARAMETER AssignedTo
    The user or team the incident is assigned to.

.PARAMETER TicketId
    External ticket system identifier.

.PARAMETER TicketUrl
    URL to external ticket system.

.PARAMETER PassThru
    If specified, returns the updated incident object.

.PARAMETER Force
    Bypasses confirmation prompts.

.OUTPUTS
    PSObject. If -PassThru is specified, returns the updated incident object.

.NOTES
    File Name      : Set-Incident.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
[OutputType([PSObject])]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter()]
    [ValidateSet('P1', 'P2', 'P3', 'P4', 'P5')]
    [IncidentPriority]$Priority,

    [Parameter()]
    [ValidateSet('New', 'Assigned', 'InProgress', 'OnHold', 'Resolved', 'Closed')]
    [IncidentStatus]$Status,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string[]]$RelatedFindingIds,

    [Parameter()]
    [string]$AssignedTo,

    [Parameter()]
    [string]$TicketId,

    [Parameter()]
    [ValidatePattern('^https?://')]
    [string]$TicketUrl,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [switch]$Force
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting incident update operation" `
                       -Level Information `
                       -Source "IncidentManager" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "UpdateIncident"
                       }
}

process {
    try {
        # Retrieve existing incident with caching
        $cacheKey = "Incident:$Id"
        $existingIncident = Get-CompassOneCache -Key $cacheKey

        if (-not $existingIncident) {
            # Fetch from API if not cached
            $apiResponse = Invoke-CompassOneApi -EndpointPath "/incidents/$Id" `
                                              -Method GET `
                                              -CorrelationId $correlationId

            if (-not $apiResponse) {
                Write-CompassOneError -ErrorCategory ResourceNotFound `
                                    -ErrorCode 4001 `
                                    -ErrorDetails @{
                                        Message = "Incident not found"
                                        Id = $Id
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
                return
            }

            $existingIncident = $apiResponse
        }

        # Create update payload
        $updatePayload = @{}

        # Validate and add updated fields
        if ($PSBoundParameters.ContainsKey('Title')) {
            $updatePayload.Title = $Title
        }

        if ($PSBoundParameters.ContainsKey('Priority')) {
            $updatePayload.Priority = $Priority
        }

        if ($PSBoundParameters.ContainsKey('Status')) {
            # Validate workflow transition
            $isValidTransition = Test-IncidentStatus -Value $Status -CurrentStatus $existingIncident.Status
            if (-not $isValidTransition) {
                Write-CompassOneError -ErrorCategory InvalidOperation `
                                    -ErrorCode 3001 `
                                    -ErrorDetails @{
                                        Message = "Invalid status transition"
                                        CurrentStatus = $existingIncident.Status
                                        RequestedStatus = $Status
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
                return
            }
            $updatePayload.Status = $Status
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $updatePayload.Description = $Description
        }

        if ($PSBoundParameters.ContainsKey('RelatedFindingIds')) {
            $updatePayload.RelatedFindingIds = $RelatedFindingIds
        }

        if ($PSBoundParameters.ContainsKey('AssignedTo')) {
            $updatePayload.AssignedTo = $AssignedTo
        }

        if ($PSBoundParameters.ContainsKey('TicketId')) {
            $updatePayload.TicketId = $TicketId
        }

        if ($PSBoundParameters.ContainsKey('TicketUrl')) {
            $updatePayload.TicketUrl = $TicketUrl
        }

        # Add audit information
        $updatePayload.UpdatedOn = [DateTime]::UtcNow
        $updatePayload.UpdatedBy = $env:USERNAME

        # Handle status-specific timestamps
        if ($Status -eq [IncidentStatus]::Resolved -and $existingIncident.Status -ne [IncidentStatus]::Resolved) {
            $updatePayload.ResolvedOn = [DateTime]::UtcNow
            $updatePayload.ResolvedBy = $env:USERNAME
        }
        elseif ($Status -eq [IncidentStatus]::Closed -and $existingIncident.Status -ne [IncidentStatus]::Closed) {
            $updatePayload.ClosedOn = [DateTime]::UtcNow
            $updatePayload.ClosedBy = $env:USERNAME
        }

        # Confirm update unless -Force is specified
        $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
            "Incident $Id",
            "Update incident with changes: $($updatePayload | ConvertTo-Json -Compress)"
        )

        if ($shouldProcess) {
            # Perform update with retry logic
            $apiResponse = Invoke-CompassOneApi -EndpointPath "/incidents/$Id" `
                                              -Method PUT `
                                              -Body $updatePayload `
                                              -CorrelationId $correlationId

            if ($apiResponse) {
                # Update cache
                $null = Set-CompassOneCache -Key $cacheKey -Value $apiResponse

                Write-CompassOneLog -Message "Successfully updated incident" `
                                   -Level Information `
                                   -Source "IncidentManager" `
                                   -Context @{
                                       CorrelationId = $correlationId
                                       IncidentId = $Id
                                       Changes = $updatePayload
                                   }

                if ($PassThru) {
                    return $apiResponse
                }
            }
        }
    }
    catch {
        Write-CompassOneError -ErrorCategory InvalidOperation `
                             -ErrorCode 5001 `
                             -ErrorDetails @{
                                 Message = "Failed to update incident: $($_.Exception.Message)"
                                 IncidentId = $Id
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
    Write-CompassOneLog -Message "Completed incident update operation" `
                       -Level Information `
                       -Source "IncidentManager" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "UpdateIncident"
                       }
}