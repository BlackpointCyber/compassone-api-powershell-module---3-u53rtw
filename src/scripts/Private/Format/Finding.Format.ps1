#Requires -Version 7.0

# Version: Microsoft.PowerShell.Core 7.0.0
# Purpose: Defines PowerShell formatting configuration for Finding objects with enhanced display capabilities

#region Color Maps

# Define severity level color mapping
$script:SeverityColorMap = @{
    'Critical' = "`e[91m" # Bright Red
    'High'     = "`e[31m" # Red
    'Medium'   = "`e[33m" # Yellow
    'Low'      = "`e[36m" # Cyan
    'Info'     = "`e[32m" # Green
}

# Define status state color mapping
$script:StatusColorMap = @{
    'New'           = "`e[94m" # Bright Blue
    'InProgress'    = "`e[93m" # Bright Yellow
    'Resolved'      = "`e[92m" # Bright Green
    'Closed'        = "`e[90m" # Gray
    'FalsePositive' = "`e[37m" # White
}

# Reset ANSI sequence
$script:ResetColor = "`e[0m"

#endregion

#region Format Functions

function Format-FindingSeverity {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingSeverity
    )

    try {
        # Check if terminal supports ANSI
        if ($Host.UI.SupportsVirtualTerminal) {
            $colorCode = $script:SeverityColorMap[$FindingSeverity]
            return "$colorCode$FindingSeverity$script:ResetColor"
        }
        
        # Fallback for non-ANSI terminals
        return "[$FindingSeverity]"
    }
    catch {
        Write-Error -Message "Failed to format finding severity: $_" -Category InvalidOperation
        return $FindingSeverity
    }
}

function Format-FindingStatus {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingStatus
    )

    try {
        # Check if terminal supports ANSI
        if ($Host.UI.SupportsVirtualTerminal) {
            $colorCode = $script:StatusColorMap[$FindingStatus]
            return "$colorCode$FindingStatus$script:ResetColor"
        }
        
        # Fallback for non-ANSI terminals
        return "[$FindingStatus]"
    }
    catch {
        Write-Error -Message "Failed to format finding status: $_" -Category InvalidOperation
        return $FindingStatus
    }
}

function Format-FindingScore {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(0.0, 10.0)]
        [float]$FindingScore
    )

    try {
        if ($Host.UI.SupportsVirtualTerminal) {
            $colorCode = switch ($FindingScore) {
                {$_ -ge 9.0} { $script:SeverityColorMap['Critical'] }
                {$_ -ge 7.0} { $script:SeverityColorMap['High'] }
                {$_ -ge 4.0} { $script:SeverityColorMap['Medium'] }
                {$_ -ge 1.0} { $script:SeverityColorMap['Low'] }
                default { $script:SeverityColorMap['Info'] }
            }
            return "$colorCode$($FindingScore.ToString('F1'))$script:ResetColor"
        }

        return $FindingScore.ToString('F1')
    }
    catch {
        Write-Error -Message "Failed to format finding score: $_" -Category InvalidOperation
        return $FindingScore.ToString('F1')
    }
}

#endregion

#region Format Configuration

function Register-FindingFormatData {
    [CmdletBinding()]
    param()

    try {
        # Define default table view
        $defaultTableView = @{
            ViewName = "Default"
            TableControl = @{
                Headers = @(
                    @{ Label = "ID"; Width = 36 },
                    @{ Label = "Title"; Width = 40 },
                    @{ Label = "Class"; Width = 12 },
                    @{ Label = "Severity"; Width = 10; Alignment = "Left" },
                    @{ Label = "Status"; Width = 12; Alignment = "Left" },
                    @{ Label = "Score"; Width = 6; Alignment = "Right" }
                )
                Rows = @{
                    Properties = @(
                        "Id",
                        "Title",
                        "Class",
                        @{ ScriptBlock = { Format-FindingSeverity $_.Severity } },
                        @{ ScriptBlock = { Format-FindingStatus $_.Status } },
                        @{ ScriptBlock = { Format-FindingScore $_.Score } }
                    )
                }
            }
        }

        # Define default list view
        $defaultListView = @{
            ViewName = "List"
            ListControl = @{
                Properties = @(
                    @{ Label = "ID"; PropertyName = "Id" },
                    @{ Label = "Title"; PropertyName = "Title" },
                    @{ Label = "Class"; PropertyName = "Class" },
                    @{ Label = "Severity"; ScriptBlock = { Format-FindingSeverity $_.Severity } },
                    @{ Label = "Status"; ScriptBlock = { Format-FindingStatus $_.Status } },
                    @{ Label = "Score"; ScriptBlock = { Format-FindingScore $_.Score } },
                    @{ Label = "Found On"; PropertyName = "FoundOn" },
                    @{ Label = "Created"; ScriptBlock = { "{0} by {1}" -f $_.CreatedOn.ToString('u'), $_.CreatedBy } },
                    @{ Label = "Updated"; ScriptBlock = { 
                        if ($_.UpdatedOn) { 
                            "{0} by {1}" -f $_.UpdatedOn.ToString('u'), $_.UpdatedBy 
                        } else { "Not Updated" }
                    }}
                )
            }
        }

        # Register format data with PowerShell
        Update-FormatData -PrependPath $defaultTableView, $defaultListView

        # Set default display properties
        $defaultDisplaySet = @('Id', 'Title', 'Class', 'Severity', 'Status', 'Score')
        Update-TypeData -TypeName Finding -DefaultDisplayPropertySet $defaultDisplaySet -Force

        Write-Verbose "Successfully registered Finding format data"
    }
    catch {
        Write-Error -Message "Failed to register Finding format data: $_" -Category InvalidOperation
        throw
    }
}

#endregion

# Export the format registration function
Export-ModuleMember -Function Register-FindingFormatData