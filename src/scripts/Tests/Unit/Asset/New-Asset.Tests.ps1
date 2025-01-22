using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Pester # Version 5.0.0

BeforeAll {
    # Import required modules and functions
    $ProjectRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    . "$ProjectRoot/Public/Asset/New-Asset.ps1"
    . "$ProjectRoot/Private/Types/Asset.Types.ps1"
    . "$ProjectRoot/Private/Api/Invoke-CompassOneApi.ps1"

    # Test data setup
    $TestAsset = @{
        Name = "TestServer01"
        Class = "Device"
        Tags = @("Test", "Unit")
        Description = "Test asset for unit tests"
    }

    $ValidAssetClasses = @("Device", "Container", "Software", "Network", "Unknown")

    $ApiResponses = @{
        Success = @{
            id = "test-123"
            name = $TestAsset.Name
            class = $TestAsset.Class
            status = "Active"
            createdOn = [DateTime]::UtcNow.ToString('o')
            createdBy = "UnitTest"
        }
        Error = @{
            code = "error"
            message = "API Error"
        }
    }

    # Mock API calls
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method, $Body)
        if ($Method -eq "POST" -and $EndpointPath -eq "/assets") {
            return $ApiResponses.Success
        }
        throw "Invalid API call"
    }

    # Mock logging functions
    Mock Write-CompassOneLog { }
    Mock Write-CompassOneError { }
}

