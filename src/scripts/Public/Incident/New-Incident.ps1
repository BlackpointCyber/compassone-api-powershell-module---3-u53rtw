using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Creates a new security incident in the CompassOne platform.

.DESCRIPTION
    Creates a new security incident with comprehensive validation, error handling,
    security controls, and audit logging. Supports pipeline input and implements
    secure API communication with retry logic.

.PARAMETER Title
    The title of the incident. Required.

.PARAMETER Priority
    The incident priority (P1-P5). Required.

.PARAMETER Description
    Optional description of the incident.

.PARAMETER RelatedFindingIds
    Optional array of related finding IDs.

.PARAMETER AssignedTo
    Optional email address of the user assigned to the incident.

.PARAMETER TicketId
    Optional external ticket ID for integration purposes.

.PARAMETER TicketUrl
    Optional URL to external ticket system.

.PARAMETER PassThru
    If specified, returns the created incident object.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs.

.PARAMETER Confirm
    Prompts for confirmation before running the cmdlet.

.OUTPUTS
    PSCustomObject. If -PassThru is specified, returns the created incident object.

.EXAMPLE
    New-Incident -Title "Critical Service Outage" -Priority P1 -Description "Production service down"

.NOTES
    File Name      : New-Incident.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Standard')]
[OutputType([PSCustomObject])]
[Alias('Create-Incident')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateSet('P1', 'P2', 'P3', 'P4', 'P5')]
    [IncidentPriority]$Priority,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string[]]$RelatedFindingIds,

    [Parameter()]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$AssignedTo,

    [Parameter()]
    [string]$TicketId,

    [Parameter()]
    [ValidatePattern('^https://')]
    [string]$TicketUrl,

    [Parameter()]
    [switch]$PassThru
)

begin {
    Write-CompassOneLog -Message "Starting incident creation" `
                       -Level Information `
                       -Source "IncidentManager" `
                       -Context @{
                           Operation = "Create"
                           Title = $Title
                           Priority = $Priority
                       }

    # Generate correlation ID for request tracking
    $correlationId = [Guid]::NewGuid().ToString()
}

process {
    try {
        # Validate required parameters
        if ([string]::IsNullOrWhiteSpace($Title)) {
            Write-CompassOneError -ErrorCategory ValidationError `
                                -ErrorCode 3001 `
                                -ErrorDetails @{
                                    Message = "Title cannot be null or empty"
                                    CorrelationId = $correlationId
                                } `
                                -ErrorAction Stop
        }

        # Create new incident object with validated parameters
        $incident = [Incident]::new($Title, $Priority, $RelatedFindingIds)
        
        # Set optional properties
        if ($PSBoundParameters.ContainsKey('Description')) {
            $incident.Description = $Description
        }
        if ($PSBoundParameters.ContainsKey('AssignedTo')) {
            $incident.AssignedTo = $AssignedTo
        }
        if ($PSBoundParameters.ContainsKey('TicketId')) {
            $incident.TicketId = $TicketId
        }
        if ($PSBoundParameters.ContainsKey('TicketUrl')) {
            $incident.TicketUrl = $TicketUrl
        }

        # Validate incident object
        if (-not $incident.Validate()) {
            Write-CompassOneError -ErrorCategory ValidationError `
                                -ErrorCode 3002 `
                                -ErrorDetails @{
                                    Message = "Incident validation failed"
                                    CorrelationId = $correlationId
                                } `
                                -ErrorAction Stop
        }

        # WhatIf support
        $operationMessage = "Create incident: $Title (Priority: $Priority)"
        if ($PSCmdlet.ShouldProcess($operationMessage, "Create Incident", "CompassOne Incident Creation")) {
            try {
                # Prepare API request
                $apiEndpoint = "/incidents"
                $apiBody = @{
                    title = $incident.Title
                    priority = $incident.Priority.ToString()
                    description = $incident.Description
                    relatedFindingIds = $incident.RelatedFindingIds
                    assignedTo = $incident.AssignedTo
                    ticketId = $incident.TicketId
                    ticketUrl = $incident.TicketUrl
                }

                # Execute API request with retry logic
                $response = Invoke-CompassOneApi -EndpointPath $apiEndpoint `
                                               -Method POST `
                                               -Body $apiBody `
                                               -CorrelationId $correlationId

                if ($PassThru) {
                    return $response
                }

                Write-CompassOneLog -Message "Successfully created incident" `
                                   -Level Information `
                                   -Source "IncidentManager" `
                                   -Context @{
                                       Operation = "Create"
                                       IncidentId = $response.id
                                       Title = $Title
                                       Priority = $Priority
                                       CorrelationId = $correlationId
                                   }
            }
            catch {
                Write-CompassOneError -ErrorCategory ConnectionError `
                                    -ErrorCode 2001 `
                                    -ErrorDetails @{
                                        Message = "Failed to create incident: $($_.Exception.Message)"
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
            }
        }
    }
    catch {
        Write-CompassOneError -ErrorCategory InvalidOperation `
                            -ErrorCode 7001 `
                            -ErrorDetails @{
                                Message = "Incident creation failed: $($_.Exception.Message)"
                                CorrelationId = $correlationId
                            } `
                            -ErrorAction Stop
    }
    finally {
        # Clean up sensitive data
        if ($incident) {
            $incident = $null
        }
        if ($apiBody) {
            $apiBody.Clear()
        }
        [System.GC]::Collect()
    }
}