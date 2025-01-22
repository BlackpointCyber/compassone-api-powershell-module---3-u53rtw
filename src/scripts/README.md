# PSCompassOne PowerShell Module

[![Build Status](https://github.com/blackpoint/pscompassone/workflows/CI/badge.svg)](https://github.com/blackpoint/pscompassone/actions)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![License](https://img.shields.io/github/license/blackpoint/pscompassone)](LICENSE)
[![Code Coverage](https://img.shields.io/codecov/c/github/blackpoint/pscompassone)](https://codecov.io/gh/blackpoint/pscompassone)
[![Platform Support](https://img.shields.io/powershellgallery/p/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)

> PowerShell module for programmatic access to Blackpoint's CompassOne cybersecurity platform

- [Installation](#installation)
- [Documentation](#documentation)
- [Examples](#examples)
- [Contributing](#contributing)

## Description

PSCompassOne provides native PowerShell commands for interacting with Blackpoint's CompassOne cybersecurity platform, enabling seamless automation and integration capabilities for security operations.

### Key Features

- Asset inventory management
- Security posture assessment
- Incident response automation
- Compliance tracking
- Tenant management
- Pipeline support for bulk operations
- Secure credential management
- Cross-platform compatibility

### Compatibility

- PowerShell Versions:
  - Windows PowerShell 5.1+
  - PowerShell 7.0+ (Cross-platform)
- Platforms:
  - Windows
  - Linux
  - macOS
- API Version: v1

## Installation

### Prerequisites

- PowerShell 5.1+ (Windows) or PowerShell 7.0+ (Cross-platform)
- Internet connectivity
- CompassOne API credentials

### PowerShell Gallery (Recommended)

```powershell
# Install the module
Install-Module -Name PSCompassOne -Scope CurrentUser

# Import the module
Import-Module PSCompassOne

# Verify installation
Get-Module PSCompassOne
```

### Manual Installation

1. Download the latest release from the [releases page](https://github.com/blackpoint/pscompassone/releases)
2. Extract the archive to your PowerShell modules directory:
   - Windows: `$env:UserProfile\Documents\WindowsPowerShell\Modules\PSCompassOne`
   - PowerShell Core: `$env:UserProfile\Documents\PowerShell\Modules\PSCompassOne`
3. Import the module:
   ```powershell
   Import-Module PSCompassOne
   ```
4. Verify installation:
   ```powershell
   Test-ModuleManifest -Path (Join-Path (Get-Module PSCompassOne -ListAvailable).ModuleBase 'PSCompassOne.psd1')
   ```

### Troubleshooting

- Ensure you have the required PowerShell version
- Check for execution policy restrictions: `Get-ExecutionPolicy`
- Verify module path is in `$env:PSModulePath`
- Run `Install-Module` with `-Verbose` for detailed output

## Usage

### Quick Start

```powershell
# Connect to CompassOne
Connect-CompassOne -ApiKey 'your-api-key'

# List assets
Get-Asset

# Get security findings
Get-Finding

# View active incidents
Get-Incident -Status Active
```

### Examples

#### Asset Management

```powershell
# List all assets
Get-Asset | Format-Table Id, Name, Status, LastSeenOn

# Filter assets by type
Get-Asset -Type Device -Status Active

# Create new asset
New-Asset -Name 'WebServer01' -Type Device -Tags @('Production', 'Web')

# Update asset properties
Set-Asset -Id 'asset-id' -Status Inactive

# Remove asset
Remove-Asset -Id 'asset-id' -Confirm:$false
```

#### Finding Management

```powershell
# Get security findings
Get-Finding -Severity High

# Create finding
New-Finding -Title 'Security Violation' -Severity High -Score 8.5

# Update finding status
Set-Finding -Id 'finding-id' -Status Resolved

# Export findings report
Get-Finding -Status Open | Export-Csv -Path 'findings-report.csv'
```

#### Incident Management

```powershell
# List active incidents
Get-Incident -Status Active

# Create incident
New-Incident -Title 'Security Breach' -Severity Critical

# Update incident status
Set-Incident -Id 'incident-id' -Status Investigating

# Close incident
Set-Incident -Id 'incident-id' -Status Closed -Resolution 'Issue resolved'
```

### Advanced Usage

#### Pipeline Operations

```powershell
# Bulk processing
Get-Asset -Type Device | Set-Asset -Status Inactive

# Filtering and transformation
Get-Finding -Severity High |
    Where-Object { $_.Score -gt 7 } |
    Select-Object Id, Title, Score |
    Export-Csv 'high-risk-findings.csv'
```

#### Error Handling

```powershell
try {
    $asset = Get-Asset -Id 'non-existent-id' -ErrorAction Stop
} catch [PSCompassOne.ResourceNotFoundException] {
    Write-Warning "Asset not found: $_"
} catch {
    Write-Error "Unexpected error: $_"
}
```

## Configuration

### Settings

Configure the module using environment variables or the `Set-CompassOneConfig` cmdlet:

```powershell
# Using environment variables
$env:COMPASSONE_API_URL = 'https://api.compassone.blackpoint.io'
$env:COMPASSONE_API_KEY = 'your-api-key'
$env:COMPASSONE_LOG_LEVEL = 'Verbose'
$env:COMPASSONE_CACHE_TTL = '3600'

# Using configuration cmdlet
Set-CompassOneConfig -ApiUrl 'https://api.compassone.blackpoint.io' -LogLevel Verbose
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| COMPASSONE_API_URL | API endpoint URL | https://api.compassone.blackpoint.io |
| COMPASSONE_API_KEY | Authentication key | - |
| COMPASSONE_API_VERSION | API version | v1 |
| COMPASSONE_TIMEOUT | Request timeout (seconds) | 30 |
| COMPASSONE_MAX_RETRY | Maximum retry attempts | 3 |
| COMPASSONE_LOG_LEVEL | Logging detail level | Information |
| COMPASSONE_CACHE_TTL | Cache lifetime (seconds) | 3600 |

### Security Best Practices

1. API Key Management
   - Store API keys securely using SecretStore
   - Never hardcode credentials in scripts
   - Rotate keys regularly

2. Secure Storage
   ```powershell
   # Store API key securely
   Set-Secret -Name 'CompassOneApiKey' -SecureString (ConvertTo-SecureString 'your-api-key' -AsPlainText -Force)
   ```

3. Access Control
   - Use least-privilege accounts
   - Implement role-based access
   - Regular access review

4. Audit Logging
   ```powershell
   # Enable verbose logging
   $VerbosePreference = 'Continue'
   Connect-CompassOne -ApiKey $apiKey
   ```

## Development

### Setup

#### Prerequisites

- Git
- PowerShell 7.0+
- Visual Studio Code
- Pester 5.0+

#### Environment Setup

```powershell
# Clone repository
git clone https://github.com/blackpoint/pscompassone.git
cd pscompassone

# Install dependencies
./build.ps1 -Bootstrap

# Run tests
./build.ps1 -Test
```

### Guidelines

#### Code Style

- Follow PowerShell best practices
- Use approved verbs for functions
- Include comment-based help
- Implement proper error handling

#### Testing Requirements

- Maintain >90% code coverage
- Include unit and integration tests
- Performance test critical paths

#### Documentation

- Update help content for new features
- Include practical examples
- Keep README current

## Contributing

### Guidelines

1. Read the [Code of Conduct](CODE_OF_CONDUCT.md)
2. Fork the repository
3. Create a feature branch
4. Submit a pull request

### Development Workflow

1. Branch naming:
   - feature/description
   - bugfix/description
   - docs/description

2. Commit messages:
   - Clear and descriptive
   - Reference issues
   - Follow conventional commits

3. Pull Request Process:
   - Update documentation
   - Add/update tests
   - Pass all checks
   - Request review

### Testing Requirements

- Add unit tests for new features
- Update integration tests
- Verify documentation accuracy
- Test cross-platform compatibility

## License

MIT © 2024 Blackpoint Cyber

See [LICENSE](LICENSE) for full details.