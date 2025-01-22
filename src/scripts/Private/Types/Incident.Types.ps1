#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# Version: Microsoft.PowerShell.Core 7.0.0
# Purpose: Core PowerShell functionality for type definitions and enum support

#region Enums

# Define incident priority levels with validation support
enum IncidentPriority {
    P1  # Critical - Immediate response required
    P2  # High - Response required within 2 hours
    P3  # Medium - Response required within 8 hours
    P4  # Low - Response required within 24 hours
    P5  # Planning - Response required within 5 days
}

# Define incident status values with workflow validation
enum IncidentStatus {
    New        # Initial state
    Assigned   # Assigned to team/individual
    InProgress # Active investigation/remediation
    OnHold     # Temporarily suspended
    Resolved   # Resolution implemented
    Closed     # Verified and completed
}

#endregion

#region Validation Functions

# Validates if a given value is a valid incident priority with enhanced validation rules
function Test-IncidentPriority {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Incident priority value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([IncidentPriority], $normalizedValue, $true, [ref]$null)) {
            Write-Verbose "Incident priority validation successful: $normalizedValue"
            return $true
        }

        $validValues = [Enum]::GetNames([IncidentPriority]) -join ", "
        Write-Error -Message "Invalid incident priority '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Incident priority validation error: $_" -Category InvalidOperation
        return $false
    }
}

# Validates if a given value is a valid incident status with workflow rules
function Test-IncidentStatus {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value,
        
        [Parameter(Position = 1)]
        [IncidentStatus]$CurrentStatus = [IncidentStatus]::New
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Incident status value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if (-not [Enum]::TryParse([IncidentStatus], $normalizedValue, $true, [ref]$null)) {
            $validValues = [Enum]::GetNames([IncidentStatus]) -join ", "
            Write-Error -Message "Invalid incident status '$Value'. Valid values are: $validValues" -Category InvalidArgument
            return $false
        }

        # Validate workflow transitions
        $newStatus = [IncidentStatus]$normalizedValue
        $validTransitions = switch ($CurrentStatus) {
            ([IncidentStatus]::New) { @([IncidentStatus]::Assigned, [IncidentStatus]::InProgress) }
            ([IncidentStatus]::Assigned) { @([IncidentStatus]::InProgress, [IncidentStatus]::OnHold) }
            ([IncidentStatus]::InProgress) { @([IncidentStatus]::OnHold, [IncidentStatus]::Resolved) }
            ([IncidentStatus]::OnHold) { @([IncidentStatus]::InProgress) }
            ([IncidentStatus]::Resolved) { @([IncidentStatus]::Closed, [IncidentStatus]::InProgress) }
            ([IncidentStatus]::Closed) { @() }
            default { @() }
        }

        if ($newStatus -notin $validTransitions -and $newStatus -ne $CurrentStatus) {
            Write-Error -Message "Invalid status transition from '$CurrentStatus' to '$newStatus'" -Category InvalidOperation
            return $false
        }

        Write-Verbose "Incident status validation successful: $normalizedValue"
        return $true
    }
    catch {
        Write-Error -Message "Incident status validation error: $_" -Category InvalidOperation
        return $false
    }
}

#endregion

#region Classes

# Represents a CompassOne security incident with enhanced workflow validation and relationship management
[Serializable()]
class Incident {
    # Required properties
    [string]$Id
    [string]$Title
    [IncidentPriority]$Priority
    [IncidentStatus]$Status
    [string]$Description
    [string[]]$RelatedFindingIds
    [string]$AssignedTo
    [string]$TicketId
    [string]$TicketUrl

    # Audit properties
    [DateTime]$CreatedOn
    [string]$CreatedBy
    [Nullable[DateTime]]$UpdatedOn
    [string]$UpdatedBy
    [Nullable[DateTime]]$ResolvedOn
    [string]$ResolvedBy
    [Nullable[DateTime]]$ClosedOn
    [string]$ClosedBy

    # Constructor with enhanced validation
    Incident([string]$title, [IncidentPriority]$priority, [string[]]$relatedFindingIds) {
        if ([string]::IsNullOrWhiteSpace($title)) {
            throw [ArgumentException]::new("Incident title cannot be null or empty")
        }

        if ($title.Length -gt 200) {
            throw [ArgumentException]::new("Incident title exceeds maximum length of 200 characters")
        }

        # Initialize required properties
        $this.Id = [Guid]::NewGuid().ToString()
        $this.Title = $title.Trim()
        $this.Priority = $priority
        $this.Status = [IncidentStatus]::New
        $this.Description = ""
        $this.RelatedFindingIds = $relatedFindingIds ?? @()
        $this.AssignedTo = ""
        $this.TicketId = ""
        $this.TicketUrl = ""

        # Initialize timestamps
        $now = [DateTime]::UtcNow
        $this.CreatedOn = $now
        $this.CreatedBy = $env:USERNAME

        # Validate the initialized object
        if (-not $this.Validate()) {
            throw [InvalidOperationException]::new("Incident validation failed during initialization")
        }
    }

