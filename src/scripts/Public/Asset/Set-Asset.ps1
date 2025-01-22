using namespace System
using namespace System.Collections.Generic

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Updates an existing asset in the CompassOne platform.

.DESCRIPTION
    Updates an existing asset's properties in the CompassOne platform with comprehensive validation,
    error handling, and audit logging. Implements secure update operations with proper access control
    and data integrity checks.

.PARAMETER Id
    The unique identifier of the asset to update.

.PARAMETER Name
    The new name for the asset.

.PARAMETER Class
    The new asset classification (Device, Container, Software, Network, Unknown).

.PARAMETER Status
    The new asset status (Active, Inactive, Archived, Deleted).

.PARAMETER Tags
    Array of tags to associate with the asset.

.PARAMETER Description
    Detailed description of the asset.

.PARAMETER PassThru
    Returns the updated asset object.

.PARAMETER Force
    Suppresses confirmation prompts.

.OUTPUTS
    PSCompassOne.Asset
    Returns the updated asset object if -PassThru is specified.

.NOTES
    File Name      : Set-Asset.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
[OutputType([PSCompassOne.Asset])]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [AssetClass]$Class,

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [AssetStatus]$Status,

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string[]]$Tags,

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$Description,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [switch]$Force
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [Guid]::NewGuid().ToString()

    Write-Verbose "Starting asset update operation with correlation ID: $correlationId"
}

process {
    try {
        # Validate required Id parameter
        if (-not (Test-CompassOneParameter -Value $Id -ParameterType 'Guid' -ParameterName 'Id')) {
            throw "Invalid asset ID format"
        }

        # Build update payload with only specified parameters
        $updateParams = @{}
        $parameterMap = @{
            'Name' = @{ Type = 'NonEmptyString' }
            'Class' = @{ Type = 'AssetClass' }
            'Status' = @{ Type = 'AssetStatus' }
            'Description' = @{ Type = 'string' }
        }

        foreach ($param in $parameterMap.Keys) {
            if ($PSBoundParameters.ContainsKey($param)) {
                # Validate parameter value
                if (-not (Test-CompassOneParameter -Value $PSBoundParameters[$param] `
                        -ParameterType $parameterMap[$param].Type `
                        -ParameterName $param)) {
                    throw "Invalid $param parameter"
                }
                $updateParams[$param] = $PSBoundParameters[$param]
            }
        }

        # Validate tags if specified
        if ($PSBoundParameters.ContainsKey('Tags')) {
            foreach ($tag in $Tags) {
                if (-not (Test-CompassOneParameter -Value $tag -ParameterType 'NonEmptyString' -ParameterName 'Tag')) {
                    throw "Invalid tag value: $tag"
                }
            }
            $updateParams['Tags'] = $Tags
        }

        # Add audit information
        $updateParams['UpdatedOn'] = [DateTime]::UtcNow
        $updateParams['UpdatedBy'] = $env:USERNAME

        # Special handling for Deleted status
        if ($Status -eq [AssetStatus]::Deleted) {
            $updateParams['DeletedOn'] = [DateTime]::UtcNow
            $updateParams['DeletedBy'] = $env:USERNAME
        }

        # Construct target identification for ShouldProcess
        $target = "Asset ID: $Id"
        if ($Name) {
            $target += " (Name: $Name)"
        }

        # Confirm update operation unless -Force is specified
        if ($Force -or $PSCmdlet.ShouldProcess($target, "Update asset")) {
            Write-Verbose "Updating asset with parameters: $($updateParams | ConvertTo-Json)"

            # Call API with retry and error handling
            $apiPath = "/assets/$Id"
            $response = Invoke-CompassOneApi -EndpointPath $apiPath `
                                           -Method 'PUT' `
                                           -Body $updateParams `
                                           -CorrelationId $correlationId

            # Return updated asset if -PassThru specified
            if ($PassThru) {
                # Convert API response to Asset object
                $asset = [Asset]::new($response.Name, $response.Class)
                foreach ($prop in $response.PSObject.Properties) {
                    if ($asset.PSObject.Properties[$prop.Name]) {
                        $asset.$($prop.Name) = $prop.Value
                    }
                }

                # Validate returned asset
                if (-not $asset.Validate()) {
                    throw "Updated asset validation failed"
                }

                return $asset
            }

            Write-Verbose "Asset updated successfully"
        }
    }
    catch {
        # Determine error category and code
        $errorCode = switch -Regex ($_.Exception.Message) {
            'Invalid .* parameter' { 3001 } # Validation error
            'API request failed' { 2001 }   # Connection error
            'Rate limit' { 8001 }           # Rate limit error
            default { 7001 }                # General error
        }

        Write-CompassOneError -ErrorCategory 'InvalidOperation' `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to update asset: $($_.Exception.Message)"
                                 AssetId = $Id
                                 CorrelationId = $correlationId
                             } `
                             -ErrorAction 'Stop'
    }
}

end {
    # Clean up sensitive data
    if ($updateParams) {
        $updateParams.Clear()
    }
    [System.GC]::Collect()
}