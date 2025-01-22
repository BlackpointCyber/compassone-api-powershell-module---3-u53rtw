# Contributing to PSCompassOne

## Table of Contents
- [Introduction](#introduction)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Issue Reporting](#issue-reporting)

## Introduction

Welcome to the PSCompassOne project! We're excited that you're interested in contributing to our PowerShell module for Blackpoint's CompassOne cybersecurity platform. This document provides comprehensive guidelines for contributing to the project.

### Types of Contributions
We welcome the following types of contributions:
- Bug fixes and feature implementations
- Documentation improvements
- Test coverage enhancements
- Performance optimizations
- Security improvements

### Code of Conduct
Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inclusive environment for all contributors.

### Quick Start
1. Fork and clone the repository
2. Set up your development environment
3. Create a feature branch
4. Make your changes
5. Submit a pull request

## Getting Started

### System Requirements
- Windows PowerShell 5.1+ or PowerShell 7.0+ (Core)
- Git 2.0+
- Visual Studio Code (recommended)

### Development Tools Installation
1. Install PowerShell:
   - Windows PowerShell 5.1 (included in Windows)
   - [PowerShell 7.0+](https://github.com/PowerShell/PowerShell)

2. Install Required PowerShell Modules:
```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name platyPS -Force
```

3. Install Visual Studio Code with extensions:
   - PowerShell Extension
   - EditorConfig
   - GitLens (recommended)

### Repository Setup
1. Fork the repository on GitHub
2. Clone your fork:
```powershell
git clone https://github.com/YOUR-USERNAME/PSCompassOne.git
cd PSCompassOne
```

3. Add upstream remote:
```powershell
git remote add upstream https://github.com/blackpoint/PSCompassOne.git
```

### Environment Verification
Run the verification script:
```powershell
./build/Test-DevEnvironment.ps1
```

## Development Workflow

### Branch Management
- Main branch: `main` (protected)
- Development branch: `develop`
- Feature branches: `feature/*`
- Bug fix branches: `bugfix/*`
- Hotfix branches: `hotfix/*`
- Documentation: `docs/*`

### Commit Message Standards
We follow the Conventional Commits specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types:
- feat: New feature
- fix: Bug fix
- docs: Documentation changes
- style: Code style changes
- refactor: Code refactoring
- test: Test updates
- chore: Build process or auxiliary tool changes

Example:
```
feat(asset): add support for bulk asset creation

- Implements batch processing for multiple assets
- Adds pipeline support for asset creation
- Updates documentation with examples

Resolves #123
```

### Pull Request Process
1. Create a feature branch from `develop`
2. Make your changes
3. Run all tests and style checks
4. Update documentation
5. Submit PR against `develop`
6. Address review feedback
7. Maintain PR up-to-date with `develop`

## Coding Standards

### PowerShell Style Guide
- Follow [PowerShell Practice and Style](https://poshcode.gitbook.io/powershell-practice-and-style/)
- Use approved verbs (Get-Verb)
- Follow noun-verb naming convention
- Use PascalCase for functions and parameters
- Use camelCase for variables

### Security Guidelines
- Never store credentials in code
- Use SecureString for sensitive data
- Implement proper error handling
- Follow principle of least privilege
- Use PowerShell SecretStore for credential storage

### Error Handling
```powershell
try {
    # Operation code
}
catch [System.Net.WebException] {
    Write-Error -Exception $_ -Category ConnectionError
}
catch {
    Write-Error -Exception $_ -Category OperationError
}
finally {
    # Cleanup code
}
```

### Code Organization
- Public functions in `Public` folder
- Private functions in `Private` folder
- One function per file
- Related functions in subfolders
- Tests mirror source structure

## Testing Guidelines

### Unit Testing Requirements
- Minimum 90% code coverage
- Test all public functions
- Test error conditions
- Use Pester 5.0+ framework

Example test:
```powershell
Describe "Get-Asset" {
    Context "When retrieving a single asset" {
        It "Returns the correct asset" {
            $result = Get-Asset -Id "test-id"
            $result.Id | Should -Be "test-id"
        }
    }
}
```

### Integration Testing
- Test API interactions
- Verify authentication flows
- Test rate limiting handling
- Validate error responses

### Code Coverage Verification
```powershell
Invoke-Pester -CodeCoverage .\src\*.ps1 -CodeCoverageOutputFile coverage.xml
```

## Documentation

### Code Documentation
- Use comment-based help
- Document all functions
- Include examples
- Specify parameter types and requirements

Example:
```powershell
<#
.SYNOPSIS
    Gets an asset from CompassOne.
.DESCRIPTION
    Retrieves an asset by ID or filter criteria from the CompassOne platform.
.PARAMETER Id
    The unique identifier of the asset.
.EXAMPLE
    Get-Asset -Id "asset-123"
#>
```

### PowerShell Help
- Generate help using platyPS
- Update help on changes
- Include practical examples
- Document all parameters

### API Documentation
- Document response formats
- Include rate limits
- Specify authentication requirements
- Provide error responses

## Issue Reporting

### Bug Reports
Include:
- PowerShell version
- Module version
- Steps to reproduce
- Expected vs actual behavior
- Error messages

### Feature Requests
Include:
- Use case description
- Proposed solution
- Alternative approaches
- Impact assessment

### Security Issues
- Follow our [Security Policy](SECURITY.md)
- Report privately via security@blackpoint.io
- Do not disclose publicly
- Include proof-of-concept if possible

### Issue Templates
Use provided templates for:
- Bug reports
- Feature requests
- Documentation updates
- Security reports

## Additional Resources
- [PowerShell Documentation](https://docs.microsoft.com/powershell)
- [Pester Documentation](https://pester.dev)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer/tree/master/docs/Rules)
- [Conventional Commits](https://www.conventionalcommits.org)

## Questions and Support
- Open a GitHub Discussion for questions
- Join our community chat
- Check existing issues and discussions
- Review documentation first

Thank you for contributing to PSCompassOne!