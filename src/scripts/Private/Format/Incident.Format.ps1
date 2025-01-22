#Requires -Version 7.0
using namespace System.Management.Automation
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Utility 7.0.0
# Purpose: Defines formatting rules and display configurations for Incident objects

# Default table view configuration
$script:DefaultIncidentTableView = [PSCustomObject]@{
    ViewName = 'TableView'
    Properties = @('Id', 'Title', 'Priority', 'Status', 'CreatedOn', 'LastUpdatedOn')
    ColorCoding = $true
    DateFormat = 'yyyy-MM-dd HH:mm:ss'
}

# Default list view configuration
$script:DefaultIncidentListView = [PSCustomObject]@{
    ViewName = 'ListView'
    Properties = @('Id', 'Title', 'Priority', 'Status', 'CreatedOn', 'LastUpdatedOn', 'RelatedFindings', 'Description')
    ColorCoding = $true
    DateFormat = 'yyyy-MM-dd HH:mm:ss'
    GroupBy = 'Priority'
}

<#
.SYNOPSIS
    Formats an incident object or collection for table view output.
#>
function Format-IncidentTable {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter()]
        [switch]$NoColor,

        [Parameter()]
        [string]$DateFormat = $script:DefaultIncidentTableView.DateFormat,

        [Parameter()]
        [string[]]$Property = $script:DefaultIncidentTableView.Properties
    )

    begin {
        $results = [List[PSObject]]::new()
    }

    process {
        foreach ($incident in $InputObject) {
            try {
                # Validate input type
                if ($incident.PSObject.TypeNames[0] -ne 'Incident') {
                    $errorParams = @{
                        ErrorCategory = 'ValidationError'
                        ErrorCode = 3001
                        ErrorDetails = @{
                            Message = "Invalid input type. Expected 'Incident', got '$($incident.PSObject.TypeNames[0])'"
                        }
                    }
                    Write-CompassOneError @errorParams
                    continue
                }

                # Create formatted object
                $formattedIncident = [PSCustomObject]@{
                    PSTypeName = 'PSCompassOne.FormattedIncident'
                }

                # Format each property
                foreach ($prop in $Property) {
                    $value = $incident.$prop
                    
                    # Format dates
                    if ($prop -match 'On$' -and $value) {
                        $value = $value.ToString($DateFormat)
                    }
                    
                    # Format priority and status with color if enabled
                    if ($prop -eq 'Priority' -and -not $NoColor) {
                        $value = Format-IncidentPriority -Priority $value -NoColor:$NoColor
                    }
                    elseif ($prop -eq 'Status' -and -not $NoColor) {
                        $value = Format-IncidentStatus -Status $value -NoColor:$NoColor
                    }

                    $formattedIncident | Add-Member -NotePropertyName $prop -NotePropertyValue $value
                }

                $results.Add($formattedIncident)
            }
            catch {
                $errorParams = @{
                    ErrorCategory = 'InvalidOperation'
                    ErrorCode = 7001
                    ErrorDetails = @{
                        Message = "Failed to format incident: $_"
                        IncidentId = $incident.Id
                    }
                }
                Write-CompassOneError @errorParams
            }
        }
    }

    end {
        return $results.ToArray()
    }
}

<#
.SYNOPSIS
    Formats an incident object or collection for detailed list view output.
#>
function Format-IncidentList {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter()]
        [switch]$NoColor,

        [Parameter()]
        [string]$DateFormat = $script:DefaultIncidentListView.DateFormat,

        [Parameter()]
        [string[]]$Property = $script:DefaultIncidentListView.Properties,

        [Parameter()]
        [string]$GroupBy = $script:DefaultIncidentListView.GroupBy
    )

    begin {
        $results = [List[PSObject]]::new()
    }

    process {
        foreach ($incident in $InputObject) {
            try {
                # Validate input type
                if ($incident.PSObject.TypeNames[0] -ne 'Incident') {
                    $errorParams = @{
                        ErrorCategory = 'ValidationError'
                        ErrorCode = 3002
                        ErrorDetails = @{
                            Message = "Invalid input type. Expected 'Incident', got '$($incident.PSObject.TypeNames[0])'"
                        }
                    }
                    Write-CompassOneError @errorParams
                    continue
                }

                # Create formatted object
                $formattedIncident = [PSCustomObject]@{
                    PSTypeName = 'PSCompassOne.FormattedIncident.List'
                }

                # Format each property
                foreach ($prop in $Property) {
                    $value = $incident.$prop
                    
                    # Format dates
                    if ($prop -match 'On$' -and $value) {
                        $value = $value.ToString($DateFormat)
                    }
                    
                    # Format priority and status with color if enabled
                    if ($prop -eq 'Priority' -and -not $NoColor) {
                        $value = Format-IncidentPriority -Priority $value -NoColor:$NoColor
                    }
                    elseif ($prop -eq 'Status' -and -not $NoColor) {
                        $value = Format-IncidentStatus -Status $value -NoColor:$NoColor
                    }
                    # Format related findings as list
                    elseif ($prop -eq 'RelatedFindings' -and $value) {
                        $value = $value -join "`n  "
                        $value = "  $value"
                    }

                    $formattedIncident | Add-Member -NotePropertyName $prop -NotePropertyValue $value
                }

                # Add grouping property if specified
                if ($GroupBy) {
                    $formattedIncident | Add-Member -NotePropertyName 'GroupName' -NotePropertyValue $incident.$GroupBy
                }

                $results.Add($formattedIncident)
            }
            catch {
                $errorParams = @{
                    ErrorCategory = 'InvalidOperation'
                    ErrorCode = 7002
                    ErrorDetails = @{
                        Message = "Failed to format incident: $_"
                        IncidentId = $incident.Id
                    }
                }
                Write-CompassOneError @errorParams
            }
        }
    }

    end {
        return $results.ToArray()
    }
}

<#
.SYNOPSIS
    Formats incident priority enum values with color coding.
#>
function Format-IncidentPriority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IncidentPriority]$Priority,

        [Parameter()]
        [switch]$NoColor
    )

    if ($NoColor) {
        return $Priority.ToString()
    }

    # Color coding based on priority
    $colorCode = switch ($Priority) {
        'P1' { '91' } # Bright Red
        'P2' { '31' } # Red
        'P3' { '93' } # Bright Yellow
        'P4' { '33' } # Yellow
        'P5' { '32' } # Green
        default { '0' } # Default
    }

    return "$([char]27)[${colorCode}m$Priority$([char]27)[0m"
}

<#
.SYNOPSIS
    Formats incident status enum values with color coding.
#>
function Format-IncidentStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IncidentStatus]$Status,

        [Parameter()]
        [switch]$NoColor
    )

    if ($NoColor) {
        return $Status.ToString()
    }

    # Color coding based on status
    $colorCode = switch ($Status) {
        'New' { '96' }        # Bright Cyan
        'Assigned' { '93' }   # Bright Yellow
        'InProgress' { '92' } # Bright Green
        'OnHold' { '95' }     # Bright Magenta
        'Resolved' { '32' }   # Green
        'Closed' { '90' }     # Bright Black
        default { '0' }       # Default
    }

    return "$([char]27)[${colorCode}m$Status$([char]27)[0m"
}

# Export functions for module use
Export-ModuleMember -Function @(
    'Format-IncidentTable',
    'Format-IncidentList'
)