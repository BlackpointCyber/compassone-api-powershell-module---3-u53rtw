#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# Version: Microsoft.PowerShell.Core 7.0.0
# Purpose: Core PowerShell functionality for type definitions and advanced type system features

#region Enums

# Define comprehensive finding classification system
enum FindingClass {
    Alert
    Event
    Vulnerability
    Compliance
    Performance
}

# Define finding severity levels with scoring correlation
enum FindingSeverity {
    Critical
    High
    Medium
    Low
    Info
}

# Define finding status workflow system
enum FindingStatus {
    New
    InProgress
    Resolved
    Closed
    FalsePositive
}

#endregion

#region Validation Functions

# Validates if a given value is a valid finding class
function Test-FindingClass {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Finding class value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([FindingClass], $normalizedValue, $true, [ref]$null)) {
            Write-Verbose "Finding class validation successful: $normalizedValue"
            return $true
        }

        $validValues = [Enum]::GetNames([FindingClass]) -join ", "
        Write-Error -Message "Invalid finding class '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Finding class validation error: $_" -Category InvalidOperation
        return $false
    }
}

# Validates if a given value is a valid finding severity
function Test-FindingSeverity {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Finding severity value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([FindingSeverity], $normalizedValue, $true, [ref]$null)) {
            Write-Verbose "Finding severity validation successful: $normalizedValue"
            return $true
        }

        $validValues = [Enum]::GetNames([FindingSeverity]) -join ", "
        Write-Error -Message "Invalid finding severity '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Finding severity validation error: $_" -Category InvalidOperation
        return $false
    }
}

# Validates if a given value is a valid finding status
function Test-FindingStatus {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Finding status value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([FindingStatus], $normalizedValue, $true, [ref]$null)) {
            Write-Verbose "Finding status validation successful: $normalizedValue"
            return $true
        }

        $validValues = [Enum]::GetNames([FindingStatus]) -join ", "
        Write-Error -Message "Invalid finding status '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Finding status validation error: $_" -Category InvalidOperation
        return $false
    }
}

#endregion

#region Classes

# Comprehensive finding type definition with enhanced validation and security features
[Serializable()]
class Finding {
    # Required properties
    [string]$Id
    [string]$Title
    [FindingClass]$Class
    [FindingSeverity]$Severity
    [FindingStatus]$Status
    [float]$Score
    [string]$Description
    [string[]]$RelatedAssetIds
    [string]$Recommendation
    [DateTime]$FoundOn
    
    # Audit properties
    [DateTime]$CreatedOn
    [string]$CreatedBy
    [Nullable[DateTime]]$UpdatedOn
    [string]$UpdatedBy
    [Nullable[DateTime]]$ResolvedOn
    [string]$ResolvedBy

    # Constructor with enhanced validation
    Finding([string]$title, [FindingClass]$class, [FindingSeverity]$severity) {
        if ([string]::IsNullOrWhiteSpace($title)) {
            throw [ArgumentException]::new("Finding title cannot be null or empty")
        }

        if ($title.Length -gt 200) {
            throw [ArgumentException]::new("Finding title exceeds maximum length of 200 characters")
        }

        # Initialize required properties
        $this.Id = [Guid]::NewGuid().ToString()
        $this.Title = $title.Trim()
        $this.Class = $class
        $this.Severity = $severity
        $this.Status = [FindingStatus]::New
        $this.Score = switch ($severity) {
            ([FindingSeverity]::Critical) { 10.0 }
            ([FindingSeverity]::High) { 8.0 }
            ([FindingSeverity]::Medium) { 5.0 }
            ([FindingSeverity]::Low) { 2.0 }
            ([FindingSeverity]::Info) { 0.0 }
        }
        $this.Description = ""
        $this.RelatedAssetIds = @()
        $this.Recommendation = ""
        
        # Initialize timestamps
        $now = [DateTime]::UtcNow
        $this.FoundOn = $now
        $this.CreatedOn = $now
        $this.CreatedBy = $env:USERNAME
        
        # Validate the initialized object
        if (-not $this.Validate()) {
            throw [InvalidOperationException]::new("Finding validation failed during initialization")
        }
    }

