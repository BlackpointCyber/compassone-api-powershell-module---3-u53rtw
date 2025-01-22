```
# CompassOne PowerShell Module Requirements

## Vision & Purpose

### Overview

Blackpoint has developed CompassOne, a comprehensive cyber security platform that helps businesses improve their security posture through both preventative and reactive measures. The platform generates security posture scores and offers various modules including asset inventory, security posture graphing, detection and response (with 24/7 SOC support), exposure prioritization, compliance tracking, and tenant management capabilities.

### Purpose

The purpose of this project is to create a PowerShell module that provides native PowerShell access to CompassOne's REST API endpoints. This module will allow PowerShell users to interact with the CompassOne platform programmatically without having to write custom REST API integration code.

### Target Users

- IT professionals who use PowerShell as their primary automation tool
- Security engineers who need to integrate CompassOne into their PowerShell-based workflows
- System administrators managing multiple systems through PowerShell
- DevOps engineers incorporating CompassOne into their automation pipelines

## Core Requirements

### Functional Requirements

#### Module Structure and Installation

1. Module Name and Distribution
    - Module must be named "PSCompassOne"
    - Must be installable via PowerShell Gallery
    - Must support direct installation from GitHub
    - Must follow standard PowerShell module structure:
      ```
      PSCompassOne/
      ├── PSCompassOne.psd1          # Module manifest
      ├── PSCompassOne.psm1          # Module script file
      ├── Public/                    # Public functions
      ├── Private/                   # Private/helper functions
      ├── Tests/                     # Pester test files
      └── en-US/                     # Help files
      ```

2. Version Information
    - Version must be properly defined in module manifest (.psd1):
      ```powershell
      @{
          ModuleVersion = '1.0.0'
          # ... other manifest properties
      }
      ```
    - Users can access version information using standard PowerShell commands:
      ```powershell
      Get-Module PSCompassOne                  # Shows full module info
      (Get-Module PSCompassOne).Version        # Shows just version
      ```

#### Command Naming and Structure

1. Command Naming Conventions
    - Must follow Verb-Noun format
    - Must use approved PowerShell verbs (Get, Set, New, Remove, etc.)
    - Must use singular nouns (Asset not Assets)
    - Must use PascalCase for all public identifiers
    - Examples of correct naming:
        - `Get-Asset` (not GetAsset or Get-Assets)
        - `New-Incident` (not CreateIncident or New-Incidents)
        - `Remove-Tag` (not DeleteTag or Remove-Tags)

2. Parameter Naming and Structure
    - Must use PascalCase for parameter names
    - Must support both positional and named parameters
    - Required parameters should support positional binding
    - Optional parameters must use named parameters
    - Example parameter structure:
      ```powershell
      function Get-Asset {
          [CmdletBinding()]
          param(
              [Parameter(Position=0)]
              [string]$Id,
              
              [Parameter()]
              [int]$PageSize = 50,
              
              [Parameter()]
              [int]$Page = 1,
              
              [Parameter()]
              [string]$SortBy = "name",
              
              [Parameter()]
              [ValidateSet("ASC", "DESC")]
              [string]$SortOrder = "ASC"
          )
          # Function implementation
      }
      ```

#### Help System Integration

1. Comment-Based Help Requirements
    - Must include detailed comment-based help for all public functions
    - Must support all standard Get-Help parameters (-Detailed, -Full, -Examples)
    - Must include at least three examples per command
    - Example help structure:
      ```powershell
      <#
      .SYNOPSIS
          Gets assets from the CompassOne platform.
      
      .DESCRIPTION
          The Get-Asset cmdlet retrieves assets from the CompassOne platform.
          Without parameters, it returns all assets. With an ID, it returns a specific asset.
      
      .PARAMETER Id
          The unique identifier of the asset to retrieve.
      
      .PARAMETER PageSize
          The number of items to return per page. Default is 50.
      
      .PARAMETER Page
          The page number to retrieve. Default is 1.
      
      .EXAMPLE
          Get-Asset
          Returns all assets using default paging.
      
      .EXAMPLE
          Get-Asset -Id "abc123"
          Returns the asset with ID "abc123".
      
      .EXAMPLE
          Get-Asset -PageSize 100 -Page 2
          Returns the second page of assets with 100 items per page.
      #>
      ```

#### API Integration

1. Authentication and Configuration
    - Must support three configuration methods in priority order:
        1. Command-line parameters (-Url and -Token)
        2. Environment variables (COMPASSONE_API_URL and COMPASSONE_API_TOKEN)
        3. Microsoft.PowerShell.SecretStore
    - Example configuration function:
      ```powershell
      function Set-PSCompassOneConfiguration {
          [CmdletBinding()]
          param(
              [Parameter(Mandatory=$true, Position=0)]
              [ValidateNotNullOrEmpty()]
              [string]$Url,
              
              [Parameter(Mandatory=$true, Position=1)]
              [ValidateNotNullOrEmpty()]
              [string]$Token,
              
              [Parameter()]
              [switch]$UseSecretStore,
 
              [Parameter()]
              [switch]$Force
          )
          
          if ($UseSecretStore) {
              # Ensure SecretStore module is available and initialized
              if (-not (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable)) {
                  throw "Microsoft.PowerShell.SecretStore module is required when using -UseSecretStore"
              }
 
              # Store in SecretStore
              Set-Secret -Name "PSCompassOne_Url" -SecureStringValue ($Url | ConvertTo-SecureString -AsPlainText -Force)
              Set-Secret -Name "PSCompassOne_Token" -SecureStringValue ($Token | ConvertTo-SecureString -AsPlainText -Force)
          }
          else {
              # Store in session
              $script:PSCompassOneConfig = @{
                  Url = $Url
                  Token = $Token
              }
          }
 
          Write-Verbose "PSCompassOne configuration updated successfully"
      }
 
      function Get-PSCompassOneConfiguration {
          [CmdletBinding()]
          param(
              [Parameter()]
              [switch]$UseSecretStore
          )
          
          if ($UseSecretStore) {
              # Retrieve from SecretStore
              try {
                  $url = (Get-Secret -Name "PSCompassOne_Url" -AsPlainText)
                  $token = (Get-Secret -Name "PSCompassOne_Token" -AsPlainText)
              }
              catch {
                  Write-Warning "Unable to retrieve configuration from SecretStore"
                  return $null
              }
 
              return @{
                  Url = $url
                  Token = $token
              }
          }
          else {
              # Return session configuration
              return $script:PSCompassOneConfig
          }
      }
 
      function Remove-PSCompassOneConfiguration {
          [CmdletBinding(SupportsShouldProcess=$true)]
          param(
              [Parameter()]
              [switch]$UseSecretStore
          )
          
          if ($UseSecretStore) {
              if ($PSCmdlet.ShouldProcess("SecretStore", "Remove PSCompassOne configuration")) {
                  Remove-Secret -Name "PSCompassOne_Url" -ErrorAction SilentlyContinue
                  Remove-Secret -Name "PSCompassOne_Token" -ErrorAction SilentlyContinue
              }
          }
          else {
              if ($PSCmdlet.ShouldProcess("Session", "Remove PSCompassOne configuration")) {
                  $script:PSCompassOneConfig = $null
              }
          }
      }
      ```

2. API Headers and Requests
    - Must include required headers for all requests

```powershell
# Example of standard header construction
$headers = @{
    'Accept' = 'application/json'
    'Content-Type' = 'application/json'
    'key' = $token
}
```

3. Response Handling
   - Must return PowerShell objects (not raw JSON)
   - Must support PowerShell pipeline operations

Example output processing:

```powershell
     function Get-Asset {
         [CmdletBinding()]
         param(
             [Parameter(Position=0)]
             [string]$Id
         )
         
         $response = Invoke-RestMethod -Uri $uri -Headers $headers
         
         # Convert response to PSCustomObject if needed
         if ($response -is [string]) {
             $response = $response | ConvertFrom-Json
         }
         
         # Add type information for better pipeline handling
         $response | ForEach-Object {
             $_ | Add-Member -MemberType NoteProperty -Name PSTypeName -Value 'PSCompassOne.Asset' -PassThru
         }
     }
