@{
    # Core Module Information
    ModuleName = 'PSCompassOne'
    ModuleVersion = '1.0.0'
    Author = 'Blackpoint'
    CompanyName = 'Blackpoint'
    Description = 'PowerShell module for programmatic access to Blackpoint''s CompassOne cybersecurity platform'
    
    # Build Output Paths
    BuildOutputPath = './build'
    TestOutputPath = './test'
    DocsOutputPath = './docs'
    
    # Code Signing Configuration
    SigningCertificate = $null
    CodeSigningEnabled = $false
    CertificateThumbprint = $null
    CertificateFile = $null
    CertificatePassword = $null
    
    # Build Configuration
    BuildConfiguration = 'Release'
    BuildOptimization = 'Speed'
    CrossPlatform = $true
    ProcessorArchitecture = 'None'
    
    # Module Requirements
    MinimumPowerShellVersion = '5.1'
    RequiredModules = @(
        'Microsoft.PowerShell.SecretStore'
    )
    RequiredAssemblies = @()
    FileList = @()
    
    # Module Metadata
    Tags = @(
        'Security',
        'CompassOne',
        'Blackpoint',
        'API'
    )
    LicenseUri = 'https://github.com/blackpoint/pscompassone/blob/main/LICENSE'
    ProjectUri = 'https://github.com/blackpoint/pscompassone'
    ReleaseNotes = 'Initial release of PSCompassOne module'
    
    # Distribution Settings
    PrivateRepository = $null
    GalleryApiKey = $null
    
    # Version Management
    PreviewVersion = $false
    HotfixVersion = $false
    
    # Development Tools
    TestFramework = 'Pester'
    CodeAnalysis = 'PSScriptAnalyzer'
    DocumentationTool = 'platyPS'
    
    # Function to retrieve and validate build configuration
    GetBuildConfiguration = {
        $config = $BuildSettings
        
        # Validate required paths
        if (-not (Test-Path -Path $config.BuildOutputPath -PathType Container)) {
            New-Item -Path $config.BuildOutputPath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -Path $config.TestOutputPath -PathType Container)) {
            New-Item -Path $config.TestOutputPath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -Path $config.DocsOutputPath -PathType Container)) {
            New-Item -Path $config.DocsOutputPath -ItemType Directory -Force | Out-Null
        }
        
        # Validate code signing if enabled
        if ($config.CodeSigningEnabled) {
            if (-not $config.CertificateThumbprint -and -not $config.CertificateFile) {
                throw "Code signing is enabled but no certificate is specified"
            }
        }
        
        # Validate version format
        if (-not ($config.ModuleVersion -match '^\d+\.\d+\.\d+$')) {
            throw "Invalid module version format. Must be in format: Major.Minor.Build"
        }
        
        # Adjust version for preview/hotfix
        if ($config.PreviewVersion) {
            $config.ModuleVersion = "$($config.ModuleVersion)-preview"
        }
        elseif ($config.HotfixVersion) {
            $config.ModuleVersion = "$($config.ModuleVersion)-hotfix"
        }
        
        # Validate PowerShell version
        if (-not ($config.MinimumPowerShellVersion -match '^\d+\.\d+$')) {
            throw "Invalid PowerShell version format. Must be in format: Major.Minor"
        }
        
        # Validate required modules
        foreach ($module in $config.RequiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                throw "Required module not found: $module"
            }
        }
        
        return $config
    }
}