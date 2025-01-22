using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Retrieves incidents from the CompassOne platform with comprehensive filtering and pagination support.

.DESCRIPTION
    Public cmdlet that retrieves incidents from the CompassOne platform. Implements comprehensive
    incident management with advanced filtering, caching, pipeline support, and robust error handling.
    Supports both single incident retrieval by ID and bulk operations with pagination.

.PARAMETER Id
    The unique identifier of the incident to retrieve.

.PARAMETER Title
    Filter incidents by title (supports partial matches).

.PARAMETER Status
    Filter incidents by status (New, InProgress, Resolved, Closed).

.PARAMETER Priority
    Filter incidents by priority (Low, Medium, High, Critical).

.PARAMETER AssignedTo
    Filter incidents by assigned user.

.PARAMETER CreatedAfter
    Filter incidents created after specified date/time.

.PARAMETER CreatedBefore
    Filter incidents created before specified date/time.

.PARAMETER PageSize
    Number of incidents to return per page (default: 50, max: 100).

.PARAMETER Page
    Page number for paginated results (default: 1).

.PARAMETER SortBy
    Field to sort results by (CreatedOn, Priority, Status, Title).

.PARAMETER SortOrder
    Sort order for results (Ascending, Descending).

.PARAMETER Raw
    Return raw API response instead of processed objects.

.OUTPUTS
    PSObject[]
    Collection of strongly-typed Incident objects or raw API response if -Raw switch is used.

.NOTES
    File Name      : Get-Incident.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(DefaultParameterSetName='List', SupportsShouldProcess=$true)]
[OutputType([PSObject[]])]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ById', Position=0, ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(ParameterSetName='List')]
    [ValidateLength(1, 255)]
    [string]$Title,

    [Parameter(ParameterSetName='List')]
    [ValidateSet('New', 'InProgress', 'Resolved', 'Closed')]
    [string]$Status,

    [Parameter(ParameterSetName='List')]
    [ValidateSet('Low', 'Medium', 'High', 'Critical')]
    [string]$Priority,

    [Parameter(ParameterSetName='List')]
    [ValidateNotNullOrEmpty()]
    [string]$AssignedTo,

    [Parameter(ParameterSetName='List')]
    [ValidateNotNull()]
    [DateTime]$CreatedAfter,

    [Parameter(ParameterSetName='List')]
    [ValidateNotNull()]
    [DateTime]$CreatedBefore,

    [Parameter(ParameterSetName='List')]
    [ValidateRange(1, 100)]
    [int]$PageSize = 50,

    [Parameter(ParameterSetName='List')]
    [ValidateRange(1, 2147483647)]
    [int]$Page = 1,

    [Parameter(ParameterSetName='List')]
    [ValidateSet('CreatedOn', 'Priority', 'Status', 'Title')]
    [string]$SortBy = 'CreatedOn',

    [Parameter(ParameterSetName='List')]
    [ValidateSet('Ascending', 'Descending')]
    [string]$SortOrder = 'Descending',

    [Parameter(ParameterSetName='ById')]
    [Parameter(ParameterSetName='List')]
    [switch]$Raw
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting incident retrieval operation" `
                       -Level Information `
                       -Source "Get-Incident" `
                       -Context @{
                           CorrelationId = $correlationId
                           ParameterSet = $PSCmdlet.ParameterSetName
                       }
}

process {
    try {
        # Build API endpoint path
        $endpointPath = "/incidents"
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $endpointPath += "/$Id"
        }

        # Check cache for single incident retrieval
        if ($PSCmdlet.ParameterSetName -eq 'ById' -and -not $Raw) {
            $cachedIncident = Get-CompassOneCache -Key "Incident:$Id"
            if ($cachedIncident) {
                return $cachedIncident
            }
        }

        # Build query parameters for list operation
        $queryParams = @{}
        if ($PSCmdlet.ParameterSetName -eq 'List') {
            if ($Title) { $queryParams['title'] = $Title }
            if ($Status) { $queryParams['status'] = $Status }
            if ($Priority) { $queryParams['priority'] = $Priority }
            if ($AssignedTo) { $queryParams['assignedTo'] = $AssignedTo }
            if ($CreatedAfter) { $queryParams['createdAfter'] = $CreatedAfter.ToUniversalTime().ToString('o') }
            if ($CreatedBefore) { $queryParams['createdBefore'] = $CreatedBefore.ToUniversalTime().ToString('o') }
            $queryParams['pageSize'] = $PageSize
            $queryParams['page'] = $Page
            $queryParams['sortBy'] = $SortBy
            $queryParams['sortOrder'] = $SortOrder.ToLower()
        }

        # Execute API request with retry logic
        $response = Invoke-CompassOneApi -EndpointPath $endpointPath `
                                       -Method 'GET' `
                                       -QueryParameters $queryParams `
                                       -UseCache:(-not $Raw) `
                                       -CorrelationId $correlationId

        # Return raw response if requested
        if ($Raw) {
            return $response
        }

        # Process response into strongly-typed objects
        $incidents = @()
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            if (-not $response) {
                Write-CompassOneError -ErrorCategory ResourceNotFound `
                                    -ErrorCode 4001 `
                                    -ErrorDetails @{
                                        Message = "Incident not found"
                                        Id = $Id
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
            }

            $incident = [PSCustomObject]@{
                PSTypeName = 'PSCompassOne.Incident'
                Id = $response.id
                Title = $response.title
                Status = $response.status
                Priority = $response.priority
                AssignedTo = $response.assignedTo
                CreatedOn = [DateTime]::Parse($response.createdOn)
                LastModifiedOn = $response.lastModifiedOn ? [DateTime]::Parse($response.lastModifiedOn) : $null
                Description = $response.description
                RelatedFindingIds = $response.relatedFindingIds
                TicketId = $response.ticketId
                TicketUrl = $response.ticketUrl
            }

            # Cache single incident result
            Set-CompassOneCache -Key "Incident:$($incident.Id)" -Value $incident

            $incidents = @($incident)
        }
        else {
            $incidents = $response.items | ForEach-Object {
                [PSCustomObject]@{
                    PSTypeName = 'PSCompassOne.Incident'
                    Id = $_.id
                    Title = $_.title
                    Status = $_.status
                    Priority = $_.priority
                    AssignedTo = $_.assignedTo
                    CreatedOn = [DateTime]::Parse($_.createdOn)
                    LastModifiedOn = $_.lastModifiedOn ? [DateTime]::Parse($_.lastModifiedOn) : $null
                    Description = $_.description
                    RelatedFindingIds = $_.relatedFindingIds
                    TicketId = $_.ticketId
                    TicketUrl = $_.ticketUrl
                }
            }
        }

        Write-CompassOneLog -Message "Successfully retrieved incidents" `
                           -Level Information `
                           -Source "Get-Incident" `
                           -Context @{
                               CorrelationId = $correlationId
                               Count = $incidents.Count
                               ParameterSet = $PSCmdlet.ParameterSetName
                           }

        return $incidents
    }
    catch {
        Write-CompassOneError -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                             -ErrorCode 7001 `
                             -ErrorDetails @{
                                 Message = "Failed to retrieve incidents: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 ParameterSet = $PSCmdlet.ParameterSetName
                             } `
                             -ErrorAction Stop
        throw
    }
}

end {
    # Cleanup
    [System.GC]::Collect()
}