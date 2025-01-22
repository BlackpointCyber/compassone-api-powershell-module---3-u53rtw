#Requires -Version 7.0
using namespace System
using namespace System.Collections.Generic
using namespace System.Management.Automation

# Version: Microsoft.PowerShell.Core 7.0.0
# Version: Microsoft.PowerShell.SecretStore 1.0.0

#region Module Variables

# Module root path with cross-platform support
$script:PSCompassOneModuleRoot = $PSScriptRoot

# Module configuration with default values
$script:PSCompassOneConfig = @{
    ApiVersion = 'v1'
    DefaultTimeout = 30
    MaxRetryCount = 3
    CacheTTL = 300
    LogLevel = 'Information'
    UseCache = $true
}

#endregion

#region Type System Initialization

# Import type definition files with enhanced error handling
$typeFiles = @(
    'Asset.Types.ps1',
    'Finding.Types.ps1',
    'Incident.Types.ps1'
)

foreach ($typeFile in $typeFiles) {
    $typePath = Join-Path -Path $PSCompassOneModuleRoot -ChildPath "Private\Types\$typeFile"
    try {
        . $typePath
        Write-Verbose "Successfully loaded type definitions from: $typeFile"
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [ErrorRecord]::new(
                [InvalidOperationException]::new("Failed to load type definitions from $typeFile: $_"),
                'TypeLoadError',
                [ErrorCategory]::InvalidOperation,
                $typePath
            )
        )
    }
}

#endregion

#region Module Initialization

function Initialize-PSCompassOne {
    [CmdletBinding()]
    param()

    try {
        # Validate PowerShell version
        $requiredVersion = [Version]'7.0'
        if ($PSVersionTable.PSVersion -lt $requiredVersion) {
            throw "PSCompassOne requires PowerShell $requiredVersion or later"
        }

        # Load format data
        $formatPath = Join-Path -Path $PSCompassOneModuleRoot -ChildPath 'Config\PSCompassOne.format.ps1xml'
        if (Test-Path -Path $formatPath) {
            Update-FormatData -AppendPath $formatPath -ErrorAction Stop
            Write-Verbose "Successfully loaded format data from: $formatPath"
        }

        # Load type data
        $typesPath = Join-Path -Path $PSCompassOneModuleRoot -ChildPath 'Config\PSCompassOne.types.ps1xml'
        if (Test-Path -Path $typesPath) {
            Update-TypeData -AppendPath $typesPath -ErrorAction Stop
            Write-Verbose "Successfully loaded type data from: $typesPath"
        }

        # Initialize SecretStore configuration
        if (-not (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable)) {
            throw "Required module 'Microsoft.PowerShell.SecretStore' is not installed"
        }

        # Import private functions
        Import-PSCompassOneFunctions -Path (Join-Path -Path $PSCompassOneModuleRoot -ChildPath 'Private') -IsPublic $false

        # Import public functions
        Import-PSCompassOneFunctions -Path (Join-Path -Path $PSCompassOneModuleRoot -ChildPath 'Public') -IsPublic $true

        Write-Verbose "PSCompassOne module initialization completed successfully"
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [ErrorRecord]::new(
                [InvalidOperationException]::new("Module initialization failed: $_"),
                'ModuleInitError',
                [ErrorCategory]::InvalidOperation,
                $null
            )
        )
    }
}

function Import-PSCompassOneFunctions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [bool]$IsPublic
    )

    try {
        # Validate path exists
        if (-not (Test-Path -Path $Path)) {
            throw "Path not found: $Path"
        }

        # Get all PS1 files recursively
        $files = Get-ChildItem -Path $Path -Filter '*.ps1' -Recurse -ErrorAction Stop

        # Import each function file
        foreach ($file in $files) {
            try {
                . $file.FullName
                Write-Verbose "Successfully imported function file: $($file.Name)"

                # Export public functions
                if ($IsPublic) {
                    $functionName = $file.BaseName
                    Export-ModuleMember -Function $functionName -ErrorAction Stop
                    Write-Verbose "Exported public function: $functionName"
                }
            }
            catch {
                Write-Error "Failed to import function file $($file.Name): $_"
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [ErrorRecord]::new(
                [InvalidOperationException]::new("Function import failed: $_"),
                'FunctionImportError',
                [ErrorCategory]::InvalidOperation,
                $Path
            )
        )
    }
}

#endregion

#region Module Exports

# Export core types
Export-ModuleMember -Function @(
    'Get-Asset'
    'New-Asset'
    'Set-Asset'
    'Remove-Asset'
    'Get-Finding'
    'New-Finding'
    'Set-Finding'
    'Remove-Finding'
    'Get-Incident'
    'New-Incident'
    'Set-Incident'
    'Remove-Incident'
    'Connect-CompassOne'
    'Disconnect-CompassOne'
    'Set-CompassOneConfig'
)

# Export type data
Export-ModuleMember -TypeData @(
    [Asset]
    [Finding]
    [Incident]
)

#endregion

# Initialize module on import
Initialize-PSCompassOne