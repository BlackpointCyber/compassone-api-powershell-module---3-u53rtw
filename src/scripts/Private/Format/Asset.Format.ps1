#Requires -Version 7.0

using namespace System
using namespace System.Collections.Generic

# Version: Microsoft.PowerShell.Utility 7.0.0
# Purpose: Formatting functions for Asset objects with enhanced display capabilities

#region Global Variables

# Default table format configuration for assets
$script:DefaultAssetTableFormat = [PSCustomObject]@{
    Properties = @(
        @{ Name = 'Id'; Expression = { $_.Id }; Width = 36 }
        @{ Name = 'Name'; Expression = { $_.Name }; Width = 30 }
        @{ Name = 'Status'; Expression = { $_.Status.ToString() }; Width = 10 }
        @{ Name = 'LastSeen'; Expression = { $_.LastSeenOn.ToLocalTime().ToString('g') }; Width = 20 }
        @{ Name = 'Type'; Expression = { $_.Class.ToString() }; Width = 15 }
    )
    GroupBy = $null
    Wrap = $false
}

# Default list format configuration for assets
$script:DefaultAssetListFormat = [PSCustomObject]@{
    Properties = @(
        'Id'
        'Name'
        'Class'
        'Status'
        @{ Name = 'Tags'; Expression = { $_.Tags -join ', ' } }
        @{ Name = 'Found'; Expression = { $_.FoundOn.ToLocalTime().ToString('g') } }
        @{ Name = 'LastSeen'; Expression = { $_.LastSeenOn.ToLocalTime().ToString('g') } }
        'Description'
        @{ Name = 'Created'; Expression = { "$($_.CreatedOn.ToLocalTime().ToString('g')) by $($_.CreatedBy)" } }
        @{ Name = 'Updated'; Expression = { if($_.UpdatedOn) { "$($_.UpdatedOn.Value.ToLocalTime().ToString('g')) by $($_.UpdatedBy)" } else { 'N/A' } } }
    )
    GroupBy = $null
}

#endregion

#region Functions

function Format-AssetTable {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter()]
        [string]$Culture = (Get-Culture).Name
    )

    begin {
        $culture = [CultureInfo]::GetCultureInfo($Culture)
        [DateTime]::CurrentCulture = $culture
        $results = [List[PSObject]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            if ($item -isnot [Asset]) {
                Write-Error "Input object must be of type [Asset]"
                continue
            }

            $formattedObject = [PSCustomObject]@{}
            foreach ($property in $DefaultAssetTableFormat.Properties) {
                $value = if ($property -is [hashtable]) {
                    & $property.Expression $item
                } else {
                    $item.$property
                }
                Add-Member -InputObject $formattedObject -MemberType NoteProperty -Name $property.Name -Value $value
            }
            $results.Add($formattedObject)
        }
    }

    end {
        $results | Format-Table -Property $DefaultAssetTableFormat.Properties.Name -AutoSize -Wrap:$DefaultAssetTableFormat.Wrap
    }
}

function Format-AssetList {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter()]
        [string]$Culture = (Get-Culture).Name
    )

    begin {
        $culture = [CultureInfo]::GetCultureInfo($Culture)
        [DateTime]::CurrentCulture = $culture
        $results = [List[PSObject]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            if ($item -isnot [Asset]) {
                Write-Error "Input object must be of type [Asset]"
                continue
            }

            $formattedObject = [PSCustomObject]@{}
            foreach ($property in $DefaultAssetListFormat.Properties) {
                $value = if ($property -is [hashtable]) {
                    & $property.Expression $item
                } else {
                    $item.$property
                }
                Add-Member -InputObject $formattedObject -MemberType NoteProperty -Name $(if($property -is [hashtable]) { $property.Name } else { $property }) -Value $value
            }
            $results.Add($formattedObject)
        }
    }

    end {
        $results | Format-List
    }
}

function Format-AssetCustomView {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Properties,

        [Parameter()]
        [string]$Culture = (Get-Culture).Name,

        [Parameter()]
        [hashtable]$FormatOptions = @{}
    )

    begin {
        $culture = [CultureInfo]::GetCultureInfo($Culture)
        [DateTime]::CurrentCulture = $culture
        $results = [List[PSObject]]::new()

        # Validate properties exist on Asset type
        $validProperties = [Asset].GetProperties().Name
        $invalidProperties = $Properties | Where-Object { $_ -notin $validProperties }
        if ($invalidProperties) {
            throw "Invalid properties specified: $($invalidProperties -join ', ')"
        }

        # Process format options
        $defaultOptions = @{
            AutoSize = $true
            Wrap = $false
            GroupBy = $null
            DateFormat = 'g'
            TagSeparator = ', '
        }
        $formatSettings = $defaultOptions + $FormatOptions
    }

    process {
        foreach ($item in $InputObject) {
            if ($item -isnot [Asset]) {
                Write-Error "Input object must be of type [Asset]"
                continue
            }

            $formattedObject = [PSCustomObject]@{}
            foreach ($property in $Properties) {
                $value = switch ($property) {
                    { $_ -in @('FoundOn', 'LastSeenOn', 'CreatedOn', 'UpdatedOn', 'DeletedOn') } {
                        if ($item.$property) {
                            $item.$property.ToLocalTime().ToString($formatSettings.DateFormat)
                        } else { 'N/A' }
                    }
                    'Tags' { $item.Tags -join $formatSettings.TagSeparator }
                    default { $item.$property }
                }
                Add-Member -InputObject $formattedObject -MemberType NoteProperty -Name $property -Value $value
            }
            $results.Add($formattedObject)
        }
    }

    end {
        if ($formatSettings.GroupBy) {
            $results | Sort-Object $formatSettings.GroupBy | Format-Table -GroupBy $formatSettings.GroupBy -Property $Properties -AutoSize:$formatSettings.AutoSize -Wrap:$formatSettings.Wrap
        } else {
            $results | Format-Table -Property $Properties -AutoSize:$formatSettings.AutoSize -Wrap:$formatSettings.Wrap
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function Format-AssetTable, Format-AssetList, Format-AssetCustomView