using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Security

# Import required type definitions and validation functions
. "$PSScriptRoot/../../Private/Types/Finding.Types.ps1"
. "$PSScriptRoot/../../Private/Validation/Test-CompassOneParameter.ps1"
. "$PSScriptRoot/../../Private/Api/Invoke-CompassOneApi.ps1"

<#
.SYNOPSIS
    Creates a new security finding in the CompassOne platform.

.DESCRIPTION
    Creates a new security finding with comprehensive validation, secure API communication,
    and full audit trail support. Implements finding tracking with validation, classification,
    and security posture assessment capabilities.

.PARAMETER Title
    The title of the finding. Must be descriptive and unique.

.PARAMETER Class
    The finding classification (Alert, Event, Vulnerability, Compliance, Performance).

.PARAMETER Severity
    The severity level of the finding (Critical, High, Medium, Low, Info).

.PARAMETER Score
    Optional. The numeric score (0.0-10.0) representing the finding's severity.
    If not specified, automatically calculated based on severity.

.PARAMETER Description
    Optional. Detailed description of the finding.

.PARAMETER RelatedAssetIds
    Optional. Array of asset IDs related to this finding.

.PARAMETER Recommendation
    Optional. Recommended remediation steps.

.PARAMETER PassThru
    Optional. Returns the created finding object.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs.

.PARAMETER Confirm
    Prompts for confirmation before running the cmdlet.

.OUTPUTS
    PSCompassOne.Finding. If -PassThru is specified.

.EXAMPLE
    New-Finding -Title "Critical SQL Injection Vulnerability" -Class Vulnerability -Severity Critical

.NOTES
    File Name      : New-Finding.ps1
    Author        : Blackpoint
    Requires      : PowerShell 7.0+
    Version       : 1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='Default')]
[OutputType([PSCompassOne.Finding])]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [FindingClass]$Class,

    [Parameter(Mandatory=$true, Position=2)]
    [ValidateNotNullOrEmpty()]
    [FindingSeverity]$Severity,

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
    [switch]$PassThru
)

begin {
    # Generate correlation ID for request tracking
    $correlationId = [Guid]::NewGuid().ToString()

    Write-CompassOneLog -Message "Starting finding creation" `
                       -Level Information `
                       -Source "FindingManagement" `
                       -Context @{
                           CorrelationId = $correlationId
                           Operation = "NewFinding"
                       }
}

process {
    try {
        # Validate all required parameters
        $paramValidation = @{
            Title = @{ Value = $Title; Type = "NonEmptyString" }
            Class = @{ Value = $Class; Type = "FindingClass" }
            Severity = @{ Value = $Severity; Type = "FindingSeverity" }
        }

        foreach ($param in $paramValidation.GetEnumerator()) {
            if (-not (Test-CompassOneParameter -Value $param.Value.Value `
                                             -ParameterType $param.Value.Type `
                                             -ParameterName $param.Key)) {
                throw "Parameter validation failed for $($param.Key)"
            }
        }

        # Validate related asset IDs if provided
        if ($RelatedAssetIds) {
            foreach ($assetId in $RelatedAssetIds) {
                if (-not (Test-CompassOneParameter -Value $assetId `
                                                 -ParameterType "Guid" `
                                                 -ParameterName "RelatedAssetId")) {
                    throw "Invalid asset ID format: $assetId"
                }
            }
        }

        # Create finding object with validated parameters
        $finding = [Finding]::new($Title, $Class, $Severity)
        
        # Set optional properties
        if ($PSBoundParameters.ContainsKey('Score')) {
            $finding.Score = $Score
        }
        if ($PSBoundParameters.ContainsKey('Description')) {
            $finding.Description = $Description
        }
        if ($PSBoundParameters.ContainsKey('RelatedAssetIds')) {
            $finding.RelatedAssetIds = $RelatedAssetIds
        }
        if ($PSBoundParameters.ContainsKey('Recommendation')) {
            $finding.Recommendation = $Recommendation
        }

        # Validate complete finding object
        if (-not $finding.Validate()) {
            throw "Finding object validation failed"
        }

        # Prepare API request
        $apiParams = @{
            EndpointPath = "/findings"
            Method = "POST"
            Body = $finding
            UseCache = $false
            CorrelationId = $correlationId
        }

        if ($PSCmdlet.ShouldProcess("Finding: $Title", "Create")) {
            # Create finding via API
            $response = Invoke-CompassOneApi @apiParams

            if (-not $response) {
                throw "Failed to create finding"
            }

            Write-CompassOneLog -Message "Finding created successfully" `
                               -Level Information `
                               -Source "FindingManagement" `
                               -Context @{
                                   CorrelationId = $correlationId
                                   FindingId = $response.Id
                                   Title = $Title
                               }

            # Return created finding if PassThru specified
            if ($PassThru) {
                return $response
            }
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'validation' { 3001 }  # Validation errors
            'api' { 2001 }        # API communication errors
            'asset' { 4001 }      # Asset reference errors
            default { 7001 }      # General errors
        }

        Write-CompassOneError -ErrorCategory "InvalidOperation" `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to create finding: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Title = $Title
                             } `
                             -ErrorAction Stop
        throw
    }
    finally {
        # Clean up sensitive data
        if ($finding) {
            $finding = $null
        }
        [System.GC]::Collect()
    }
}