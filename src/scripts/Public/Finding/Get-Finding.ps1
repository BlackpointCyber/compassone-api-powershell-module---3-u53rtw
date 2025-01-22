using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Core

<#
.SYNOPSIS
    Retrieves security findings from the CompassOne platform.

.DESCRIPTION
    Retrieves security findings from the CompassOne platform with support for single finding
    retrieval by ID and filtered queries with pagination. Implements comprehensive security,
    performance optimization, and error handling capabilities.

.PARAMETER Id
    The unique identifier of a specific finding to retrieve.

.PARAMETER Class
    Filter findings by class (Alert, Event, Vulnerability, Compliance, Performance).

.PARAMETER Severity
    Filter findings by severity level (Critical, High, Medium, Low, Info).

.PARAMETER Status
    Filter findings by status (New, InProgress, Resolved, Closed, FalsePositive).

.PARAMETER AssetId
    Filter findings by related asset ID.

.PARAMETER StartDate
    Filter findings created on or after this date.

.PARAMETER EndDate
    Filter findings created before this date.

.PARAMETER PageSize
    Number of findings to return per page (default: 50, max: 100).

.PARAMETER Page
    Page number for paginated results (default: 1).

.PARAMETER Force
    Bypass cache and retrieve findings directly from the API.

.OUTPUTS
    Finding[]
    Array of Finding objects matching the specified criteria.

.EXAMPLE
    Get-Finding -Id "abc123"
    Retrieves a specific finding by ID.

.EXAMPLE
    Get-Finding -Class Alert -Severity High -Status New
    Retrieves all new high-severity alerts.

.NOTES
    File Name      : Get-Finding.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(DefaultParameterSetName='List', SupportsShouldProcess=$true)]
[OutputType([Finding])]
param(
    [Parameter(ParameterSetName='ById', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(ParameterSetName='List')]
    [ValidateScript({ Test-FindingClass $_ })]
    [FindingClass]$Class,

    [Parameter(ParameterSetName='List')]
    [ValidateScript({ Test-FindingSeverity $_ })]
    [FindingSeverity]$Severity,

    [Parameter(ParameterSetName='List')]
    [ValidateScript({ Test-FindingStatus $_ })]
    [FindingStatus]$Status,

    [Parameter(ParameterSetName='List')]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$AssetId,

    [Parameter(ParameterSetName='List')]
    [DateTime]$StartDate,

    [Parameter(ParameterSetName='List')]
    [DateTime]$EndDate,

    [Parameter(ParameterSetName='List')]
    [ValidateRange(1, 100)]
    [int]$PageSize = 50,

    [Parameter(ParameterSetName='List')]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Page = 1,

    [Parameter()]
    [switch]$Force
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [Guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting finding retrieval operation" `
                       -Level Information `
                       -Source "Get-Finding" `
                       -Context @{
                           CorrelationId = $correlationId
                           ParameterSet = $PSCmdlet.ParameterSetName
                       }
}

process {
    try {
        # Build API endpoint path
        $endpointPath = "/findings"
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $endpointPath += "/$Id"
        }

        # Check cache for single finding retrieval
        if (-not $Force -and $PSCmdlet.ParameterSetName -eq 'ById') {
            $cachedFinding = Get-CompassOneCache -Key "Finding:$Id"
            if ($cachedFinding) {
                Write-CompassOneLog -Message "Retrieved finding from cache" `
                                   -Level Verbose `
                                   -Source "Get-Finding" `
                                   -Context @{
                                       CorrelationId = $correlationId
                                       FindingId = $Id
                                   }
                return $cachedFinding
            }
        }

        # Build query parameters
        $queryParams = @{}
        
        if ($PSCmdlet.ParameterSetName -eq 'List') {
            if ($PSBoundParameters.ContainsKey('Class')) {
                $queryParams['class'] = $Class.ToString()
            }
            if ($PSBoundParameters.ContainsKey('Severity')) {
                $queryParams['severity'] = $Severity.ToString()
            }
            if ($PSBoundParameters.ContainsKey('Status')) {
                $queryParams['status'] = $Status.ToString()
            }
            if ($PSBoundParameters.ContainsKey('AssetId')) {
                $queryParams['assetId'] = $AssetId
            }
            if ($PSBoundParameters.ContainsKey('StartDate')) {
                $queryParams['startDate'] = $StartDate.ToUniversalTime().ToString('o')
            }
            if ($PSBoundParameters.ContainsKey('EndDate')) {
                $queryParams['endDate'] = $EndDate.ToUniversalTime().ToString('o')
            }
            $queryParams['pageSize'] = $PageSize
            $queryParams['page'] = $Page
        }

        # Prepare API request
        $apiParams = @{
            EndpointPath = $endpointPath
            Method = 'GET'
            QueryParameters = $queryParams
            UseCache = (-not $Force)
            CorrelationId = $correlationId
        }

        if ($PSCmdlet.ShouldProcess(
            "CompassOne API",
            "Get findings from $endpointPath"
        )) {
            # Execute API request
            $response = Invoke-CompassOneApi @apiParams

            # Process response
            if ($response) {
                $findings = @()
                
                if ($PSCmdlet.ParameterSetName -eq 'ById') {
                    # Single finding response
                    $findings += [Finding]$response
                    
                    # Cache single finding result
                    if (-not $Force) {
                        $null = Set-CompassOneCache -Key "Finding:$Id" -Value $findings[0]
                    }
                }
                else {
                    # Process paginated results
                    foreach ($item in $response.items) {
                        $findings += [Finding]$item
                    }

                    # Write pagination info
                    Write-CompassOneLog -Message "Retrieved findings page" `
                                       -Level Information `
                                       -Source "Get-Finding" `
                                       -Context @{
                                           CorrelationId = $correlationId
                                           Page = $Page
                                           TotalItems = $response.totalItems
                                           TotalPages = $response.totalPages
                                       }
                }

                return $findings
            }
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'authentication' { 1001 }  # Authentication error
            'connection' { 2001 }      # Connection error
            'validation' { 3001 }      # Validation error
            'not found' { 4001 }       # Resource not found
            'timeout' { 5001 }         # Operation timeout
            default { 7001 }           # General error
        }

        Write-CompassOneError -ErrorCategory ConnectionError `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to retrieve findings: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Endpoint = $endpointPath
                             } `
                             -ErrorAction Stop
    }
}

end {
    Write-CompassOneLog -Message "Completed finding retrieval operation" `
                       -Level Information `
                       -Source "Get-Finding" `
                       -Context @{
                           CorrelationId = $correlationId
                           ParameterSet = $PSCmdlet.ParameterSetName
                       }
}