```

#### Input Handling

1. JSON Input Support
   - Must accept JSON input as string or file path

   - Must support both positional and named parameters for JSON input

   - Example:

     ```powershell
     function New-Asset {
         [CmdletBinding()]
         param(
             [Parameter(Position=0, ValueFromPipeline=$true)]
             [string]$Data
         )
         
         # Check if input is a file path
         if (Test-Path $Data) {
             $Data = Get-Content $Data -Raw
         }
         
         # Validate JSON
         try {
             $null = $Data | ConvertFrom-Json
         }
         catch {
             throw "Invalid JSON input: $_"
         }
         
         # Process the request
         $uri = "$BaseUrl/v1/assets"
         Invoke-RestMethod -Uri $uri -Method Post -Body $Data -Headers $headers
     }
     ```

## Technical Requirements

### Development Environment

- PowerShell 7.0 or higher (required for modern PowerShell features)
- Visual Studio Code with PowerShell extension
- .NET SDK 6.0 or higher (for potential compiled cmdlets)
- Git for version control
- PowerShell modules:
  - PSScriptAnalyzer (for linting)
  - Pester 5.0+ (for testing)
  - platyPS (for help documentation)
  - Microsoft.PowerShell.SecretStore (for secure configuration storage)

### Performance Requirements

- Commands should complete within reasonable timeframes (\< 2s for simple operations)
- Should handle large result sets efficiently using pagination
- Memory usage should be optimized for pipeline operations
- Should support background jobs for long-running operations

### Security Requirements

- Must support secure token storage via SecretStore
- Must not log sensitive information
- Must use secure string for token handling
- Must validate all API inputs
- Must handle HTTPS connections only
- Must follow PowerShell security best practices:
  - No plain text passwords
  - No global variables
  - Proper scope usage
  - Credential parameter handling

### Compatibility Requirements

- Must work on:
  - Windows PowerShell 5.1 (minimum)
  - PowerShell 7.0+ (recommended)
  - Windows, Linux, macOS
- Must support common PowerShell hosting environments:
  - Console
  - ISE
  - VS Code
  - Azure Automation
  - AWS Systems Manager

### Integration Requirements

- Must provide proper pipeline support
- Must support standard PowerShell output streams
- Must integrate with standard PowerShell error handling
- Must support PowerShell logging mechanisms
- Must follow standard module auto-loading

## Business Requirements

### Access & Authentication

- Users must obtain API key from CompassOne platform
- Module must support:
  - Direct API key input
  - Environment variable configuration
  - Secure key storage via SecretStore
- Authentication errors must provide clear, actionable messages
- Token renewal/refresh process must be documented

### Business Rules

1. Data Handling

   - All dates must be in ISO 8601 format
   - All IDs must be treated as strings
   - All boolean flags must accept PowerShell boolean values
   - All enums must use PowerShell validation sets

2. Error Management

   - Business logic errors must be clearly distinguished from technical errors
   - Rate limiting must be handled gracefully
   - Retry logic must be implemented for transient failures
   - Error messages must be user-actionable

3. Audit & Logging

   - All configuration changes must be logged
   - All API calls must be traceable (with -Verbose)
   - All error conditions must be properly recorded
   - Sensitive data must never be logged

4. Resource Management

   - Connections must be properly disposed
   - Long-running operations must be cancelable
   - Memory usage must be managed for large datasets
   - Concurrent operations must be handled safely

## Implementation Priorities

### High Priority (MVP)

1. Core API Integration

   - Basic authentication
   - Essential CRUD operations
   - Error handling
   - Help documentation

2. PowerShell Standards

   - Proper command naming
   - Parameter validation
   - Pipeline support
   - Common parameters

### Medium Priority

1. Enhanced Features

   - Advanced filtering
   - Batch operations
   - Output formatting
   - Progress reporting

2. Development Support

   - Unit tests
   - Integration tests
   - Code coverage
   - Static analysis

### Lower Priority

1. Additional Features

   - Caching
   - Offline mode
   - Custom formatters
   - Additional output formats

2. Performance Optimizations

   - Connection pooling
   - Parallel operations
   - Memory optimization
   - Response compression

### Lowest Priority

1. Nice-to-Have Features
   - GUI tools
   - Additional authentication methods
   - Custom report generation
   - Integration with other tools

## User Experience Requirements

### Command Operation Modes

1. Interactive Mode

   - Should provide clear prompts
   - Should offer confirmation for destructive operations
   - Should support tab completion
   - Should provide verbose output when requested

2. Non-Interactive Mode

   - Should support silent operation
   - Should handle errors appropriately
   - Should support automation scenarios
   - Should provide consistent return codes

### Error Handling

1. User Errors

   - Clear error messages
   - Suggested corrections
   - Examples of correct usage
   - Links to documentation

2. System Errors

   - Technical details in verbose output
   - Appropriate error categories
   - Proper exception handling
   - Error record population

#### Code Quality and Testing

1. Unit Testing

   - Must use Pester for unit testing

   - Must achieve 100% code coverage

   - Must include mocked API calls

   - Example test structure:

     ```powershell
     Describe "Get-Asset" {
         BeforeAll {
             # Mock configuration and API calls
             Mock Get-PSCompassOneConfig { @{Url = "https://api.test"; Token = "test"} }
             Mock Invoke-RestMethod { @{id="123"; name="TestAsset"} }
         }
         
         It "Returns asset when ID is provided" {
             $result = Get-Asset -Id "123"
             $result.id | Should -Be "123"
             $result.name | Should -Be "TestAsset"
         }
         
         It "Uses correct URI for API call" {
             $null = Get-Asset -Id "123"
             Should -Invoke Invoke-RestMethod -ParameterFilter {
                 $Uri -eq "https://api.test/v1/assets/123"
             }
         }
     }
     ```

2. Code Style and Linting

   - Must use PSScriptAnalyzer with all default rules enabled

   - Must include custom PSScriptAnalyzer settings file

     ```powershell
         # PSScriptAnalyzerSettings.psd1
         @{
             Severity = @('Error', 'Warning')
             IncludeRules = @('*')
             ExcludeRules = @(
                 # Add any excluded rules here
             )
             Rules = @{
                 PSAvoidUsingCmdletAliases = @{
                     Enable = $true
                 }
                 PSUseDeclaredVarsMoreThanAssignments = @{
                     Enable = $true
                 }
             }
         }
     ```

   - Must include formatting settings in .editorconfig:

     ```ini
     [*.{ps1,psm1,psd1}]
     indent_style = space
     indent_size = 4
     end_of_line = crlf
     charset = utf-8
     trim_trailing_whitespace = true
     insert_final_newline = true
     ```

3. Documentation Requirements

   - Must include detailed README.md with:
     - Installation instructions
     - Configuration guide
     - Command reference
     - Examples for common scenarios
     - Troubleshooting guide
   - Must include CONTRIBUTING.md with:
     - Development setup instructions
     - Code style guidelines
     - Testing requirements
     - Pull request process

### Implementation Priorities

#### High Priority

1. Core module structure and installation capability
2. Basic authentication and configuration functionality
3. Implementation of primary API endpoints (assets, findings, incidents)
4. Help system integration
5. Pipeline support for all commands

#### Medium Priority

1. Complete unit test coverage
2. Detailed documentation
3. Advanced authentication methods (SecretStore integration)
4. Error handling and logging

#### Lower Priority

1. Performance optimizations
2. Additional convenience functions
3. Cross-platform testing
4. Advanced pipeline scenarios

#### Lowest Priority

1. Additional output formats
2. Caching mechanisms
3. Backward compatibility with older PowerShell versions
4. Integration with other security tools

## Technical Specifications

### Development Environment

- PowerShell 7.0 or higher
- Visual Studio Code with PowerShell extension
- Pester 5.0 or higher for testing
- PSScriptAnalyzer for linting

### Module File Structure

```
PSCompassOne/
├── src/                        # Source directory
│   ├── PSCompassOne.psd1      # Module manifest
│   ├── PSCompassOne.psm1      # Module script
│   ├── Public/                # Public functions
│   │   ├── Assets.ps1         # Asset management functions
│   │   ├── Findings.ps1       # Finding management functions
│   │   ├── Incidents.ps1      # Incident management functions
│   │   ├── Relationships.ps1  # Relationship management functions
│   │   └── Tags.ps1          # Tag management functions
│   └── Private/               # Private functions
│       ├── Invoke-ApiRequest.ps1  # API helper functions
│       └── Utils.ps1          # Utility functions
├── tests/                     # Test directory
│   ├── PSCompassOne.Tests.ps1 # Main test file
│   └── Unit/                  # Unit tests
│       ├── Assets.Tests.ps1   # Asset function tests
│       ├── Findings.Tests.ps1 # Finding function tests
│       └── Private.Tests.ps1  # Private function tests
├── docs/                      # Documentation
│   ├── en-US/                # Help files
│   │   ├── about_PSCompassOne.help.txt        # Module help
│   │   └── PSCompassOne-help.xml              # Command help
│   └── examples/              # Example scripts
├── .vscode/                   # VS Code settings
│   └── settings.json          # Editor settings
├── .github/                   # GitHub settings
│   └── workflows/             # GitHub Actions
│       ├── test.yml          # Testing workflow
│       └── publish.yml       # Gallery publishing workflow
├── .gitignore                # Git ignore file
├── PSScriptAnalyzerSettings.psd1  # Linting rules
├── build.ps1                 # Build script
└── README.md                 # Repository documentation
```

### Error Handling

#### Must implement custom error types:

```powershell
# Use PowerShell's native error handling with ErrorRecord
$errorCategory = [System.Management.Automation.ErrorCategory]::ConnectionError
$exception = [System.Net.WebException]::new("API request failed")
$errorId = 'PSCompassOneApiError'
$targetObject = $uri
$errorRecord = [System.Management.Automation.ErrorRecord]::new(
    $exception, 
    $errorId, 
    $errorCategory, 
    $targetObject
)
```

#### Example usage in functions:

```powershell
Write-Error -ErrorRecord $errorRecord
```

#### For terminating errors:

```powershell
$PSCmdlet.ThrowTerminatingError($errorRecord)
```

### Logging

- Must implement verbose logging.

#### Message Streams and Logging

```powershell
# Use PowerShell's built-in streams for different message types
# Example usage in functions:
Write-Verbose "Detailed information for troubleshooting"
Write-Debug "Internal state information for debugging"
Write-Warning "Warning message about potential issues"
Write-Error "Error message when something fails"
Write-Information "General informational message"

