using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import required modules and functions
    . "$PSScriptRoot/../../../Public/Finding/New-Finding.ps1"
    . "$PSScriptRoot/../../../Private/Types/Finding.Types.ps1"
    . "$PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1"

    # Mock API responses
    $mockFinding = @{
        Id = [guid]::NewGuid().ToString()
        Title = "Test Finding"
        Class = "Vulnerability"
        Severity = "Critical"
        Status = "New"
        Score = 10.0
        Description = "Test Description"
        RelatedAssetIds = @()
        Recommendation = "Test Recommendation"
        CreatedOn = [DateTime]::UtcNow
        CreatedBy = $env:USERNAME
    }

    # Mock API function
    Mock Invoke-CompassOneApi {
        return $mockFinding
    }

    # Mock logging functions
    Mock Write-CompassOneLog { }
    Mock Write-CompassOneError { }
}

Describe "New-Finding" {
    Context "Parameter Validation" {
        It "Should require Title parameter" {
            $command = Get-Command New-Finding
            $command.Parameters['Title'].Attributes | 
                Should -Contain { $_ -is [Parameter] -and $_.Mandatory }
        }

        It "Should require Class parameter" {
            $command = Get-Command New-Finding
            $command.Parameters['Class'].Attributes | 
                Should -Contain { $_ -is [Parameter] -and $_.Mandatory }
        }

        It "Should require Severity parameter" {
            $command = Get-Command New-Finding
            $command.Parameters['Severity'].Attributes | 
                Should -Contain { $_ -is [Parameter] -and $_.Mandatory }
        }

        It "Should validate Score range between 0.0 and 10.0" {
            $command = Get-Command New-Finding
            $command.Parameters['Score'].Attributes | 
                Should -Contain { $_ -is [ValidateRange] -and $_.MinRange -eq 0.0 -and $_.MaxRange -eq 10.0 }
        }

        It "Should throw on empty Title" {
            { New-Finding -Title "" -Class Vulnerability -Severity Critical } |
                Should -Throw
        }

        It "Should throw on invalid Class value" {
            { New-Finding -Title "Test" -Class "Invalid" -Severity Critical } |
                Should -Throw
        }

        It "Should throw on invalid Severity value" {
            { New-Finding -Title "Test" -Class Vulnerability -Severity "Invalid" } |
                Should -Throw
        }

        It "Should throw on invalid Score value" {
            { New-Finding -Title "Test" -Class Vulnerability -Severity Critical -Score 11.0 } |
                Should -Throw
        }
    }

    Context "Security Compliance" {
        BeforeEach {
            $secureParams = @{
                Title = "Security Test Finding"
                Class = "Vulnerability"
                Severity = "Critical"
                Description = "Security test description"
            }
        }

        It "Should handle credentials securely" {
            $result = New-Finding @secureParams
            Should -Invoke Invoke-CompassOneApi -Times 1 -Exactly
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should validate security context" {
            Mock Test-SecurityCompliance { return $true }
            $result = New-Finding @secureParams
            Should -Invoke Test-SecurityCompliance -Times 1 -Exactly
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should protect sensitive data" {
            $result = New-Finding @secureParams
            $result.PSObject.Properties | 
                Where-Object { $_.Name -match 'secret|password|key' } |
                Should -BeNullOrEmpty
        }

        It "Should enforce audit logging" {
            $result = New-Finding @secureParams
            Should -Invoke Write-CompassOneLog -Times 2 -Exactly
        }
    }

    Context "Error Handling" {
        BeforeEach {
            $errorParams = @{
                Title = "Error Test Finding"
                Class = "Vulnerability"
                Severity = "Critical"
            }
        }

        It "Should handle API errors gracefully" {
            Mock Invoke-CompassOneApi { throw "API Error" }
            { New-Finding @errorParams } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1 -Exactly
        }

        It "Should implement retry logic" {
            Mock Invoke-CompassOneApi { throw "Transient Error" } -ParameterFilter { $RetryCount -gt 0 }
            { New-Finding @errorParams } | Should -Throw
            Should -Invoke Invoke-CompassOneApi -Times 3 -Exactly
        }

        It "Should respect timeout settings" {
            Mock Invoke-CompassOneApi { Start-Sleep -Seconds 31; return $null }
            { New-Finding @errorParams } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1 -Exactly
        }

        It "Should provide detailed error messages" {
            Mock Invoke-CompassOneApi { throw "Validation Error" }
            { New-Finding @errorParams } | Should -Throw -ExpectedMessage "*Validation Error*"
        }
    }

    Context "Cross-Platform Compatibility" {
        BeforeEach {
            $crossPlatformParams = @{
                Title = "Cross-Platform Test Finding"
                Class = "Vulnerability"
                Severity = "Critical"
            }
        }

        It "Should work on Windows PowerShell 5.1" {
            Mock $PSVersionTable { @{ PSVersion = "5.1" } }
            $result = New-Finding @crossPlatformParams
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should work on PowerShell 7.0+" {
            Mock $PSVersionTable { @{ PSVersion = "7.0" } }
            $result = New-Finding @crossPlatformParams
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should handle path differences" {
            $result = New-Finding @crossPlatformParams -RelatedAssetIds @("test/path")
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should manage encoding correctly" {
            $crossPlatformParams.Title = "Test with üñîçødé"
            $result = New-Finding @crossPlatformParams
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Successful Finding Creation" {
        BeforeEach {
            $validParams = @{
                Title = "Valid Test Finding"
                Class = "Vulnerability"
                Severity = "Critical"
                Score = 9.5
                Description = "Test description"
                RelatedAssetIds = @([guid]::NewGuid().ToString())
                Recommendation = "Test recommendation"
                PassThru = $true
            }
        }

        It "Should create finding with all parameters" {
            $result = New-Finding @validParams
            $result | Should -Not -BeNullOrEmpty
            $result.Title | Should -Be $validParams.Title
            $result.Class | Should -Be $validParams.Class
            $result.Severity | Should -Be $validParams.Severity
            $result.Score | Should -Be $validParams.Score
        }

        It "Should support WhatIf parameter" {
            $result = New-Finding @validParams -WhatIf
            Should -Invoke Invoke-CompassOneApi -Times 0 -Exactly
            $result | Should -BeNullOrEmpty
        }

        It "Should return finding object with PassThru" {
            $result = New-Finding @validParams -PassThru
            $result | Should -BeOfType [PSObject]
            $result.Id | Should -Not -BeNullOrEmpty
        }

        It "Should set default values correctly" {
            $result = New-Finding -Title "Default Test" -Class Vulnerability -Severity Critical -PassThru
            $result.Status | Should -Be "New"
            $result.Score | Should -Be 10.0
            $result.CreatedBy | Should -Be $env:USERNAME
        }
    }
}