    # Returns a detailed string representation of the incident
    [string] ToString() {
        $sb = [StringBuilder]::new()
        
        $sb.AppendLine("Incident Details:") | Out-Null
        $sb.AppendLine("----------------") | Out-Null
        $sb.AppendLine("ID: $($this.Id)") | Out-Null
        $sb.AppendLine("Title: $($this.Title)") | Out-Null
        $sb.AppendLine("Priority: $($this.Priority)") | Out-Null
        $sb.AppendLine("Status: $($this.Status)") | Out-Null
        
        if (-not [string]::IsNullOrWhiteSpace($this.AssignedTo)) {
            $sb.AppendLine("Assigned To: $($this.AssignedTo)") | Out-Null
        }
        
        if ($this.RelatedFindingIds.Count -gt 0) {
            $sb.AppendLine("Related Findings: $($this.RelatedFindingIds.Count)") | Out-Null
        }
        
        $sb.AppendLine("Created: $($this.CreatedOn.ToString('u')) by $($this.CreatedBy)") | Out-Null
        
        if ($this.ResolvedOn.HasValue) {
            $sb.AppendLine("Resolved: $($this.ResolvedOn.Value.ToString('u')) by $($this.ResolvedBy)") | Out-Null
        }
        
        if ($this.ClosedOn.HasValue) {
            $sb.AppendLine("Closed: $($this.ClosedOn.Value.ToString('u')) by $($this.ClosedBy)") | Out-Null
        }
        
        return $sb.ToString()
    }

    # Performs comprehensive validation of the incident
    [bool] Validate() {
        try {
            # Validate required properties
            if ([string]::IsNullOrWhiteSpace($this.Id)) { return $false }
            if ([string]::IsNullOrWhiteSpace($this.Title)) { return $false }
            if (-not [Enum]::IsDefined(typeof([IncidentPriority]), $this.Priority)) { return $false }
            if (-not [Enum]::IsDefined(typeof([IncidentStatus]), $this.Status)) { return $false }
            
            # Validate dates
            $now = [DateTime]::UtcNow
            if ($this.CreatedOn > $now) { return $false }
            
            # Validate optional dates if present
            if ($this.UpdatedOn.HasValue) {
                if ($this.UpdatedOn.Value < $this.CreatedOn) { return $false }
                if ($this.UpdatedOn.Value > $now) { return $false }
                if ([string]::IsNullOrWhiteSpace($this.UpdatedBy)) { return $false }
            }
            
            if ($this.ResolvedOn.HasValue) {
                if ($this.ResolvedOn.Value < $this.CreatedOn) { return $false }
                if ($this.ResolvedOn.Value > $now) { return $false }
                if ([string]::IsNullOrWhiteSpace($this.ResolvedBy)) { return $false }
            }
            
            if ($this.ClosedOn.HasValue) {
                if ($this.ClosedOn.Value < $this.CreatedOn) { return $false }
                if ($this.ClosedOn.Value > $now) { return $false }
                if ([string]::IsNullOrWhiteSpace($this.ClosedBy)) { return $false }
                if (-not $this.ResolvedOn.HasValue) { return $false }
                if ($this.ClosedOn.Value < $this.ResolvedOn.Value) { return $false }
            }
            
            # Validate status transitions
            if ($this.Status -eq [IncidentStatus]::Resolved -and -not $this.ResolvedOn.HasValue) { return $false }
            if ($this.Status -eq [IncidentStatus]::Closed -and -not $this.ClosedOn.HasValue) { return $false }
            
            # Validate related findings array
            if ($null -eq $this.RelatedFindingIds) { return $false }
            foreach ($findingId in $this.RelatedFindingIds) {
                if ([string]::IsNullOrWhiteSpace($findingId)) { return $false }
                if (-not [Guid]::TryParse($findingId, [ref]$null)) { return $false }
            }

            return $true
        }
        catch {
            Write-Error -Message "Incident validation error: $_" -Category InvalidOperation
            return $false
        }
    }
}

#endregion

# Export type data for enhanced PowerShell integration
Update-TypeData -TypeName Incident -DefaultDisplayPropertySet Id, Title, Priority, Status, AssignedTo -Force