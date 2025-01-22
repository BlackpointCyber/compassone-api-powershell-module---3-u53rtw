using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Removes an asset from the CompassOne platform.

.DESCRIPTION
    Removes one or more assets from the CompassOne platform with comprehensive validation,
    security controls, and audit logging. Supports both single asset deletion and bulk
    operations through pipeline input with configurable batch processing.

.PARAMETER Id
    The unique identifier of the asset to remove.

.PARAMETER InputObject
    Asset object to remove, supporting pipeline input.

.PARAMETER Force
    Suppresses confirmation prompts.

.PARAMETER PassThru
    Returns the removed asset object.

.PARAMETER BatchSize
    Number of assets to process in each batch for bulk operations. Default is 10.

.PARAMETER WaitForCompletion
    Waits for batch operations to complete before returning.

.OUTPUTS
    None by default
    PSCompassOne.Asset when -PassThru is specified
    PSCompassOne.BatchOperationResult for batch operations

.NOTES
    File Name      : Remove-Asset.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
[OutputType([void], [PSCompassOne.Asset], [PSCompassOne.BatchOperationResult])]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ById', Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
    [ValidateNotNull()]
    [Asset]$InputObject,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$BatchSize = 10,

    [Parameter()]
    [switch]$WaitForCompletion
)

begin {
    # Generate correlation ID for operation tracking
    $correlationId = [guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting asset removal operation" `
                       -Level Information `
                       -Source "AssetManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "Remove"
                           BatchSize = $BatchSize
                       }

    # Initialize batch processing
    $batchQueue = [List[Asset]]::new()
    $results = [List[object]]::new()
}

process {
    try {
        # Determine asset to remove
        $assetToRemove = if ($PSCmdlet.ParameterSetName -eq 'ById') {
            # Retrieve asset by ID
            $apiParams = @{
                EndpointPath = "/assets/$Id"
                Method = 'GET'
                CorrelationId = $correlationId
            }
            
            $asset = Invoke-CompassOneApi @apiParams
            if (-not $asset) {
                Write-CompassOneError -ErrorCategory ResourceNotFound `
                                    -ErrorCode 4001 `
                                    -ErrorDetails @{
                                        Message = "Asset not found"
                                        AssetId = $Id
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
            }
            $asset
        }
        else {
            $InputObject
        }

        # Validate asset state
        if (-not $assetToRemove.Validate()) {
            Write-CompassOneError -ErrorCategory ValidationError `
                                -ErrorCode 3001 `
                                -ErrorDetails @{
                                    Message = "Invalid asset state"
                                    AssetId = $assetToRemove.Id
                                    CorrelationId = $correlationId
                                } `
                                -ErrorAction Stop
        }

        # Add to batch queue
        $batchQueue.Add($assetToRemove)

        # Process batch if size threshold reached
        if ($batchQueue.Count -ge $BatchSize) {
            $null = ProcessAssetBatch -Assets $batchQueue `
                                    -Force:$Force `
                                    -PassThru:$PassThru `
                                    -WaitForCompletion:$WaitForCompletion `
                                    -CorrelationId $correlationId
            $batchQueue.Clear()
        }
    }
    catch {
        Write-CompassOneError -ErrorCategory InvalidOperation `
                            -ErrorCode 7001 `
                            -ErrorDetails @{
                                Message = "Asset removal failed"
                                Error = $_.Exception.Message
                                CorrelationId = $correlationId
                            } `
                            -ErrorAction Stop
    }
}

end {
    try {
        # Process any remaining assets in the batch queue
        if ($batchQueue.Count -gt 0) {
            $null = ProcessAssetBatch -Assets $batchQueue `
                                    -Force:$Force `
                                    -PassThru:$PassThru `
                                    -WaitForCompletion:$WaitForCompletion `
                                    -CorrelationId $correlationId
        }

        Write-CompassOneLog -Message "Asset removal operation completed" `
                           -Level Information `
                           -Source "AssetManagement" `
                           -Context @{
                               CorrelationId = $correlationId
                               Operation = "Remove"
                               AssetsProcessed = $results.Count
                           }
    }
    catch {
        Write-CompassOneError -ErrorCategory InvalidOperation `
                            -ErrorCode 7002 `
                            -ErrorDetails @{
                                Message = "Failed to complete asset removal operation"
                                Error = $_.Exception.Message
                                CorrelationId = $correlationId
                            } `
                            -ErrorAction Stop
    }
    finally {
        # Cleanup
        if ($batchQueue) {
            $batchQueue.Clear()
        }
        [System.GC]::Collect()
    }
}

#region Helper Functions

function ProcessAssetBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [List[Asset]]$Assets,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$WaitForCompletion,

        [Parameter(Mandatory = $true)]
        [string]$CorrelationId
    )

    foreach ($asset in $Assets) {
        # Confirm removal unless -Force is specified
        $confirmMessage = "Are you sure you want to remove asset '$($asset.Name)' ($($asset.Id))?"
        if ($Force -or $PSCmdlet.ShouldProcess($confirmMessage, "Remove Asset")) {
            try {
                # Log removal attempt
                Write-CompassOneLog -Message "Removing asset" `
                                   -Level Information `
                                   -Source "AssetManagement" `
                                   -Context @{
                                       CorrelationId = $CorrelationId
                                       Operation = "Remove"
                                       AssetId = $asset.Id
                                       AssetName = $asset.Name
                                   }

                # Execute API call
                $apiParams = @{
                    EndpointPath = "/assets/$($asset.Id)"
                    Method = 'DELETE'
                    CorrelationId = $CorrelationId
                }

                $response = Invoke-CompassOneApi @apiParams

                if ($PassThru) {
                    $results.Add($asset)
                }

                # Log successful removal
                Write-CompassOneLog -Message "Asset removed successfully" `
                                   -Level Information `
                                   -Source "AssetManagement" `
                                   -Context @{
                                       CorrelationId = $CorrelationId
                                       Operation = "Remove"
                                       AssetId = $asset.Id
                                       AssetName = $asset.Name
                                   }
            }
            catch {
                Write-CompassOneError -ErrorCategory InvalidOperation `
                                    -ErrorCode 7003 `
                                    -ErrorDetails @{
                                        Message = "Failed to remove asset"
                                        AssetId = $asset.Id
                                        Error = $_.Exception.Message
                                        CorrelationId = $CorrelationId
                                    } `
                                    -ErrorAction Continue
            }
        }
    }

    if ($PassThru) {
        return $results
    }
}

#endregion