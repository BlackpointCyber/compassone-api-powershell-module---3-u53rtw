# PSCompassOne PowerShell Module

[![Build Status](https://img.shields.io/github/workflow/status/blackpoint/pscompassone/CI)](https://github.com/blackpoint/pscompassone/actions)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![License](https://img.shields.io/github/license/blackpoint/pscompassone)](LICENSE)
[![Code Coverage](https://img.shields.io/codecov/c/github/blackpoint/pscompassone)](https://codecov.io/gh/blackpoint/pscompassone)

PowerShell module providing programmatic access to Blackpoint's CompassOne cybersecurity platform through native PowerShell commands.

## Features

- Comprehensive asset inventory management with CRUD operations
- Real-time security posture assessment and monitoring
- Automated incident response and management
- Compliance tracking and reporting
- Multi-tenant management and configuration
- Pipeline support for bulk operations
- Secure credential management
- Cross-platform compatibility

## Requirements

### PowerShell Version
- Windows: Windows PowerShell 5.1 or PowerShell 7.0+
- Linux: PowerShell 7.0+
- macOS: PowerShell 7.0+

### Dependencies
- Required: Microsoft.PowerShell.SecretStore
- Optional: Microsoft.PowerShell.ConsoleGuiTools

## Installation

### PowerShell Gallery (Recommended)
```powershell
Install-Module -Name PSCompassOne -Scope CurrentUser
```

### Manual Installation
1. Clone repository:
```powershell
git clone https://github.com/blackpoint/pscompassone
```
2. Navigate to directory:
```powershell
cd pscompassone
```
3. Run installation script:
```powershell
./install.ps1
```

## Quick Start

### Connect to CompassOne
```powershell
Connect-CompassOne -ApiKey 'your-api-key'
```

### List Assets
```powershell
Get-Asset | Format-Table Id, Name, Status
```

### Handle Security Findings
```powershell
Get-Finding -Severity High | Set-Finding -Status InProgress
```

## Documentation

### Command Help
Get detailed help for any command:
```powershell
Get-Help Get-Asset -Detailed
Get-Help Get-Asset -Examples
```

### About Topics
- about_PSCompassOne
- about_PSCompassOne_Security
- about_PSCompassOne_Pipeline

### Online Documentation
Visit our [comprehensive documentation](https://docs.blackpoint.io/pscompassone) for detailed guides, examples, and best practices.

## Contributing

We welcome contributions from the community! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

### Areas for Contribution
- Code contributions
- Documentation improvements
- Test coverage
- Bug reports
- Feature requests

### Development Workflow
1. Fork repository
2. Create feature branch
3. Add tests
4. Create pull request

## Security

Please review our [Security Policy](SECURITY.md) for important security information.

### Reporting Security Issues
Report security vulnerabilities to security@blackpoint.io. See our security policy for the responsible disclosure process.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

© 2024 Blackpoint Cyber