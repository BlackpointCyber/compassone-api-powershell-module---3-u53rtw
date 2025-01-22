using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Core

<#
.SYNOPSIS
    Retrieves assets from the CompassOne platform.

.DESCRIPTION
    Gets assets from CompassOne with support for single asset retrieval, filtered queries,
    pagination, and performance optimization through caching. Implements comprehensive error
    handling, correlation tracking, and memory management for large result sets.

.PARAMETER Id
    The unique identifier of a specific asset to retrieve.

.PARAMETER Name
    Filter assets by name. Supports wildcards.

.PARAMETER Class
    Filter assets by asset class (Device, Container, Software, Network, Unknown).

.PARAMETER Status
    Filter assets by status (Active, Inactive, Archived, Deleted).

.PARAMETER Tags
    Filter assets by one or more tags.

.PARAMETER PageSize
    Number of items to return per page. Default is 50.

.PARAMETER Page
    Page number to retrieve. Default is 1.

.PARAMETER UseCache
    Use cached results if available.

.PARAMETER Force
    Bypass cache and force a new API request.

.PARAMETER IncludeRelationships
    Include relationship data for returned assets.

.OUTPUTS
    PSCompassOne.Asset[]. Array of Asset objects matching the specified criteria.

.EXAMPLE
    Get-Asset -Id "abc123"
    Retrieves a specific asset by ID.

.EXAMPLE
    Get-Asset -Class Device -Status Active -UseCache
    Retrieves all active devices using cached results if available.

.EXAMPLE
    Get-Asset -Tags "Production" -PageSize 50
    Retrieves assets tagged as "Production" with 50 items per page.

.NOTES
    File Name      : Get-Asset.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(DefaultParameterSetName = 'List', SupportsShouldProcess = $true)]
[OutputType([PSCompassOne.Asset[]])]
param(
    [Parameter(ParameterSetName = 'ById', Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(ParameterSetName = 'List')]
    [ValidateNotNullOrEmpty()]
    [SupportsWildcards()]
    [string]$Name,

    [Parameter(ParameterSetName = 'List')]
    [ValidateSet('Device', 'Container', 'Software', 'Network', 'Unknown')]
    [string]$Class,

    [Parameter(ParameterSetName = 'List')]
    [ValidateSet('Active', 'Inactive', 'Archived', 'Deleted')]
    [string]$Status,

    [Parameter(ParameterSetName = 'List')]
    [string[]]$Tags,

    [Parameter(ParameterSetName = 'List')]
    [ValidateRange(1, 100)]
    [int]$PageSize = 50,

    [Parameter(ParameterSetName = 'List')]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Page = 1,

    [Parameter()]
    [switch]$UseCache,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$IncludeRelationships
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting asset retrieval operation" `
                       -Level Information `
                       -Source "AssetManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           ParameterSet = $PSCmdlet.ParameterSetName
                           Operation = "GetAsset"
                       }

    # Initialize result collection with proper capacity
    $results = [List[PSCompassOne.Asset]]::new($PageSize)
}

process {
    try {
        # Build query parameters
        $queryParams = @{
            'include_relationships' = $IncludeRelationships.IsPresent
        }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $endpoint = "/assets/$Id"
        }
        else {
            $endpoint = "/assets"
            $queryParams += @{
                'page_size' = $PageSize
                'page' = $Page
            }

            if ($Name) {
                $queryParams['name'] = $Name
            }
            if ($Class) {
                $queryParams['class'] = $Class
            }
            if ($Status) {
                $queryParams['status'] = $Status
            }
            if ($Tags) {
                $queryParams['tags'] = $Tags -join ','
            }
        }

        # Check cache if enabled and not forced
        if ($UseCache -and -not $Force) {
            $cacheKey = "Assets:$($queryParams | ConvertTo-Json -Compress)"
            $cachedResult = Get-CompassOneCache -Key $cacheKey

            if ($cachedResult) {
                Write-CompassOneLog -Message "Returning cached assets" `
                                   -Level Verbose `
                                   -Source "AssetManagement" `
                                   -Context @{
                                       CorrelationId = $correlationId
                                       CacheHit = $true
                                       Count = $cachedResult.Count
                                   }
                return $cachedResult
            }
        }

        # Make API request with retry logic
        $response = Invoke-CompassOneApi -EndpointPath $endpoint `
                                       -Method GET `
                                       -QueryParameters $queryParams

        # Process response
        if ($response) {
            if ($PSCmdlet.ParameterSetName -eq 'ById') {
                # Single asset response
                $asset = [PSCompassOne.Asset]@{
                    Id = $response.id
                    Name = $response.name
                    Class = $response.class
                    Status = $response.status
                    Tags = $response.tags
                    Description = $response.description
                    FoundOn = $response.found_on
                    LastSeenOn = $response.last_seen_on
                    CreatedOn = $response.created_on
                    CreatedBy = $response.created_by
                    UpdatedOn = $response.updated_on
                    UpdatedBy = $response.updated_by
                    DeletedOn = $response.deleted_on
                    DeletedBy = $response.deleted_by
                }

                if ($IncludeRelationships) {
                    $asset.Relationships = $response.relationships
                }

                $results.Add($asset)
            }
            else {
                # Process paginated results
                foreach ($item in $response.items) {
                    $asset = [PSCompassOne.Asset]@{
                        Id = $item.id
                        Name = $item.name
                        Class = $item.class
                        Status = $item.status
                        Tags = $item.tags
                        Description = $item.description
                        FoundOn = $item.found_on
                        LastSeenOn = $item.last_seen_on
                        CreatedOn = $item.created_on
                        CreatedBy = $item.created_by
                        UpdatedOn = $item.updated_on
                        UpdatedBy = $item.updated_by
                        DeletedOn = $item.deleted_on
                        DeletedBy = $item.deleted_by
                    }

                    if ($IncludeRelationships) {
                        $asset.Relationships = $item.relationships
                    }

                    $results.Add($asset)
                }
            }

            # Cache results if caching is enabled
            if ($UseCache) {
                $null = Set-CompassOneCache -Key $cacheKey -Value $results.ToArray()
            }

            Write-CompassOneLog -Message "Successfully retrieved assets" `
                               -Level Information `
                               -Source "AssetManagement" `
                               -Context @{
                                   CorrelationId = $correlationId
                                   Count = $results.Count
                                   Operation = "GetAsset"
                               }

            return $results.ToArray()
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'not found' { 4001 }      # Asset not found
            'unauthorized' { 1001 }    # Authentication error
            'timeout' { 5001 }        # Operation timeout
            default { 7001 }          # General error
        }

        Write-CompassOneError -ErrorCategory InvalidOperation `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to retrieve assets: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Operation = "GetAsset"
                             } `
                             -ErrorAction Stop
    }
    finally {
        # Clean up resources
        if ($results) {
            $results.Clear()
        }
        [System.GC]::Collect()
    }
}