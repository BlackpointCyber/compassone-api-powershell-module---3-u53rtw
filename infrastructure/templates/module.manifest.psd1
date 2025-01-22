# Module manifest template for PSCompassOne
# Version: 1.0.0
# Copyright (c) Blackpoint. All rights reserved.

@{
    # Script module or binary module file associated with this manifest
    RootModule = 'PSCompassOne.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Unique identifier for this module
    GUID = '00000000-0000-0000-0000-000000000000'

    # Author of this module
    Author = 'Blackpoint'

    # Company or vendor of this module
    CompanyName = 'Blackpoint'

    # Copyright statement for this module
    Copyright = '(c) Blackpoint. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for CompassOne cybersecurity platform providing secure, programmatic access through native PowerShell commands with comprehensive security features and enterprise integration capabilities'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Minimum version of the .NET Framework required by this module
    DotNetFrameworkVersion = '4.7.2'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion = '4.0'

    # Processor architecture (None, X86, Amd64) required by this module
    ProcessorArchitecture = 'None'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        'Microsoft.PowerShell.SecretStore',  # v1.0.6 - For secure credential storage
        'Microsoft.PowerShell.Security'      # v7.0.0 - For certificate and security features
    )

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @('./Config/PSCompassOne.format.ps1xml')

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @('./Config/PSCompassOne.types.ps1xml')

    # Functions to export from this module
    FunctionsToExport = @(
        # Connection Management
        'Connect-CompassOne',
        'Disconnect-CompassOne',
        
        # Asset Management
        'Get-Asset',
        'New-Asset',
        'Set-Asset',
        'Remove-Asset',
        
        # Finding Management
        'Get-Finding',
        'New-Finding',
        'Set-Finding',
        'Remove-Finding',
        
        # Incident Management
        'Get-Incident',
        'New-Incident',
        'Set-Incident',
        'Remove-Incident',
        
        # Configuration and Testing
        'Test-CompassOneConnection',
        'Get-CompassOneConfig',
        'Set-CompassOneConfig'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for PowerShell Gallery discoverability
            Tags = @(
                'Security',
                'CompassOne',
                'Blackpoint',
                'API',
                'SecOps',
                'Cybersecurity',
                'Enterprise',
                'Automation',
                'DevSecOps'
            )

            # License URI for this module
            LicenseUri = 'https://github.com/blackpoint/pscompassone/blob/main/LICENSE'

            # Project URI for this module
            ProjectUri = 'https://github.com/blackpoint/pscompassone'

            # Icon URI for this module
            IconUri = 'https://raw.githubusercontent.com/blackpoint/pscompassone/main/assets/icon.png'

            # Release notes for this module
            ReleaseNotes = 'Initial release of PSCompassOne module with comprehensive security features and enterprise integration capabilities'
        }

        # Require license acceptance before module installation
        RequireLicenseAcceptance = $true

        # External module dependencies that must be installed
        ExternalModuleDependencies = @('Microsoft.PowerShell.SecretStore')

        # Security bug tracking URL
        SecurityBugTracking = 'https://github.com/blackpoint/pscompassone/security/advisories'

        # Help info URI for online documentation
        HelpInfoURI = 'https://docs.blackpoint.io/pscompassone'
    }
}