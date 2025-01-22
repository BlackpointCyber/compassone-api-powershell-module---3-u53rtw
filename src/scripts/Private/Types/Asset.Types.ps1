#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Core 7.0.0
# Purpose: Core PowerShell functionality for type definitions and advanced type system features

#region Enums

# Define comprehensive asset classification system
enum AssetClass {
    Device
    Container
    Software
    Network
    Unknown
}

# Define asset lifecycle status system
enum AssetStatus {
    Active
    Inactive
    Archived
    Deleted
}

#endregion

#region Validation Functions

# Validates if a given value is a valid asset class
function Test-AssetClass {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Asset class value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([AssetClass], $normalizedValue, $true, [ref]$null)) {
            return $true
        }

        $validValues = [Enum]::GetNames([AssetClass]) -join ", "
        Write-Error -Message "Invalid asset class '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Asset class validation error: $_" -Category InvalidOperation
        return $false
    }
}

# Validates if a given value is a valid asset status
function Test-AssetStatus {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Error -Message "Asset status value cannot be null or empty" -Category InvalidArgument
            return $false
        }

        $normalizedValue = $Value.Trim()
        if ([Enum]::TryParse([AssetStatus], $normalizedValue, $true, [ref]$null)) {
            return $true
        }

        $validValues = [Enum]::GetNames([AssetStatus]) -join ", "
        Write-Error -Message "Invalid asset status '$Value'. Valid values are: $validValues" -Category InvalidArgument
        return $false
    }
    catch {
        Write-Error -Message "Asset status validation error: $_" -Category InvalidOperation
        return $false
    }
}

#endregion

#region Classes

# Comprehensive asset type definition with enhanced validation and PowerShell integration
[Serializable()]
class Asset {
    # Required properties
    [string]$Id
    [string]$Name
    [AssetClass]$Class
    [AssetStatus]$Status
    [string[]]$Tags
    [string]$Description
    [DateTime]$FoundOn
    [DateTime]$LastSeenOn
    
    # Audit properties
    [DateTime]$CreatedOn
    [string]$CreatedBy
    [Nullable[DateTime]]$UpdatedOn
    [string]$UpdatedBy
    [Nullable[DateTime]]$DeletedOn
    [string]$DeletedBy

    # Constructor with enhanced validation
    Asset([string]$name, [AssetClass]$class) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Asset name cannot be null or empty")
        }

        # Initialize required properties
        $this.Id = [Guid]::NewGuid().ToString()
        $this.Name = $name.Trim()
        $this.Class = $class
        $this.Status = [AssetStatus]::Active
        $this.Tags = @()
        $this.Description = ""
        
        # Initialize timestamps
        $now = [DateTime]::UtcNow
        $this.FoundOn = $now
        $this.LastSeenOn = $now
        $this.CreatedOn = $now
        $this.CreatedBy = $env:USERNAME
        
        # Validate the initialized object
        if (-not $this.Validate()) {
            throw [InvalidOperationException]::new("Asset validation failed during initialization")
        }
    }

    # Enhanced string representation
    [string] ToString() {
        $status = $this.Status.ToString()
        $class = $this.Class.ToString()
        $tags = $this.Tags -join ", "
        
        return @"
Asset: $($this.Name)
ID: $($this.Id)
Class: $class
Status: $status
Tags: $tags
Found: $($this.FoundOn.ToString('u'))
Last Seen: $($this.LastSeenOn.ToString('u'))
Created: $($this.CreatedOn.ToString('u')) by $($this.CreatedBy)
"@
    }

    # Comprehensive validation
    [bool] Validate() {
        try {
            # Validate required properties
            if ([string]::IsNullOrWhiteSpace($this.Id)) { return $false }
            if ([string]::IsNullOrWhiteSpace($this.Name)) { return $false }
            if (-not [Enum]::IsDefined(typeof([AssetClass]), $this.Class)) { return $false }
            if (-not [Enum]::IsDefined(typeof([AssetStatus]), $this.Status)) { return $false }
            
            # Validate dates
            $now = [DateTime]::UtcNow
            if ($this.FoundOn > $now) { return $false }
            if ($this.LastSeenOn > $now) { return $false }
            if ($this.LastSeenOn < $this.FoundOn) { return $false }
            if ($this.CreatedOn > $now) { return $false }
            
            # Validate optional dates if present
            if ($this.UpdatedOn.HasValue -and $this.UpdatedOn.Value < $this.CreatedOn) { return $false }
            if ($this.DeletedOn.HasValue -and $this.DeletedOn.Value < $this.CreatedOn) { return $false }
            
            # Validate status transitions
            if ($this.Status -eq [AssetStatus]::Deleted -and -not $this.DeletedOn.HasValue) { return $false }
            if ($this.DeletedOn.HasValue -and $this.Status -ne [AssetStatus]::Deleted) { return $false }
            
            # Validate tags array
            if ($null -eq $this.Tags) { return $false }
            foreach ($tag in $this.Tags) {
                if ([string]::IsNullOrWhiteSpace($tag)) { return $false }
            }

            return $true
        }
        catch {
            Write-Error -Message "Asset validation error: $_" -Category InvalidOperation
            return $false
        }
    }
}

#endregion

# Export type data for enhanced PowerShell integration
Update-TypeData -TypeName Asset -DefaultDisplayPropertySet Id, Name, Class, Status, LastSeenOn -Force