Describe "New-Asset" {
    Context "Parameter Validation" {
        It "Should require Name parameter" {
            { New-Asset -Class Device } | 
                Should -Throw -ErrorId "ParameterBindingException"
        }

        It "Should require Class parameter" {
            { New-Asset -Name "TestServer" } | 
                Should -Throw -ErrorId "ParameterBindingException"
        }

        It "Should validate Name format" {
            { New-Asset -Name "" -Class Device } | 
                Should -Throw
            { New-Asset -Name "   " -Class Device } | 
                Should -Throw
        }

        It "Should validate Class is from valid set" {
            foreach ($class in $ValidAssetClasses) {
                { New-Asset -Name "TestServer" -Class $class } | 
                    Should -Not -Throw
            }
            { New-Asset -Name "TestServer" -Class "Invalid" } | 
                Should -Throw
        }

        It "Should validate Tags array format" {
            { New-Asset -Name "TestServer" -Class Device -Tags @("") } | 
                Should -Throw
            { New-Asset -Name "TestServer" -Class Device -Tags @("Valid", "Tags") } | 
                Should -Not -Throw
        }

        It "Should validate Description length" {
            $longDesc = "a" * 1001
            { New-Asset -Name "TestServer" -Class Device -Description $longDesc } | 
                Should -Throw
        }
    }

    Context "Asset Creation" {
        It "Should create asset with minimum required parameters" {
            $result = New-Asset -Name $TestAsset.Name -Class $TestAsset.Class -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $TestAsset.Name
            $result.Class | Should -Be $TestAsset.Class
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It "Should create asset with all optional parameters" {
            $result = New-Asset -Name $TestAsset.Name `
                              -Class $TestAsset.Class `
                              -Tags $TestAsset.Tags `
                              -Description $TestAsset.Description `
                              -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Tags | Should -Be $TestAsset.Tags
            $result.Description | Should -Be $TestAsset.Description
        }

        It "Should respect WhatIf parameter" {
            New-Asset -Name $TestAsset.Name -Class $TestAsset.Class -WhatIf
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It "Should honor Confirm parameter" {
            # Mock confirmation response
            Mock $PSCmdlet.ShouldProcess { return $false }
            New-Asset -Name $TestAsset.Name -Class $TestAsset.Class -Confirm
            Should -Invoke Invoke-CompassOneApi -Times 0
        }
    }

    Context "Pipeline Support" {
        It "Should accept pipeline input by property name" {
            $pipelineInput = @(
                @{ Name = "Server01"; Class = "Device" }
                @{ Name = "Server02"; Class = "Device" }
            )
            $pipelineInput | New-Asset -PassThru | Should -HaveCount 2
            Should -Invoke Invoke-CompassOneApi -Times 2
        }

        It "Should process multiple pipeline inputs efficiently" {
            $pipelineInput = 1..10 | ForEach-Object {
                @{ Name = "Server$_"; Class = "Device" }
            }
            $start = Get-Date
            $pipelineInput | New-Asset
            $duration = (Get-Date) - $start
            $duration.TotalSeconds | Should -BeLessThan 30
        }

        It "Should maintain memory efficiency with large pipeline inputs" {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            $pipelineInput = 1..100 | ForEach-Object {
                @{ Name = "Server$_"; Class = "Device" }
            }
            $pipelineInput | New-Asset
            [System.GC]::Collect()
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryDiff = $finalMemory - $initialMemory
            $memoryDiff | Should -BeLessThan 100MB
        }
    }

    Context "Error Handling" {
        BeforeEach {
            Mock Invoke-CompassOneApi { throw "API Error" }
        }

        It "Should handle API errors gracefully" {
            { New-Asset -Name $TestAsset.Name -Class $TestAsset.Class } | 
                Should -Throw
            Should -Invoke Write-CompassOneError -Times 1
        }

        It "Should implement retry logic for transient errors" {
            Mock Invoke-CompassOneApi { 
                throw [System.Net.WebException]::new("Connection error")
            }
            { New-Asset -Name $TestAsset.Name -Class $TestAsset.Class } | 
                Should -Throw
            Should -Invoke Invoke-CompassOneApi -Times 3
        }

        It "Should handle rate limiting" {
            Mock Invoke-CompassOneApi { 
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                    "Rate limit exceeded",
                    [System.Net.HttpStatusCode]::TooManyRequests
                )
            }
            { New-Asset -Name $TestAsset.Name -Class $TestAsset.Class } | 
                Should -Throw
            Should -Invoke Write-CompassOneError -Times 1
        }
    }

    Context "Security Validation" {
        It "Should sanitize input parameters" {
            $unsafeInput = "<script>alert('xss')</script>"
            { New-Asset -Name $unsafeInput -Class Device } | 
                Should -Throw
        }

        It "Should validate authentication context" {
            Mock Test-CompassOneToken { return $false }
            { New-Asset -Name $TestAsset.Name -Class $TestAsset.Class } | 
                Should -Throw
        }

        It "Should prevent injection attacks" {
            $sqlInjection = "TestServer'; DROP TABLE Assets;--"
            { New-Asset -Name $sqlInjection -Class Device } | 
                Should -Throw
        }
    }

    Context "Performance" {
        It "Should complete operations within timeout" {
            $timeout = [TimeSpan]::FromSeconds(30)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            New-Asset -Name $TestAsset.Name -Class $TestAsset.Class
            $sw.Stop()
            $sw.Elapsed | Should -BeLessThan $timeout
        }

        It "Should handle concurrent requests" {
            $jobs = 1..5 | ForEach-Object {
                Start-Job {
                    New-Asset -Name "ConcurrentServer$_" -Class Device
                }
            }
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            $results | Should -HaveCount 5
        }

        It "Should clean up resources properly" {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            1..10 | ForEach-Object {
                New-Asset -Name "Server$_" -Class Device
            }
            [System.GC]::Collect()
            $finalMemory = [System.GC]::GetTotalMemory($true)
            ($finalMemory - $initialMemory) | Should -BeLessThan 50MB
        }
    }
}

AfterAll {
    # Clean up test data and mocks
    Remove-Variable -Name TestAsset -ErrorAction SilentlyContinue
    Remove-Variable -Name ValidAssetClasses -ErrorAction SilentlyContinue
    Remove-Variable -Name ApiResponses -ErrorAction SilentlyContinue
}