# Enable streams as needed:
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'
$InformationPreference = 'Continue'
```

### CRAFT API Swagger Specification

```json
{"openapi":"3.0.0","paths":{"/v1/assets":{"post":{"operationId":"AssetController_create","summary":"","description":"Create an asset of a given class","parameters":[],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateAssetRequestBodyDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"CONTAINER":"#/components/schemas/ContainerResponseDto","DEVICE":"#/components/schemas/DeviceResponseDto","FRAMEWORK":"#/components/schemas/FrameworkResponseDto","NETSTAT":"#/components/schemas/NetstatResponseDto","PERSON":"#/components/schemas/PersonResponseDto","PROCESS":"#/components/schemas/ProcessResponseDto","SERVICE":"#/components/schemas/ServiceResponseDto","SOFTWARE":"#/components/schemas/SoftwareResponseDto","SOURCE":"#/components/schemas/SourceResponseDto","SURVEY":"#/components/schemas/SurveyResponseDto","USER":"#/components/schemas/UserResponseDto"},"propertyName":"assetClass"},"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"} ],"title":"AssetResponseDto"}} }} },"tags":[ "asset" ] },"get":{"operationId":"AssetController_list","summary":"","description":"Get a list of assets of a given class","parameters":[ {"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"sortBy","required":false,"in":"query","schema":{"default":"name","enum":[ "assetClass","classification","criticality","foundOn","id","lastSeenOn","name","status" ],"type":"string"}},{"name":"sortOrder","required":false,"in":"query","schema":{"$ref":"#/components/schemas/OrderDirection"}},{"name":"withDeleted","required":false,"in":"query","schema":{"default":false,"type":"boolean"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListAssetsPaginatedResponseDto"}} }} },"tags":[ "asset" ] }},"/v1/assets/{id}":{"get":{"operationId":"AssetController_get","summary":"","description":"Get a single asset of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"CONTAINER":"#/components/schemas/ContainerResponseDto","DEVICE":"#/components/schemas/DeviceResponseDto","FRAMEWORK":"#/components/schemas/FrameworkResponseDto","NETSTAT":"#/components/schemas/NetstatResponseDto","PERSON":"#/components/schemas/PersonResponseDto","PROCESS":"#/components/schemas/ProcessResponseDto","SERVICE":"#/components/schemas/ServiceResponseDto","SOFTWARE":"#/components/schemas/SoftwareResponseDto","SOURCE":"#/components/schemas/SourceResponseDto","SURVEY":"#/components/schemas/SurveyResponseDto","USER":"#/components/schemas/UserResponseDto"},"propertyName":"assetClass"},"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"} ],"title":"AssetResponseDto"}} }} },"tags":[ "asset" ] },"patch":{"operationId":"AssetController_update","summary":"","description":"Update an asset of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateAssetRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"CONTAINER":"#/components/schemas/ContainerResponseDto","DEVICE":"#/components/schemas/DeviceResponseDto","FRAMEWORK":"#/components/schemas/FrameworkResponseDto","NETSTAT":"#/components/schemas/NetstatResponseDto","PERSON":"#/components/schemas/PersonResponseDto","PROCESS":"#/components/schemas/ProcessResponseDto","SERVICE":"#/components/schemas/ServiceResponseDto","SOFTWARE":"#/components/schemas/SoftwareResponseDto","SOURCE":"#/components/schemas/SourceResponseDto","SURVEY":"#/components/schemas/SurveyResponseDto","USER":"#/components/schemas/UserResponseDto"},"propertyName":"assetClass"},"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"} ],"title":"AssetResponseDto"}} }} },"tags":[ "asset" ] },"delete":{"operationId":"AssetController_delete","summary":"","description":"Soft deletes an asset of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"204":{"description":""}},"tags":[ "asset" ] }},"/v1/assets/{id}/tags":{"put":{"operationId":"AssetController_replaceTags","summary":"","description":"Replace all tags assigned to an asset","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/AssignTagsToAssetsRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"CONTAINER":"#/components/schemas/ContainerResponseDto","DEVICE":"#/components/schemas/DeviceResponseDto","FRAMEWORK":"#/components/schemas/FrameworkResponseDto","NETSTAT":"#/components/schemas/NetstatResponseDto","PERSON":"#/components/schemas/PersonResponseDto","PROCESS":"#/components/schemas/ProcessResponseDto","SERVICE":"#/components/schemas/ServiceResponseDto","SOFTWARE":"#/components/schemas/SoftwareResponseDto","SOURCE":"#/components/schemas/SourceResponseDto","SURVEY":"#/components/schemas/SurveyResponseDto","USER":"#/components/schemas/UserResponseDto"},"propertyName":"assetClass"},"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"} ],"title":"AssetResponseDto"}} }} },"tags":[ "asset" ] }},"/v1/findings":{"post":{"operationId":"FindingController_create","summary":"","description":"Create a finding of a given class","parameters":[],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateFindingRequestBodyDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"ALERT":"#/components/schemas/AlertResponseDto","EVENT":"#/components/schemas/EventResponseDto","INCIDENT":"#/components/schemas/IncidentResponseDto"},"propertyName":"findingClass"},"oneOf":[ {"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ],"title":"FindingResponseDto"}} }} },"tags":[ "finding" ] },"get":{"operationId":"FindingController_list","summary":"","description":"Get a list of findings of a given class","parameters":[ {"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"sortBy","required":false,"in":"query","schema":{"default":"name","enum":[ "findingClass","classification","criticality","foundOn","id","lastSeenOn","name","status" ],"type":"string"}},{"name":"sortOrder","required":false,"in":"query","schema":{"$ref":"#/components/schemas/OrderDirection"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListFindingsPaginatedResponseDto"}} }} },"tags":[ "finding" ] }},"/v1/findings/{id}":{"patch":{"operationId":"FindingController_update","summary":"","description":"Update a finding of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateFindingRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"ALERT":"#/components/schemas/AlertResponseDto","EVENT":"#/components/schemas/EventResponseDto","INCIDENT":"#/components/schemas/IncidentResponseDto"},"propertyName":"findingClass"},"oneOf":[ {"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ],"title":"FindingResponseDto"}} }} },"tags":[ "finding" ] },"get":{"operationId":"FindingController_get","summary":"","description":"Get a single finding of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"discriminator":{"mapping":{"ALERT":"#/components/schemas/AlertResponseDto","EVENT":"#/components/schemas/EventResponseDto","INCIDENT":"#/components/schemas/IncidentResponseDto"},"propertyName":"findingClass"},"oneOf":[ {"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ],"title":"FindingResponseDto"}} }} },"tags":[ "finding" ] },"delete":{"operationId":"FindingController_delete","summary":"","description":"Soft deletes a finding of a given class","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"204":{"description":""}},"tags":[ "finding" ] }},"/v1/incidents/{id}":{"get":{"operationId":"IncidentController_get","summary":"Get an incident by ID","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/IncidentResponseDto"}} }} },"tags":[ "incident" ] },"patch":{"operationId":"IncidentController_update","summary":"Update an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateIncidentRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/IncidentResponseDto"}} }} },"tags":[ "incident" ] },"delete":{"operationId":"IncidentController_delete","summary":"Delete an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":""}},"tags":[ "incident" ] }},"/v1/incidents":{"get":{"operationId":"IncidentController_list","summary":"List incidents","parameters":[ {"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"search","required":false,"in":"query","description":"Search string to query on all data from incidents","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListIncidentsPaginatedResponseDto"}} }} },"tags":[ "incident" ] },"post":{"operationId":"IncidentController_create","summary":"Create an incident","parameters":[],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateIncidentRequestBodyDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/IncidentResponseDto"}} }} },"tags":[ "incident" ] }},"/v1/incidents/{id}/notes":{"get":{"operationId":"IncidentController_getNotes","summary":"Retrieve the notes for an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}},{"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"withDeleted","required":false,"in":"query","schema":{"default":false,"type":"boolean"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListIncidentNotesPaginatedResponseDto"}} }} },"tags":[ "incident" ] },"post":{"operationId":"IncidentController_createNote","summary":"Create a note for an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateNoteForIncidentRequestBodyDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/IncidentNoteResponseDto"}} }},"default":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/IncidentNoteResponseDto"}} }} },"tags":[ "incident" ] }},"/v1/incidents/{id}/notes/{noteId}":{"delete":{"operationId":"IncidentController_deleteNote","summary":"Delete a note from an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}},{"name":"noteId","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":""}},"tags":[ "incident" ] }},"/v1/incidents/{id}/alerts":{"put":{"operationId":"IncidentController_putAlerts","summary":"Change the associated alerts of an incident","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateIncidentAlertsRequestBodyDto"}} }},"responses":{"200":{"description":""}},"tags":[ "incident" ] }},"/v1/notes/{id}":{"get":{"operationId":"NoteController_get","summary":"","description":"Get a note by ID.","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/NoteResponseDto"}} }} },"tags":[ "note" ] },"patch":{"operationId":"NoteController_update","summary":"","description":"Update a note with the given ID.","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateNoteRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/NoteResponseDto"}} }} },"tags":[ "note" ] },"delete":{"operationId":"NoteController_delete","summary":"","description":"Delete a note with the given ID.","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":""}},"tags":[ "note" ] }},"/v1/notes":{"get":{"operationId":"NoteController_list","summary":"","description":"Get a paginated list of notes.","parameters":[ {"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"withDeleted","required":false,"in":"query","schema":{"default":false,"type":"boolean"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListNotesPaginatedResponseDto"}} }} },"tags":[ "note" ] }},"/v1/relationships":{"post":{"operationId":"RelationshipController_createRelationship","parameters":[],"requestBody":{"required":true,"description":"The relationship to create.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipCreateRequestDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."},"default":{"description":"The relationship that was created,along with related data.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }} },"tags":[ "relationship" ] }},"/v1/relationships/{id}":{"get":{"operationId":"RelationshipController_getRelationship","parameters":[ {"name":"id","required":true,"in":"path","description":"The id of the relationship to retrieve.","schema":{"format":"uuid","type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."},"default":{"description":"The relationship with the given id.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }} },"tags":[ "relationship" ] },"patch":{"operationId":"RelationshipController_updateRelationship","parameters":[ {"name":"id","required":true,"in":"path","description":"The id of the entity to update.","schema":{"format":"uuid","type":"string"}} ],"requestBody":{"required":true,"description":"The updates to the relationship entity","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipUpdateRequestDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."},"default":{"description":"The relationship that was updated,along with related data.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipReadResponseWithRelatedDto"}} }} },"tags":[ "relationship" ] },"delete":{"operationId":"RelationshipController_deleteRelationship","parameters":[ {"name":"id","required":true,"in":"path","description":"The id of the entity to delete.","schema":{"format":"uuid","type":"string"}} ],"requestBody":{"required":true,"description":"The delete information for the relationship entity","content":{"application/json":{"schema":{"$ref":"#/components/schemas/RelationshipDeleteRequestDto"}} }},"responses":{"204":{"description":"Returned when the entity is deleted successfully"},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."}},"tags":[ "relationship" ] }},"/v1/relationships/asset/{id}/entities":{"get":{"operationId":"RelationshipController_listEntitiesRelatedToAsset","parameters":[ {"name":"id","required":true,"in":"path","description":"The id of the asset to retrieve related entities for.","schema":{"format":"uuid","type":"string"}},{"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"sortBy","required":false,"in":"query","schema":{"default":"name","enum":[ "classification","criticality","display_name","foundOn","id","lastSeenOn","model","name","status","type" ],"type":"string"}},{"name":"sortOrder","required":false,"in":"query","schema":{"$ref":"#/components/schemas/OrderDirection"}},{"name":"direction","required":true,"in":"query","schema":{"enum":[ "in","out" ],"type":"string"}},{"name":"model","required":false,"in":"query","schema":{"enum":[ "ASSET","FINDING" ],"type":"string"}},{"name":"class","required":false,"in":"query","schema":{"enum":[ "CONTAINER","DEVICE","FRAMEWORK","NETSTAT","PERSON","PROCESS","SERVICE","SOFTWARE","SOURCE","SURVEY","USER","ALERT","EVENT","INCIDENT" ],"type":"string"}},{"name":"type","required":false,"in":"query","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListAssetRelatedPaginatedResponseDto"}} }},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."},"default":{"description":"The list of related entities,plus pagination metadata.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListAssetRelatedPaginatedResponseDto"}} }} },"tags":[ "relationship" ] }},"/v1/relationships/finding/{id}/entities":{"get":{"operationId":"RelationshipController_listEntitiesRelatedToFinding","parameters":[ {"name":"id","required":true,"in":"path","description":"The id of the finding to retrieve related entities for.","schema":{"format":"uuid","type":"string"}},{"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"sortBy","required":false,"in":"query","schema":{"default":"name","enum":[ "classification","criticality","display_name","foundOn","id","lastSeenOn","model","name","status","type" ],"type":"string"}},{"name":"sortOrder","required":false,"in":"query","schema":{"$ref":"#/components/schemas/OrderDirection"}},{"name":"direction","required":false,"in":"query","schema":{"enum":[ "in","out" ],"type":"string"}},{"name":"model","required":false,"in":"query","schema":{"enum":[ "ASSET","FINDING" ],"type":"string"}},{"name":"class","required":false,"in":"query","schema":{"enum":[ "CONTAINER","DEVICE","FRAMEWORK","NETSTAT","PERSON","PROCESS","SERVICE","SOFTWARE","SOURCE","SURVEY","USER","ALERT","EVENT","INCIDENT" ],"type":"string"}},{"name":"type","required":false,"in":"query","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListFindingRelatedPaginatedResponseDto"}} }},"400":{"description":"The server could not understand the request due to invalid syntax."},"401":{"description":"Access to the resource is unauthorized."},"403":{"description":"Access to the resource is forbidden."},"404":{"description":"Resource not found."},"429":{"description":"Returned when the rate limit has been exceeded."},"500":{"description":"Returned when a server operation fails in an unexpected way."},"503":{"description":"Returned when the service is temporarily or expectedly unavailable."},"default":{"description":"The list of related entities,plus pagination metadata.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListFindingRelatedPaginatedResponseDto"}} }} },"tags":[ "relationship" ] }},"/v1/tags/{id}":{"get":{"operationId":"TagController_get","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TagResponseDto"}} }} },"tags":[ "tag" ] },"put":{"operationId":"TagController_update","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/UpdateTagRequestBodyDto"}} }},"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TagResponseDto"}} }} },"tags":[ "tag" ] },"delete":{"operationId":"TagController_delete","parameters":[ {"name":"id","required":true,"in":"path","schema":{"type":"string"}} ],"responses":{"200":{"description":""}},"tags":[ "tag" ] }},"/v1/tags":{"get":{"operationId":"TagController_list","parameters":[ {"name":"pageSize","required":false,"in":"query","description":"Max number of items to return from the database","schema":{"default":50,"type":"number"}},{"name":"page","required":false,"in":"query","description":"Number of database items to skip","schema":{"default":1,"type":"number"}},{"name":"search","required":false,"in":"query","description":"Search string to query on all data from tags","schema":{"type":"string"}} ],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ListTagsPaginatedResponseDto"}} }} },"tags":[ "tag" ] },"post":{"operationId":"TagController_create","parameters":[],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateTagRequestBodyDto"}} }},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TagResponseDto"}} }} },"tags":[ "tag" ] }} },"info":{"title":"craft-service-swagger","description":"Blackpoint craft service swagger spec and client","version":"0.0.19","contact":{}},"tags":[],"servers":[],"components":{"schemas":{"AssetTag":{"type":"object","properties":{"id":{"type":"string","description":"The unique ID of the tag that is applied to the asset."},"name":{"type":"string","description":"The name of the tag."},"customerId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"},"accountId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"},"createdBy":{"type":"string"},"createdOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true },"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "id","name","createdBy","createdOn" ] },"ContainerResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"CONTAINER"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"command":{"type":"string","nullable":true },"containerId":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"string"}},"imageTag":{"type":"string","nullable":true },"image":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"DeviceResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"DEVICE"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"byod":{"type":"boolean","nullable":true },"encrypted":{"type":"boolean","nullable":true },"fqdns":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareModel":{"type":"string","nullable":true },"hardwareVendor":{"type":"string","nullable":true },"hardwareVersion":{"type":"string","nullable":true },"hostname":{"type":"string","nullable":true },"platform":{"type":"string","nullable":true },"osName":{"type":"string","nullable":true },"osDetails":{"type":"string","nullable":true },"osVersion":{"type":"string","nullable":true },"ips":{"nullable":true,"type":"array","items":{"type":"string"}},"macs":{"nullable":true,"type":"array","items":{"type":"string"}},"osUpdatesEnabled":{"type":"boolean","nullable":true },"windowsDefenderEnabled":{"type":"boolean","nullable":true },"malwareProtected":{"type":"boolean","nullable":true },"publicIps":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareSerial":{"type":"string","nullable":true },"location":{"type":"string","nullable":true },"firewallEnabled":{"type":"boolean","nullable":true },"remoteAccessEnabled":{"type":"boolean","nullable":true },"screenLockEnabled":{"type":"boolean","nullable":true },"screenLockTimeout":{"type":"number","nullable":true,"minimum":0 }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"FrameworkResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"FRAMEWORK"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"compliance":{"type":"boolean","nullable":true },"security":{"type":"boolean","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"NetstatResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"NETSTAT"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"application":{"type":"string","nullable":true },"localAddress":{"type":"string","nullable":true },"offloadState":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"protocol":{"type":"string","nullable":true },"remoteAddress":{"type":"string","nullable":true },"user":{"type":"string","nullable":true },"state":{"type":"string","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"PersonResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PERSON"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"address":{"type":"string","nullable":true },"csuite":{"type":"boolean","nullable":true },"email":{"type":"string","nullable":true },"emailDomain":{"type":"string","nullable":true },"employeeType":{"type":"string","nullable":true },"lastName":{"type":"string","nullable":true },"middleName":{"type":"string","nullable":true },"firstName":{"type":"string","nullable":true },"employee":{"type":"boolean","nullable":true },"employeeId":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true },"title":{"type":"string","nullable":true },"phone":{"type":"string","nullable":true },"exitedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"ProcessResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PROCESS"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"excludedUser":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"ppid":{"type":"number","nullable":true,"minimum":0 },"userName":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"ServiceResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SERVICE"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"function":{"type":"string","nullable":true },"hosted":{"type":"boolean","nullable":true },"managed":{"type":"boolean","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"SoftwareResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOFTWARE"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"cots":{"type":"boolean","nullable":true },"fedramp":{"type":"boolean","nullable":true },"foss":{"type":"boolean","nullable":true },"function":{"type":"string","nullable":true },"version":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"number"}},"license":{"type":"string","nullable":true },"repoUrl":{"type":"string","nullable":true },"internal":{"type":"boolean","nullable":true },"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"hipaa":{"type":"boolean","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"SourceResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOURCE"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}} },"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"SurveyResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SURVEY"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"surveyId":{"type":"string"},"surveyedOn":{"format":"date-time","type":"string"},"surveyedBy":{"type":"string"}},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"UserResponseDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"USER"},"id":{"type":"string"},"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"email":{"type":"string"},"emailDomain":{"type":"string"},"username":{"type":"string"},"group":{"type":"string","nullable":true },"admin":{"type":"boolean","nullable":true },"mfaEnabled":{"type":"boolean","nullable":true },"mfaType":{"type":"boolean","nullable":true }},"required":[ "assetClass","id","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags","email","emailDomain","username" ] },"CreateContainerDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"CONTAINER"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"command":{"type":"string","nullable":true },"containerId":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"string"}},"imageTag":{"type":"string","nullable":true },"image":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateDeviceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"DEVICE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"byod":{"type":"boolean","nullable":true },"encrypted":{"type":"boolean","nullable":true },"fqdns":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareModel":{"type":"string","nullable":true },"hardwareVendor":{"type":"string","nullable":true },"hardwareVersion":{"type":"string","nullable":true },"hostname":{"type":"string","nullable":true },"platform":{"type":"string","nullable":true },"osName":{"type":"string","nullable":true },"osDetails":{"type":"string","nullable":true },"osVersion":{"type":"string","nullable":true },"ips":{"nullable":true,"type":"array","items":{"type":"string"}},"macs":{"nullable":true,"type":"array","items":{"type":"string"}},"osUpdatesEnabled":{"type":"boolean","nullable":true },"windowsDefenderEnabled":{"type":"boolean","nullable":true },"malwareProtected":{"type":"boolean","nullable":true },"publicIps":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareSerial":{"type":"string","nullable":true },"location":{"type":"string","nullable":true },"firewallEnabled":{"type":"boolean","nullable":true },"remoteAccessEnabled":{"type":"boolean","nullable":true },"screenLockEnabled":{"type":"boolean","nullable":true },"screenLockTimeout":{"type":"number","nullable":true,"minimum":0 }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateFrameworkDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"FRAMEWORK"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"compliance":{"type":"boolean","nullable":true },"security":{"type":"boolean","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateNetstatDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"NETSTAT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"application":{"type":"string","nullable":true },"localAddress":{"type":"string","nullable":true },"offloadState":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"protocol":{"type":"string","nullable":true },"remoteAddress":{"type":"string","nullable":true },"user":{"type":"string","nullable":true },"state":{"type":"string","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreatePersonDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PERSON"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"address":{"type":"string","nullable":true },"csuite":{"type":"boolean","nullable":true },"email":{"type":"string","nullable":true },"emailDomain":{"type":"string","nullable":true },"employeeType":{"type":"string","nullable":true },"lastName":{"type":"string","nullable":true },"middleName":{"type":"string","nullable":true },"firstName":{"type":"string","nullable":true },"employee":{"type":"boolean","nullable":true },"employeeId":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true },"title":{"type":"string","nullable":true },"phone":{"type":"string","nullable":true },"exitedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateProcessDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PROCESS"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"excludedUser":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"ppid":{"type":"number","nullable":true,"minimum":0 },"userName":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateServiceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SERVICE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"function":{"type":"string","nullable":true },"hosted":{"type":"boolean","nullable":true },"managed":{"type":"boolean","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateSoftwareDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOFTWARE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"cots":{"type":"boolean","nullable":true },"fedramp":{"type":"boolean","nullable":true },"foss":{"type":"boolean","nullable":true },"function":{"type":"string","nullable":true },"version":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"number"}},"license":{"type":"string","nullable":true },"repoUrl":{"type":"string","nullable":true },"internal":{"type":"boolean","nullable":true },"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"hipaa":{"type":"boolean","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateSourceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOURCE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}} },"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateSurveyDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SURVEY"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"surveyId":{"type":"string"},"surveyedBy":{"type":"string"},"surveyedOn":{"format":"date-time","type":"string"}},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags" ] },"CreateUserDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"USER"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"username":{"type":"string"},"email":{"type":"string"},"emailDomain":{"type":"string"},"group":{"type":"string","nullable":true },"admin":{"type":"boolean","nullable":true },"mfaEnabled":{"type":"boolean","nullable":true },"mfaType":{"type":"boolean","nullable":true }},"required":[ "assetClass","accountId","customerId","lastSeenOn","name","status","foundOn","tags","username","email","emailDomain" ] },"CreateAssetRequestBodyDto":{"type":"object","properties":{"asset":{"oneOf":[ {"$ref":"#/components/schemas/CreateContainerDto"},{"$ref":"#/components/schemas/CreateDeviceDto"},{"$ref":"#/components/schemas/CreateFrameworkDto"},{"$ref":"#/components/schemas/CreateNetstatDto"},{"$ref":"#/components/schemas/CreatePersonDto"},{"$ref":"#/components/schemas/CreateProcessDto"},{"$ref":"#/components/schemas/CreateServiceDto"},{"$ref":"#/components/schemas/CreateSoftwareDto"},{"$ref":"#/components/schemas/CreateSourceDto"},{"$ref":"#/components/schemas/CreateSurveyDto"},{"$ref":"#/components/schemas/CreateUserDto"} ] }},"required":[ "asset" ] },"PartialCreateContainerDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"CONTAINER"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"command":{"type":"string","nullable":true },"containerId":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"string"}},"imageTag":{"type":"string","nullable":true },"image":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass" ] },"PartialCreateDeviceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"DEVICE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"byod":{"type":"boolean","nullable":true },"encrypted":{"type":"boolean","nullable":true },"fqdns":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareModel":{"type":"string","nullable":true },"hardwareVendor":{"type":"string","nullable":true },"hardwareVersion":{"type":"string","nullable":true },"hostname":{"type":"string","nullable":true },"platform":{"type":"string","nullable":true },"osName":{"type":"string","nullable":true },"osDetails":{"type":"string","nullable":true },"osVersion":{"type":"string","nullable":true },"ips":{"nullable":true,"type":"array","items":{"type":"string"}},"macs":{"nullable":true,"type":"array","items":{"type":"string"}},"osUpdatesEnabled":{"type":"boolean","nullable":true },"windowsDefenderEnabled":{"type":"boolean","nullable":true },"malwareProtected":{"type":"boolean","nullable":true },"publicIps":{"nullable":true,"type":"array","items":{"type":"string"}},"hardwareSerial":{"type":"string","nullable":true },"location":{"type":"string","nullable":true },"firewallEnabled":{"type":"boolean","nullable":true },"remoteAccessEnabled":{"type":"boolean","nullable":true },"screenLockEnabled":{"type":"boolean","nullable":true },"screenLockTimeout":{"type":"number","nullable":true,"minimum":0 }},"required":[ "assetClass" ] },"PartialCreateFrameworkDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"FRAMEWORK"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"compliance":{"type":"boolean","nullable":true },"security":{"type":"boolean","nullable":true }},"required":[ "assetClass" ] },"PartialCreateNetstatDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"NETSTAT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"application":{"type":"string","nullable":true },"localAddress":{"type":"string","nullable":true },"offloadState":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"protocol":{"type":"string","nullable":true },"remoteAddress":{"type":"string","nullable":true },"user":{"type":"string","nullable":true },"state":{"type":"string","nullable":true }},"required":[ "assetClass" ] },"PartialCreatePersonDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PERSON"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"address":{"type":"string","nullable":true },"csuite":{"type":"boolean","nullable":true },"email":{"type":"string","nullable":true },"emailDomain":{"type":"string","nullable":true },"employeeType":{"type":"string","nullable":true },"lastName":{"type":"string","nullable":true },"middleName":{"type":"string","nullable":true },"firstName":{"type":"string","nullable":true },"employee":{"type":"boolean","nullable":true },"employeeId":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true },"title":{"type":"string","nullable":true },"phone":{"type":"string","nullable":true },"exitedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass" ] },"PartialCreateProcessDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"PROCESS"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"excludedUser":{"type":"string","nullable":true },"pid":{"type":"number","nullable":true,"minimum":0 },"ppid":{"type":"number","nullable":true,"minimum":0 },"userName":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"startedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "assetClass" ] },"PartialCreateServiceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SERVICE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"function":{"type":"string","nullable":true },"hosted":{"type":"boolean","nullable":true },"managed":{"type":"boolean","nullable":true }},"required":[ "assetClass" ] },"PartialCreateSoftwareDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOFTWARE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"cots":{"type":"boolean","nullable":true },"fedramp":{"type":"boolean","nullable":true },"foss":{"type":"boolean","nullable":true },"function":{"type":"string","nullable":true },"version":{"type":"string","nullable":true },"ports":{"nullable":true,"type":"array","items":{"type":"number"}},"license":{"type":"string","nullable":true },"repoUrl":{"type":"string","nullable":true },"internal":{"type":"boolean","nullable":true },"urls":{"nullable":true,"type":"array","items":{"type":"string"}},"hipaa":{"type":"boolean","nullable":true }},"required":[ "assetClass" ] },"PartialCreateSourceDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SOURCE"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}} },"required":[ "assetClass" ] },"PartialCreateSurveyDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"SURVEY"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"surveyId":{"type":"string"},"surveyedBy":{"type":"string"},"surveyedOn":{"format":"date-time","type":"string"}},"required":[ "assetClass" ] },"PartialCreateUserDto":{"type":"object","properties":{"assetClass":{"type":"string","default":"USER"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string"},"type":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}},"username":{"type":"string"},"email":{"type":"string"},"emailDomain":{"type":"string"},"group":{"type":"string","nullable":true },"admin":{"type":"boolean","nullable":true },"mfaEnabled":{"type":"boolean","nullable":true },"mfaType":{"type":"boolean","nullable":true }},"required":[ "assetClass" ] },"UpdateAssetRequestBodyDto":{"type":"object","properties":{"asset":{"oneOf":[ {"$ref":"#/components/schemas/CreateContainerDto"},{"$ref":"#/components/schemas/CreateDeviceDto"},{"$ref":"#/components/schemas/CreateFrameworkDto"},{"$ref":"#/components/schemas/CreateNetstatDto"},{"$ref":"#/components/schemas/CreatePersonDto"},{"$ref":"#/components/schemas/CreateProcessDto"},{"$ref":"#/components/schemas/CreateServiceDto"},{"$ref":"#/components/schemas/CreateSoftwareDto"},{"$ref":"#/components/schemas/CreateSourceDto"},{"$ref":"#/components/schemas/CreateSurveyDto"},{"$ref":"#/components/schemas/CreateUserDto"} ] }},"required":[ "asset" ] },"OrderDirection":{"type":"string","enum":[ "ASC","DESC" ] },"Asset":{"type":"object","properties":{"id":{"type":"string"},"assetClass":{"type":"string","enum":[ "CONTAINER","DEVICE","FRAMEWORK","NETSTAT","PERSON","PROCESS","SERVICE","SOFTWARE","SOURCE","SURVEY","USER" ] },"classification":{"type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"type":{"type":"string","nullable":true },"accountId":{"type":"string"},"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"updatedBy":{"type":"string","nullable":true },"model":{"type":"string"},"summary":{"type":"string","nullable":true },"status":{"type":"string"},"updatedOn":{"format":"date-time","type":"string","nullable":true },"tags":{"type":"array","items":{"$ref":"#/components/schemas/AssetTag"}} },"required":[ "id","assetClass","name","accountId","createdOn","customerId","foundOn","lastSeenOn","model","status","tags" ] },"PageMetaFieldsResponseConstraint":{"type":"object","properties":{"currentPage":{"type":"number","description":"The currently accessed page of results"},"totalItems":{"type":"number","description":"The total number of items available in the entire list"},"totalPages":{"type":"number","description":"The total number of pages containing all the items"},"pageSize":{"type":"number","description":"The max number of items returned in a single page."}},"required":[ "currentPage","totalItems","totalPages","pageSize" ] },"ListAssetsPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","discriminator":{"mapping":{"CONTAINER":"#/components/schemas/ContainerResponseDto","DEVICE":"#/components/schemas/DeviceResponseDto","FRAMEWORK":"#/components/schemas/FrameworkResponseDto","NETSTAT":"#/components/schemas/NetstatResponseDto","PERSON":"#/components/schemas/PersonResponseDto","PROCESS":"#/components/schemas/ProcessResponseDto","SERVICE":"#/components/schemas/ServiceResponseDto","SOFTWARE":"#/components/schemas/SoftwareResponseDto","SOURCE":"#/components/schemas/SourceResponseDto","SURVEY":"#/components/schemas/SurveyResponseDto","USER":"#/components/schemas/UserResponseDto"},"propertyName":"assetClass"},"type":"array","items":{"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"} ] }},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"AssignTagsToAssetsRequestBodyDto":{"type":"object","properties":{"tagIds":{"type":"array","items":{"type":"string"}} },"required":[ "tagIds" ] },"AlertResponseDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"ALERT"},"id":{"type":"string"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true },"impact":{"type":"string","nullable":true },"recommendation":{"type":"string","nullable":true },"score":{"type":"number","nullable":true },"severity":{"type":"string","nullable":true }},"required":[ "findingClass","id","accountId","createdOn","customerId","foundOn","lastSeenOn","model","name" ] },"EventResponseDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"EVENT"},"id":{"type":"string"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true },"action":{"type":"string","nullable":true },"dataset":{"type":"string","nullable":true },"eventCategory":{"type":"string","nullable":true },"eventType":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"kind":{"type":"string","nullable":true },"threatTacticId":{"type":"string","nullable":true },"threatTacticName":{"type":"string","nullable":true },"threatTechniqueId":{"type":"string","nullable":true },"threatTechniqueName":{"type":"string","nullable":true }},"required":[ "findingClass","id","accountId","createdOn","customerId","foundOn","lastSeenOn","model","name" ] },"IncidentResponseDto":{"type":"object","properties":{"accountId":{"type":"string"},"class":{"type":"string","default":"INCIDENT"},"classification":{"type":"string","nullable":true },"createdBy":{"type":"string"},"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"id":{"type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"ticketId":{"type":"string","nullable":true },"ticketUrl":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "accountId","class","createdBy","createdOn","customerId","foundOn","id","lastSeenOn","model","name","ticketId","ticketUrl" ] },"CreateAlertDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"ALERT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"impact":{"type":"string","nullable":true },"recommendation":{"type":"string","nullable":true },"score":{"type":"number","nullable":true },"severity":{"type":"string","nullable":true }},"required":[ "findingClass","accountId","customerId","foundOn","lastSeenOn","model","name" ] },"CreateEventDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"EVENT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"action":{"type":"string","nullable":true },"dataset":{"type":"string","nullable":true },"eventCategory":{"type":"string","nullable":true },"eventType":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"kind":{"type":"string","nullable":true },"threatTacticId":{"type":"string","nullable":true },"threatTacticName":{"type":"string","nullable":true },"threatTechniqueId":{"type":"string","nullable":true },"threatTechniqueName":{"type":"string","nullable":true }},"required":[ "findingClass","accountId","customerId","foundOn","lastSeenOn","model","name" ] },"CreateFindingRequestBodyDto":{"type":"object","properties":{"finding":{"oneOf":[ {"$ref":"#/components/schemas/CreateAlertDto"},{"$ref":"#/components/schemas/CreateEventDto"} ] }},"required":[ "finding" ] },"PartialCreateAlertDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"ALERT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"impact":{"type":"string","nullable":true },"recommendation":{"type":"string","nullable":true },"score":{"type":"number","nullable":true },"severity":{"type":"string","nullable":true }},"required":[ "findingClass" ] },"PartialCreateEventDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"EVENT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"action":{"type":"string","nullable":true },"dataset":{"type":"string","nullable":true },"eventCategory":{"type":"string","nullable":true },"eventType":{"type":"string","nullable":true },"hash":{"type":"string","nullable":true },"kind":{"type":"string","nullable":true },"threatTacticId":{"type":"string","nullable":true },"threatTacticName":{"type":"string","nullable":true },"threatTechniqueId":{"type":"string","nullable":true },"threatTechniqueName":{"type":"string","nullable":true }},"required":[ "findingClass" ] },"PartialIncidentDto":{"type":"object","properties":{"findingClass":{"type":"string","default":"INCIDENT"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"ticketId":{"type":"string","nullable":true },"ticketUrl":{"type":"string","nullable":true }},"required":[ "findingClass" ] },"UpdateFindingRequestBodyDto":{"type":"object","properties":{"finding":{"oneOf":[ {"$ref":"#/components/schemas/CreateAlertDto"},{"$ref":"#/components/schemas/CreateEventDto"} ] }},"required":[ "finding" ] },"Finding":{"type":"object","properties":{"id":{"type":"string"},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"criticality":{"type":"number","nullable":true },"customerId":{"type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"findingClass":{"type":"string","enum":[ "ALERT","EVENT","INCIDENT" ] },"foundBy":{"type":"string","nullable":true },"foundOn":{"format":"date-time","type":"string"},"lastSeenBy":{"type":"string","nullable":true },"lastSeenOn":{"format":"date-time","type":"string"},"model":{"type":"string"},"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"type":{"type":"string","nullable":true },"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "id","accountId","createdOn","customerId","findingClass","foundOn","lastSeenOn","model","name" ] },"ListFindingsPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","discriminator":{"mapping":{"ALERT":"#/components/schemas/AlertResponseDto","EVENT":"#/components/schemas/EventResponseDto","INCIDENT":"#/components/schemas/IncidentResponseDto"},"propertyName":"findingClass"},"type":"array","items":{"oneOf":[ {"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ] }},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"ListIncidentsPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","type":"array","items":{"$ref":"#/components/schemas/IncidentResponseDto"}},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"CreateIncidentRequestBodyDto":{"type":"object","properties":{"alertsIds":{"description":"List of IDs of the alerts to assign to the incident","type":"array","items":{"type":"string"}},"accountId":{"type":"string"},"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"customerId":{"type":"string"},"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"foundBy":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"ticketId":{"type":"string","nullable":true },"ticketUrl":{"type":"string","nullable":true },"type":{"type":"string","nullable":true }},"required":[ "alertsIds","accountId","customerId","name","ticketId","ticketUrl" ] },"UpdateIncidentRequestBodyDto":{"type":"object","properties":{"classification":{"type":"string","nullable":true },"criticality":{"type":"number","nullable":true,"minimum":1,"maximum":10 },"description":{"type":"string","nullable":true },"displayName":{"type":"string","nullable":true },"lastSeenBy":{"type":"string","nullable":true },"name":{"type":"string"},"notes":{"type":"string","nullable":true },"production":{"type":"boolean","nullable":true },"status":{"type":"string","nullable":true },"summary":{"type":"string","nullable":true },"ticketId":{"type":"string","nullable":true },"ticketUrl":{"type":"string","nullable":true },"type":{"type":"string","nullable":true }},"required":[ "name","ticketId","ticketUrl" ] },"NoteAccess":{"type":"string","description":"The access level of the note","enum":[ "CUSTOMER","INTERNAL","PARTNER","SELF" ] },"IncidentNoteResponseDto":{"type":"object","properties":{"access":{"nullable":true,"$ref":"#/components/schemas/NoteAccess"},"text":{"type":"string","description":"The text of the note"},"accountId":{"type":"string","nullable":true },"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"customerId":{"type":"string","nullable":true },"id":{"type":"string"},"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "text","createdOn","id" ] },"ListIncidentNotesPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","type":"array","items":{"$ref":"#/components/schemas/IncidentNoteResponseDto"}},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"CreateNoteForIncidentRequestBodyDto":{"type":"object","properties":{"access":{"nullable":true,"$ref":"#/components/schemas/NoteAccess"},"text":{"type":"string","description":"The text of the note"},"accountId":{"type":"string","nullable":true },"customerId":{"type":"string","nullable":true }},"required":[ "text" ] },"UpdateIncidentAlertsRequestBodyDto":{"type":"object","properties":{"add":{"type":"array","items":{"type":"string"}},"remove":{"type":"array","items":{"type":"string"}} }},"NoteResponseDto":{"type":"object","properties":{"access":{"nullable":true,"$ref":"#/components/schemas/NoteAccess"},"text":{"type":"string","description":"The text of the note"},"accountId":{"type":"string","nullable":true },"createdBy":{"type":"string","nullable":true },"createdOn":{"format":"date-time","type":"string"},"customerId":{"type":"string","nullable":true },"id":{"type":"string"},"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "text","createdOn","id" ] },"ListNotesPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","type":"array","items":{"$ref":"#/components/schemas/NoteResponseDto"}},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"UpdateNoteRequestBodyDto":{"type":"object","properties":{"access":{"nullable":true,"$ref":"#/components/schemas/NoteAccess"},"text":{"type":"string","description":"The text of the note"},"updatedBy":{"type":"string","nullable":true }},"required":[ "text" ] },"relationshipStatus":{"type":"string","enum":[ "active","closed","inactive","open","suspended","terminated" ] },"relationshipType":{"type":"string","enum":[ "explicit","implicit" ] },"relationshipVerb":{"type":"string","enum":[ "connects","has" ] },"RelationshipCreateRequestDto":{"type":"object","properties":{"accountId":{"type":"string","format":"uuid"},"createdBy":{"type":"string","nullable":true,"format":"uuid"},"customerId":{"type":"string","format":"uuid"},"foundBy":{"type":"string","nullable":true,"format":"uuid"},"foundOn":{"format":"date-time","type":"string"},"fromId":{"type":"string"},"lastSeenBy":{"type":"string","nullable":true,"format":"uuid"},"lastSeenOn":{"format":"date-time","type":"string"},"status":{"nullable":true,"$ref":"#/components/schemas/relationshipStatus"},"toId":{"type":"string"},"type":{"nullable":true,"$ref":"#/components/schemas/relationshipType"},"verb":{"$ref":"#/components/schemas/relationshipVerb"},"weight":{"type":"integer","nullable":true,"minimum":0 }},"required":[ "accountId","customerId","foundOn","fromId","lastSeenOn","status","toId","verb" ] },"RelationshipReadResponseWithRelatedDto":{"type":"object","properties":{}},"RelationshipUpdateRequestDto":{"type":"object","properties":{"lastSeenBy":{"type":"string","nullable":true,"format":"uuid"},"lastSeenOn":{"format":"date-time","type":"string"},"status":{"nullable":true,"$ref":"#/components/schemas/relationshipStatus"},"type":{"nullable":true,"$ref":"#/components/schemas/relationshipType"},"updatedBy":{"type":"string","nullable":true,"format":"uuid"},"verb":{"$ref":"#/components/schemas/relationshipVerb"},"weight":{"type":"integer","nullable":true,"minimum":0 }},"required":[ "lastSeenOn","status","verb" ] },"RelationshipDeleteRequestDto":{"type":"object","properties":{"deletedBy":{"type":"string","nullable":true,"format":"uuid"}} },"ListAssetRelatedPaginatedResponseDto":{"type":"object","properties":{"data":{"type":"array","items":{"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"},{"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ] }},"meta":{"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"}},"required":[ "data","meta" ] },"ListFindingRelatedPaginatedResponseDto":{"type":"object","properties":{"data":{"type":"array","items":{"oneOf":[ {"$ref":"#/components/schemas/ContainerResponseDto"},{"$ref":"#/components/schemas/DeviceResponseDto"},{"$ref":"#/components/schemas/FrameworkResponseDto"},{"$ref":"#/components/schemas/NetstatResponseDto"},{"$ref":"#/components/schemas/PersonResponseDto"},{"$ref":"#/components/schemas/ProcessResponseDto"},{"$ref":"#/components/schemas/ServiceResponseDto"},{"$ref":"#/components/schemas/SoftwareResponseDto"},{"$ref":"#/components/schemas/SourceResponseDto"},{"$ref":"#/components/schemas/SurveyResponseDto"},{"$ref":"#/components/schemas/UserResponseDto"},{"$ref":"#/components/schemas/AlertResponseDto"},{"$ref":"#/components/schemas/EventResponseDto"},{"$ref":"#/components/schemas/IncidentResponseDto"} ] }},"meta":{"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"}},"required":[ "data","meta" ] },"TagResponseDto":{"type":"object","properties":{"name":{"type":"string"},"customerId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"},"accountId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"},"createdBy":{"type":"string"},"createdOn":{"format":"date-time","type":"string"},"deletedBy":{"type":"string","nullable":true },"deletedOn":{"format":"date-time","type":"string","nullable":true },"id":{"type":"string"},"updatedBy":{"type":"string","nullable":true },"updatedOn":{"format":"date-time","type":"string","nullable":true }},"required":[ "name","createdBy","createdOn","id" ] },"ListTagsPaginatedResponseDto":{"type":"object","properties":{"data":{"description":"Items returned from the database","type":"array","items":{"$ref":"#/components/schemas/TagResponseDto"}},"meta":{"description":"Pagination metadata","allOf":[ {"$ref":"#/components/schemas/PageMetaFieldsResponseConstraint"} ] }},"required":[ "data","meta" ] },"CreateTagRequestBodyDto":{"type":"object","properties":{"name":{"type":"string"},"customerId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"},"accountId":{"type":"string","description":"A tag must contain exactly one of either accountId or customerId"}},"required":[ "name" ] },"UpdateTagRequestBodyDto":{"type":"object","properties":{"name":{"type":"string"}},"required":[ "name" ] }} }}
```

```
```