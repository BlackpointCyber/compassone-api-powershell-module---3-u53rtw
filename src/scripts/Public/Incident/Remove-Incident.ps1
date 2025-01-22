using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Core

<#
.SYNOPSIS
    Removes an incident from the CompassOne platform.

.DESCRIPTION
    Removes an incident from the CompassOne platform with comprehensive validation,
    confirmation workflow, and audit logging. Supports both single incident removal
    by ID and bulk removal through pipeline input.

.PARAMETER Id
    The unique identifier of the incident to remove.

.PARAMETER InputObject
    The incident object to remove, supporting pipeline input.

.PARAMETER Force
    Suppresses the confirmation prompt before removing the incident.

.PARAMETER Reason
    Optional reason for incident removal, used for audit logging.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs.

.PARAMETER Confirm
    Prompts for confirmation before running the cmdlet.

.EXAMPLE
    Remove-Incident -Id "abc123"

.EXAMPLE
    Get-Incident | Where-Object Status -eq 'Closed' | Remove-Incident -Force

.NOTES
    File Name      : Remove-Incident.ps1
    Author        : Blackpoint
    Requires      : PowerShell 7.0 or later
    Version       : 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, 
               ConfirmImpact = 'High',
               DefaultParameterSetName = 'ById')]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true,
               ParameterSetName = 'ById',
               Position = 0,
               ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(Mandatory = $true,
               ParameterSetName = 'ByObject',
               ValueFromPipeline = $true)]
    [ValidateNotNull()]
    [Incident]$InputObject,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Reason
)

begin {
    # Initialize rate limiting
    $script:RequestCount = 0
    $script:RequestLimit = 10
    $script:RequestInterval = [timespan]::FromSeconds(1)
    $script:LastRequest = [datetime]::MinValue

    Write-CompassOneLog -Message "Starting incident removal operation" `
                       -Level Information `
                       -Source "IncidentManagement" `
                       -Context @{
                           Operation = "Remove"
                           ParameterSet = $PSCmdlet.ParameterSetName
                           Force = $Force.IsPresent
                       }
}

process {
    try {
        # Rate limiting check
        $now = [datetime]::UtcNow
        if (($now - $script:LastRequest) -gt $script:RequestInterval) {
            $script:RequestCount = 0
            $script:LastRequest = $now
        }
        elseif ($script:RequestCount -ge $script:RequestLimit) {
            $delay = $script:RequestInterval - ($now - $script:LastRequest)
            Start-Sleep -Milliseconds $delay.TotalMilliseconds
            $script:RequestCount = 0
            $script:LastRequest = [datetime]::UtcNow
        }
        $script:RequestCount++

        # Get incident ID based on parameter set
        $incidentId = if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
            $InputObject.Id
        } else {
            $Id
        }

        # Validate incident exists
        $apiParams = @{
            EndpointPath = "/incidents/$incidentId"
            Method = 'GET'
        }
        
        $incident = Invoke-CompassOneApi @apiParams
        if (-not $incident) {
            Write-CompassOneError -ErrorCategory ResourceNotFound `
                                -ErrorCode 4001 `
                                -ErrorDetails @{
                                    Message = "Incident not found"
                                    Id = $incidentId
                                } `
                                -ErrorAction Stop
            return
        }

        # Validate incident can be deleted
        if ($incident.Status -notin @([IncidentStatus]::Closed, [IncidentStatus]::Resolved)) {
            Write-CompassOneError -ErrorCategory InvalidOperation `
                                -ErrorCode 7001 `
                                -ErrorDetails @{
                                    Message = "Only closed or resolved incidents can be deleted"
                                    Id = $incidentId
                                    Status = $incident.Status
                                } `
                                -ErrorAction Stop
            return
        }

        # Build confirmation message
        $confirmMessage = @"
Are you sure you want to remove the following incident?
ID: $($incident.Id)
Title: $($incident.Title)
Status: $($incident.Status)
Priority: $($incident.Priority)
Created: $($incident.CreatedOn)
"@

        # Check for confirmation unless -Force is used
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($confirmMessage, "Remove Incident")) {
            return
        }

        # Log deletion attempt
        Write-CompassOneLog -Message "Removing incident" `
                           -Level Information `
                           -Source "IncidentManagement" `
                           -Context @{
                               Operation = "Remove"
                               Id = $incidentId
                               Status = $incident.Status
                               Reason = $Reason
                           }

        # Execute deletion
        $deleteParams = @{
            EndpointPath = "/incidents/$incidentId"
            Method = 'DELETE'
        }

        $null = Invoke-CompassOneApi @deleteParams

        # Log successful deletion
        Write-CompassOneLog -Message "Successfully removed incident" `
                           -Level Information `
                           -Source "IncidentManagement" `
                           -Context @{
                               Operation = "Remove"
                               Id = $incidentId
                               Status = "Deleted"
                               Reason = $Reason
                           }

        Write-Verbose "Successfully removed incident $incidentId"
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'not found' { 4001 }
            'rate limit' { 8001 }
            'permission' { 6001 }
            default { 7001 }
        }

        Write-CompassOneError -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Operation = "RemoveIncident"
                                 Id = $incidentId
                                 Error = $_.Exception.Message
                             } `
                             -ErrorAction Stop
    }
}

end {
    # Clean up any sensitive data
    if ($incident) {
        $incident = $null
    }
    [System.GC]::Collect()
}