    # Enhanced string representation with StringBuilder for performance
    [string] ToString() {
        $sb = [StringBuilder]::new()
        
        $sb.AppendLine("Finding Details:") | Out-Null
        $sb.AppendLine("----------------") | Out-Null
        $sb.AppendLine("ID: $($this.Id)") | Out-Null
        $sb.AppendLine("Title: $($this.Title)") | Out-Null
        $sb.AppendLine("Class: $($this.Class)") | Out-Null
        $sb.AppendLine("Severity: $($this.Severity)") | Out-Null
        $sb.AppendLine("Status: $($this.Status)") | Out-Null
        $sb.AppendLine("Score: $($this.Score)") | Out-Null
        $sb.AppendLine("Found: $($this.FoundOn.ToString('u'))") | Out-Null
        $sb.AppendLine("Created: $($this.CreatedOn.ToString('u')) by $($this.CreatedBy)") | Out-Null
        
        if ($this.RelatedAssetIds.Count -gt 0) {
            $sb.AppendLine("Related Assets: $($this.RelatedAssetIds.Count)") | Out-Null
        }
        
        if ($this.ResolvedOn.HasValue) {
            $sb.AppendLine("Resolved: $($this.ResolvedOn.Value.ToString('u')) by $($this.ResolvedBy)") | Out-Null
        }
        
        return $sb.ToString()
    }

    # Comprehensive validation with enhanced security checks
    [bool] Validate() {
        try {
            # Validate required properties
            if ([string]::IsNullOrWhiteSpace($this.Id)) { return $false }
            if ([string]::IsNullOrWhiteSpace($this.Title)) { return $false }
            if (-not [Enum]::IsDefined(typeof([FindingClass]), $this.Class)) { return $false }
            if (-not [Enum]::IsDefined(typeof([FindingSeverity]), $this.Severity)) { return $false }
            if (-not [Enum]::IsDefined(typeof([FindingStatus]), $this.Status)) { return $false }
            
            # Validate score range
            if ($this.Score -lt 0.0 -or $this.Score -gt 10.0) { return $false }
            
            # Validate dates
            $now = [DateTime]::UtcNow
            if ($this.FoundOn > $now) { return $false }
            if ($this.CreatedOn > $now) { return $false }
            
            # Validate optional dates if present
            if ($this.UpdatedOn.HasValue) {
                if ($this.UpdatedOn.Value < $this.CreatedOn) { return $false }
                if ($this.UpdatedOn.Value > $now) { return $false }
            }
            
            if ($this.ResolvedOn.HasValue) {
                if ($this.ResolvedOn.Value < $this.CreatedOn) { return $false }
                if ($this.ResolvedOn.Value > $now) { return $false }
                if ([string]::IsNullOrWhiteSpace($this.ResolvedBy)) { return $false }
            }
            
            # Validate status transitions
            if ($this.Status -in @([FindingStatus]::Resolved, [FindingStatus]::Closed) -and -not $this.ResolvedOn.HasValue) {
                return $false
            }
            
            # Validate related assets array
            if ($null -eq $this.RelatedAssetIds) { return $false }
            foreach ($assetId in $this.RelatedAssetIds) {
                if ([string]::IsNullOrWhiteSpace($assetId)) { return $false }
                if (-not [Guid]::TryParse($assetId, [ref]$null)) { return $false }
            }

            return $true
        }
        catch {
            Write-Error -Message "Finding validation error: $_" -Category InvalidOperation
            return $false
        }
    }
}

#endregion

# Export type data for enhanced PowerShell integration
Update-TypeData -TypeName Finding -DefaultDisplayPropertySet Id, Title, Class, Severity, Status, Score -Force