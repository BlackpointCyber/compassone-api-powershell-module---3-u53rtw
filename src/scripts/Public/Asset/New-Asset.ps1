using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Creates a new asset in the CompassOne platform with comprehensive validation and security controls.

.DESCRIPTION
    Creates a new asset with full validation, security checks, and audit logging. Supports pipeline
    input and implements enterprise-grade error handling with proper security controls.

.PARAMETER Name
    The name of the asset. Must be unique and non-empty.

.PARAMETER Class
    The asset classification (Device, Container, Software, Network, Unknown).

.PARAMETER Tags
    Optional array of tags to associate with the asset.

.PARAMETER Description
    Optional description of the asset.

.PARAMETER PassThru
    If specified, returns the created asset object.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs.

.PARAMETER Confirm
    Prompts for confirmation before running the cmdlet.

.OUTPUTS
    PSCompassOne.Asset. Returns the created asset if -PassThru is specified.

.EXAMPLE
    New-Asset -Name "WebServer01" -Class Device -Tags "Production","Web"

.EXAMPLE
    New-Asset -Name "Container01" -Class Container -Description "Development container" -PassThru

.NOTES
    File Name      : New-Asset.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Default')]
[OutputType([PSCompassOne.Asset])]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [AssetClass]$Class,

    [Parameter()]
    [string[]]$Tags,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [switch]$PassThru
)

begin {
    Write-CompassOneLog -Message "Starting asset creation operation" `
                       -Level Information `
                       -Source "AssetManagement" `
                       -Context @{
                           Operation = "Create"
                           Component = "Asset"
                       }

    # Track operation metrics
    $operationStart = [DateTime]::UtcNow
    $processedCount = 0
    $errorCount = 0
}

process {
    try {
        # Generate correlation ID for request tracking
        $correlationId = [Guid]::NewGuid().ToString()

        Write-CompassOneLog -Message "Processing asset creation request" `
                           -Level Verbose `
                           -Source "AssetManagement" `
                           -Context @{
                               CorrelationId = $correlationId
                               Name = $Name
                               Class = $Class
                           }

        # Validate input parameters
        $paramValidation = @{
            Name = @{
                Type = "NonEmptyString"
                Value = $Name
            }
            Class = @{
                Type = "AssetClass"
                Value = $Class.ToString()
            }
        }

        foreach ($param in $paramValidation.GetEnumerator()) {
            $isValid = Test-CompassOneParameter `
                -Value $param.Value.Value `
                -ParameterType $param.Value.Type `
                -ParameterName $param.Key

            if (-not $isValid) {
                throw "Parameter validation failed for $($param.Key)"
            }
        }

        # Create new asset object with validated properties
        $asset = [Asset]::new($Name, $Class)
        
        # Set optional properties
        if ($PSBoundParameters.ContainsKey('Tags')) {
            $asset.Tags = $Tags
        }
        
        if ($PSBoundParameters.ContainsKey('Description')) {
            $asset.Description = $Description
        }

        # Validate complete asset object
        if (-not $asset.Validate()) {
            throw "Asset validation failed"
        }

        # Prepare API request
        $apiEndpoint = "/assets"
        $requestBody = @{
            name = $asset.Name
            class = $asset.Class.ToString()
            status = $asset.Status.ToString()
            tags = $asset.Tags
            description = $asset.Description
        }

        # Execute creation with ShouldProcess
        if ($PSCmdlet.ShouldProcess($Name, "Create new asset")) {
            # Make API request with retry logic
            $response = Invoke-CompassOneApi `
                -EndpointPath $apiEndpoint `
                -Method "POST" `
                -Body $requestBody

            if ($response) {
                # Update asset with response data
                $asset.Id = $response.id
                $asset.CreatedOn = [DateTime]::Parse($response.createdOn)
                $asset.CreatedBy = $response.createdBy

                Write-CompassOneLog -Message "Asset created successfully" `
                                   -Level Information `
                                   -Source "AssetManagement" `
                                   -Context @{
                                       CorrelationId = $correlationId
                                       AssetId = $asset.Id
                                       Name = $asset.Name
                                       Class = $asset.Class
                                   }

                # Return asset if PassThru specified
                if ($PassThru) {
                    $asset
                }

                $processedCount++
            }
        }
    }
    catch {
        $errorCount++
        
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'validation' { 3001 }  # Validation error
            'duplicate' { 3002 }   # Duplicate asset
            'api' { 2001 }        # API error
            default { 7001 }       # General error
        }

        Write-CompassOneError -ErrorCategory InvalidOperation `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Asset creation failed: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Name = $Name
                                 Class = $Class
                             } `
                             -ErrorAction Stop
    }
}

end {
    # Log operation summary
    $duration = [DateTime]::UtcNow - $operationStart
    
    Write-CompassOneLog -Message "Asset creation operation completed" `
                       -Level Information `
                       -Source "AssetManagement" `
                       -Context @{
                           Operation = "Create"
                           Duration = $duration.TotalSeconds
                           ProcessedCount = $processedCount
                           ErrorCount = $errorCount
                       }
}