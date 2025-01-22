#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Core 7.0.0
# Import required type definitions
. "$PSScriptRoot/../Types/Asset.Types.ps1"
. "$PSScriptRoot/../Types/Finding.Types.ps1"
. "$PSScriptRoot/../Types/Incident.Types.ps1"

#region Parameter Conversion Functions

<#
.SYNOPSIS
    Converts and validates input parameters for CompassOne entities.
.DESCRIPTION
    Main function that provides comprehensive parameter conversion and validation 
    for all CompassOne entity types with thread-safe operations and detailed error handling.
#>
function ConvertTo-CompassOneParameter {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet('Asset', 'Finding', 'Incident')]
        [string]$TargetType
    )

    try {
        Write-Verbose "Converting parameter to $TargetType type"
        
        # Handle null values appropriately
        if ($null -eq $Value) {
            Write-Error "Parameter value cannot be null for type $TargetType" -Category InvalidArgument
            return $null
        }

        # Route to appropriate conversion function based on target type
        $result = switch ($TargetType) {
            'Asset' { ConvertTo-AssetParameter -Value $Value }
            'Finding' { ConvertTo-FindingParameter -Value $Value }
            'Incident' { ConvertTo-IncidentParameter -Value $Value }
            default {
                Write-Error "Unsupported target type: $TargetType" -Category InvalidArgument
                return $null
            }
        }

        return $result
    }
    catch {
        Write-Error "Parameter conversion error: $_" -Category InvalidOperation
        return $null
    }
}

<#
.SYNOPSIS
    Converts and validates Asset-specific parameters.
.DESCRIPTION
    Specialized function for converting and validating Asset parameters with comprehensive type checking.
#>
function ConvertTo-AssetParameter {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$PropertyName = ''
    )

    try {
        # Handle string conversion for enum types
        if ($PropertyName -eq 'Class' -and $Value -is [string]) {
            if (-not [Enum]::TryParse([AssetClass], $Value, $true, [ref]$null)) {
                $validValues = [Enum]::GetNames([AssetClass]) -join ', '
                Write-Error "Invalid asset class '$Value'. Valid values are: $validValues" -Category InvalidArgument
                return $null
            }
            return [AssetClass]$Value
        }

        # Handle array types (e.g., Tags)
        if ($Value -is [array]) {
            return $Value | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }

        # Handle date conversions
        if ($PropertyName -in @('FoundOn', 'LastSeenOn', 'CreatedOn', 'UpdatedOn', 'DeletedOn')) {
            if ($Value -is [DateTime]) {
                return $Value.ToUniversalTime()
            }
            if ($Value -is [string] -and [DateTime]::TryParse($Value, [ref]$null)) {
                return [DateTime]::Parse($Value).ToUniversalTime()
            }
            Write-Error "Invalid date format for $PropertyName" -Category InvalidArgument
            return $null
        }

        # Default string conversion with validation
        return $Value.ToString().Trim()
    }
    catch {
        Write-Error "Asset parameter conversion error: $_" -Category InvalidOperation
        return $null
    }
}

<#
.SYNOPSIS
    Converts and validates Finding-specific parameters.
.DESCRIPTION
    Specialized function for converting and validating Finding parameters with comprehensive type checking.
