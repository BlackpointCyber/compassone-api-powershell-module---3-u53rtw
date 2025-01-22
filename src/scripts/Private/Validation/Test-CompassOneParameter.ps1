#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Core 7.0.0

# Import type validation functions
. "$PSScriptRoot/../Types/Asset.Types.ps1"
. "$PSScriptRoot/../Types/Finding.Types.ps1"
. "$PSScriptRoot/../Types/Incident.Types.ps1"

#region Parameter Validation Functions

<#
.SYNOPSIS
    Validates input parameters against CompassOne type system rules with comprehensive error reporting and input sanitization.
.DESCRIPTION
    Provides robust parameter validation with type checking, business rule validation, and detailed error reporting.
    Implements input sanitization to prevent injection attacks and ensures data integrity.
#>
function Test-CompassOneParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterType,

        [Parameter(Position = 2)]
        [string]$ParameterName = "Parameter"
    )

    try {
        Write-Verbose "Validating parameter '$ParameterName' of type '$ParameterType'"

        # Handle null values based on parameter type requirements
        if ($null -eq $Value) {
            $message = "Parameter '$ParameterName' cannot be null"
            Write-Error -Message $message -Category InvalidArgument
            return $false
        }

        # Sanitize string input to prevent injection
        if ($Value -is [string]) {
            $Value = $Value.Trim()
            # Remove potentially dangerous characters
            $Value = [System.Web.HttpUtility]::HtmlEncode($Value)
        }

        # Validate based on parameter type
        switch ($ParameterType) {
            # Asset validations
            'AssetClass' {
                return Test-AssetClass -Value $Value
            }
            'AssetStatus' {
                return Test-AssetStatus -Value $Value
            }

            # Finding validations
            'FindingClass' {
                return Test-FindingClass -Value $Value
            }
            'FindingSeverity' {
                return Test-FindingSeverity -Value $Value
            }
            'FindingStatus' {
                return Test-FindingStatus -Value $Value
            }

            # Incident validations
            'IncidentPriority' {
                return Test-IncidentPriority -Value $Value
            }
            'IncidentStatus' {
                return Test-IncidentStatus -Value $Value
            }

            # Common type validations
            'Guid' {
                $guid = [Guid]::Empty
                if (-not [Guid]::TryParse($Value, [ref]$guid)) {
                    Write-Error -Message "Invalid GUID format for parameter '$ParameterName'" -Category InvalidArgument
                    return $false
                }
                return $true
            }
            'DateTime' {
                $date = [DateTime]::MinValue
                if (-not [DateTime]::TryParse($Value, [ref]$date)) {
                    Write-Error -Message "Invalid date format for parameter '$ParameterName'" -Category InvalidArgument
                    return $false
                }
                return $true
            }
            'Uri' {
                $uri = [Uri]::Empty
                if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
                    Write-Error -Message "Invalid URI format for parameter '$ParameterName'" -Category InvalidArgument
                    return $false
                }
                return $true
            }
            'Email' {
                if (-not ($Value -match '^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')) {
                    Write-Error -Message "Invalid email format for parameter '$ParameterName'" -Category InvalidArgument
                    return $false
                }
                return $true
            }
            'NonEmptyString' {
                if ([string]::IsNullOrWhiteSpace($Value)) {
                    Write-Error -Message "Parameter '$ParameterName' cannot be empty or whitespace" -Category InvalidArgument
                    return $false
                }
                return $true
            }
            default {
                Write-Error -Message "Unsupported parameter type '$ParameterType'" -Category InvalidArgument
                return $false
            }
        }
    }
    catch {
        Write-Error -Message "Parameter validation error for '$ParameterName': $_" -Category InvalidOperation
        return $false
    }
}

<#
.SYNOPSIS
    Validates a complete set of parameters for a specific CompassOne operation with dependency checking.
.DESCRIPTION
    Provides comprehensive parameter set validation including required parameter checks,
    dependency validation, and custom validation rules application.
#>
function Test-CompassOneParameterSet {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationType,

        [Parameter(Position = 2)]
        [hashtable]$ValidationRules = @{}
    )

    try {
        Write-Verbose "Validating parameter set for operation '$OperationType'"

        # Define required parameters for each operation type
        $requiredParams = @{
            'NewAsset' = @{
                'Name' = 'NonEmptyString'
                'AssetClass' = 'AssetClass'
            }
            'NewFinding' = @{
                'Title' = 'NonEmptyString'
                'FindingClass' = 'FindingClass'
                'Severity' = 'FindingSeverity'
            }
            'NewIncident' = @{
                'Title' = 'NonEmptyString'
                'Priority' = 'IncidentPriority'
            }
            'UpdateAsset' = @{
                'Id' = 'Guid'
            }
            'UpdateFinding' = @{
                'Id' = 'Guid'
            }
            'UpdateIncident' = @{
                'Id' = 'Guid'
            }
        }

        # Validate operation type
        if (-not $requiredParams.ContainsKey($OperationType)) {
            Write-Error -Message "Unsupported operation type '$OperationType'" -Category InvalidArgument
            return $false
        }

        # Check required parameters
        foreach ($param in $requiredParams[$OperationType].GetEnumerator()) {
            if (-not $Parameters.ContainsKey($param.Key)) {
                Write-Error -Message "Missing required parameter '$($param.Key)' for operation '$OperationType'" -Category InvalidArgument
                return $false
            }

            if (-not (Test-CompassOneParameter -Value $Parameters[$param.Key] -ParameterType $param.Value -ParameterName $param.Key)) {
                return $false
            }
        }

        # Apply custom validation rules if provided
        foreach ($rule in $ValidationRules.GetEnumerator()) {
            if ($Parameters.ContainsKey($rule.Key)) {
                $validationScript = [ScriptBlock]::Create($rule.Value)
                if (-not (& $validationScript $Parameters[$rule.Key])) {
                    Write-Error -Message "Custom validation failed for parameter '$($rule.Key)'" -Category InvalidArgument
                    return $false
                }
            }
        }

        # Validate parameter dependencies
        switch ($OperationType) {
            'UpdateAsset' {
                if ($Parameters.ContainsKey('Status') -and $Parameters['Status'] -eq 'Deleted' -and -not $Parameters.ContainsKey('DeletedBy')) {
                    Write-Error -Message "DeletedBy is required when Status is set to Deleted" -Category InvalidArgument
                    return $false
                }
            }
            'UpdateFinding' {
                if ($Parameters.ContainsKey('Status') -and $Parameters['Status'] -in @('Resolved', 'Closed') -and -not $Parameters.ContainsKey('Resolution')) {
                    Write-Error -Message "Resolution is required when Status is set to Resolved or Closed" -Category InvalidArgument
                    return $false
                }
            }
            'UpdateIncident' {
                if ($Parameters.ContainsKey('Status') -and $Parameters['Status'] -eq 'Assigned' -and -not $Parameters.ContainsKey('AssignedTo')) {
                    Write-Error -Message "AssignedTo is required when Status is set to Assigned" -Category InvalidArgument
                    return $false
                }
            }
        }

        Write-Verbose "Parameter set validation successful for operation '$OperationType'"
        return $true
    }
    catch {
        Write-Error -Message "Parameter set validation error: $_" -Category InvalidOperation
        return $false
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Test-CompassOneParameter',
    'Test-CompassOneParameterSet'
)