#>
function ConvertTo-FindingParameter {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$PropertyName = ''
    )

    try {
        # Handle string conversion for enum types
        if ($PropertyName -eq 'Class' -and $Value -is [string]) {
            if (-not [Enum]::TryParse([FindingClass], $Value, $true, [ref]$null)) {
                $validValues = [Enum]::GetNames([FindingClass]) -join ', '
                Write-Error "Invalid finding class '$Value'. Valid values are: $validValues" -Category InvalidArgument
                return $null
            }
            return [FindingClass]$Value
        }

        # Handle severity conversion
        if ($PropertyName -eq 'Severity' -and $Value -is [string]) {
            if (-not [Enum]::TryParse([FindingSeverity], $Value, $true, [ref]$null)) {
                $validValues = [Enum]::GetNames([FindingSeverity]) -join ', '
                Write-Error "Invalid finding severity '$Value'. Valid values are: $validValues" -Category InvalidArgument
                return $null
            }
            return [FindingSeverity]$Value
        }

        # Handle score validation
        if ($PropertyName -eq 'Score' -and $Value -is [ValueType]) {
            $score = [float]$Value
            if ($score -lt 0.0 -or $score -gt 10.0) {
                Write-Error "Finding score must be between 0.0 and 10.0" -Category InvalidArgument
                return $null
            }
            return $score
        }

        # Handle array types (e.g., RelatedAssetIds)
        if ($Value -is [array]) {
            return $Value | ForEach-Object { $_.ToString().Trim() } | Where-Object { 
                -not [string]::IsNullOrWhiteSpace($_) -and [Guid]::TryParse($_, [ref]$null)
            }
        }

        # Handle date conversions
        if ($PropertyName -in @('FoundOn', 'CreatedOn', 'UpdatedOn', 'ResolvedOn')) {
            if ($Value -is [DateTime]) {
                return $Value.ToUniversalTime()
            }
            if ($Value -is [string] -and [DateTime]::TryParse($Value, [ref]$null)) {
                return [DateTime]::Parse($Value).ToUniversalTime()
            }
            Write-Error "Invalid date format for $PropertyName" -Category InvalidArgument
            return $null
        }

        # Default string conversion with validation
        return $Value.ToString().Trim()
    }
    catch {
        Write-Error "Finding parameter conversion error: $_" -Category InvalidOperation
        return $null
    }
}

<#
.SYNOPSIS
    Converts and validates Incident-specific parameters.
.DESCRIPTION
    Specialized function for converting and validating Incident parameters with comprehensive type checking.
#>
function ConvertTo-IncidentParameter {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$PropertyName = ''
    )

    try {
        # Handle string conversion for enum types
        if ($PropertyName -eq 'Priority' -and $Value -is [string]) {
            if (-not [Enum]::TryParse([IncidentPriority], $Value, $true, [ref]$null)) {
                $validValues = [Enum]::GetNames([IncidentPriority]) -join ', '
                Write-Error "Invalid incident priority '$Value'. Valid values are: $validValues" -Category InvalidArgument
                return $null
            }
            return [IncidentPriority]$Value
        }

        # Handle status conversion with workflow validation
        if ($PropertyName -eq 'Status' -and $Value -is [string]) {
            if (-not [Enum]::TryParse([IncidentStatus], $Value, $true, [ref]$null)) {
                $validValues = [Enum]::GetNames([IncidentStatus]) -join ', '
                Write-Error "Invalid incident status '$Value'. Valid values are: $validValues" -Category InvalidArgument
                return $null
            }
            return [IncidentStatus]$Value
        }

        # Handle array types (e.g., RelatedFindingIds)
        if ($Value -is [array]) {
            return $Value | ForEach-Object { $_.ToString().Trim() } | Where-Object { 
                -not [string]::IsNullOrWhiteSpace($_) -and [Guid]::TryParse($_, [ref]$null)
            }
        }

        # Handle date conversions
        if ($PropertyName -in @('CreatedOn', 'UpdatedOn', 'ResolvedOn', 'ClosedOn')) {
            if ($Value -is [DateTime]) {
                return $Value.ToUniversalTime()
            }
            if ($Value -is [string] -and [DateTime]::TryParse($Value, [ref]$null)) {
                return [DateTime]::Parse($Value).ToUniversalTime()
            }
            Write-Error "Invalid date format for $PropertyName" -Category InvalidArgument
            return $null
        }

        # Handle URL validation
        if ($PropertyName -eq 'TicketUrl' -and $Value -is [string]) {
            $url = $Value.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($url) -and -not $url.StartsWith('http', [StringComparison]::OrdinalIgnoreCase)) {
                Write-Error "Invalid ticket URL format. URL must start with http or https" -Category InvalidArgument
                return $null
            }
            return $url
        }

        # Default string conversion with validation
        return $Value.ToString().Trim()
    }
    catch {
        Write-Error "Incident parameter conversion error: $_" -Category InvalidOperation
        return $null
    }
}

#endregion

# Export the main conversion function
Export-ModuleMember -Function ConvertTo-CompassOneParameter