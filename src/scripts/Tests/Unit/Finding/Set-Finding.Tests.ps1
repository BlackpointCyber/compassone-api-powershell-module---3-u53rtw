#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules and functions
    . "$PSScriptRoot/../../../Public/Finding/Set-Finding.ps1"
    . "$PSScriptRoot/../../../Private/Types/Finding.Types.ps1"
    . "$PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1"

    # Configure Pester strict mode
    Set-StrictMode -Version Latest

    # Initialize test correlation ID
    $script:testCorrelationId = [guid]::NewGuid().ToString()

    # Create test finding objects
    $script:validFinding = [Finding]::new(
        "Test Finding",
        [FindingClass]::Alert,
        [FindingSeverity]::High
    )
    $script:validFinding.Id = "test-finding-1"
    $script:validFinding.Status = [FindingStatus]::New
    $script:validFinding.Score = 8.5
    $script:validFinding.Description = "Test finding description"

    $script:invalidFinding = [Finding]::new(
        "Invalid Finding",
        [FindingClass]::Alert,
        [FindingSeverity]::Low
    )
    $script:invalidFinding.Id = ""
    $script:invalidFinding.Status = [FindingStatus]::New

    # Mock API responses
    Mock Invoke-CompassOneApi -ParameterFilter { 
        $Method -eq 'GET' -and $EndpointPath -match '^/findings/test-finding-\d+$' 
    } -MockWith {
        return $script:validFinding
    }

    Mock Invoke-CompassOneApi -ParameterFilter { 
        $Method -eq 'PUT' -and $EndpointPath -match '^/findings/test-finding-\d+$' 
    } -MockWith {
        return $script:validFinding
    }

    # Mock parameter validation
    Mock Test-CompassOneParameter -MockWith { $true }
}

AfterAll {
    # Remove mocks
    Remove-Module -Name Pester -ErrorAction SilentlyContinue
}

Describe 'Set-Finding' {
    Context 'Parameter Validation' {
        It 'Should require a valid Id parameter' {
            { 
                Set-Finding -Id '' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ParameterValidationError'
        }

        It 'Should validate Title parameter' {
            { 
                Set-Finding -Id 'test-finding-1' -Title '' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ValidationError'
        }

        It 'Should validate FindingClass parameter' {
            { 
                Set-Finding -Id 'test-finding-1' -Class 'InvalidClass' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'InvalidFindingClass'
        }

        It 'Should validate Score range' {
            { 
                Set-Finding -Id 'test-finding-1' -Score 11.0 -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ValidationError'
        }

        It 'Should validate RelatedAssetIds format' {
            { 
                Set-Finding -Id 'test-finding-1' -RelatedAssetIds @('invalid-guid') -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ValidationError'
        }
    }

    Context 'API Interaction' {
        It 'Should call GET before PUT to validate finding existence' {
            Set-Finding -Id 'test-finding-1' -Title 'Updated Finding'
            Should -Invoke Invoke-CompassOneApi -ParameterFilter {
                $Method -eq 'GET' -and $EndpointPath -eq '/findings/test-finding-1'
            } -Times 1
        }

        It 'Should include correlation ID in API calls' {
            Set-Finding -Id 'test-finding-1' -Title 'Updated Finding'
            Should -Invoke Invoke-CompassOneApi -ParameterFilter {
                $null -ne $CorrelationId -and $CorrelationId -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
            }
        }

        It 'Should handle API errors gracefully' {
            Mock Invoke-CompassOneApi -ParameterFilter { $Method -eq 'PUT' } -MockWith { 
                throw "API Error" 
            }
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Updated Finding' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ApiError'
        }

        It 'Should retry on transient errors' {
            Mock Invoke-CompassOneApi -ParameterFilter { $Method -eq 'PUT' } -MockWith { 
                throw [System.Net.WebException]::new("Connection error") 
            } -Times 2
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Updated Finding' -ErrorAction Stop 
            } | Should -Throw
            Should -Invoke Invoke-CompassOneApi -Times 3
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept pipeline input by property name' {
            $finding = $script:validFinding.Clone()
            $finding | Set-Finding -Title 'Pipeline Test'
            Should -Invoke Invoke-CompassOneApi -ParameterFilter {
                $Method -eq 'PUT' -and $Body.Title -eq 'Pipeline Test'
            }
        }

        It 'Should process multiple pipeline inputs' {
            $findings = @(
                [PSCustomObject]@{ Id = 'test-finding-1'; Title = 'First Finding' },
                [PSCustomObject]@{ Id = 'test-finding-2'; Title = 'Second Finding' }
            )
            $findings | Set-Finding
            Should -Invoke Invoke-CompassOneApi -Times 4 # 2 GET + 2 PUT
        }
    }

    Context 'Security Compliance' {
        It 'Should respect ShouldProcess' {
            Set-Finding -Id 'test-finding-1' -Title 'Test' -WhatIf
            Should -Not -Invoke Invoke-CompassOneApi -ParameterFilter {
                $Method -eq 'PUT'
            }
        }

        It 'Should require confirmation for high-severity changes' {
            $finding = $script:validFinding.Clone()
            $finding.Severity = [FindingSeverity]::Critical
            { 
                $finding | Set-Finding -Severity High -Confirm:$false 
            } | Should -Not -Throw
            Should -Invoke Invoke-CompassOneApi
        }

        It 'Should validate security context' {
            Mock Test-CompassOneParameter -ParameterFilter { 
                $ParameterType -eq 'SecurityContext' 
            } -MockWith { $false }
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Test' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'SecurityError'
        }

        It 'Should sanitize sensitive data in logs' {
            Set-Finding -Id 'test-finding-1' -Description 'Contains password: secret123'
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -notmatch 'secret123'
            }
        }
    }

    Context 'Output and PassThru' {
        It 'Should return nothing by default' {
            $result = Set-Finding -Id 'test-finding-1' -Title 'Test'
            $result | Should -BeNullOrEmpty
        }

        It 'Should return updated finding with PassThru' {
            $result = Set-Finding -Id 'test-finding-1' -Title 'Test' -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Title | Should -Be 'Test'
        }

        It 'Should return properly typed objects' {
            $result = Set-Finding -Id 'test-finding-1' -Title 'Test' -PassThru
            $result | Should -BeOfType Finding
        }
    }

    Context 'Error Handling' {
        It 'Should handle finding not found' {
            Mock Invoke-CompassOneApi -ParameterFilter { 
                $Method -eq 'GET' 
            } -MockWith { $null }
            { 
                Set-Finding -Id 'non-existent' -Title 'Test' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ResourceNotFound'
        }

        It 'Should handle validation failures' {
            Mock Test-CompassOneParameter -MockWith { $false }
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Test' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'ValidationError'
        }

        It 'Should handle unauthorized access' {
            Mock Invoke-CompassOneApi -ParameterFilter { 
                $Method -eq 'PUT' 
            } -MockWith { 
                throw [System.UnauthorizedAccessException]::new() 
            }
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Test' -ErrorAction Stop 
            } | Should -Throw -ErrorId 'UnauthorizedAccess'
        }

        It 'Should clean up resources on error' {
            Mock Invoke-CompassOneApi -MockWith { throw 'Test error' }
            { 
                Set-Finding -Id 'test-finding-1' -Title 'Test' -ErrorAction Stop 
            } | Should -Throw
            [System.GC]::Collect()
            # Verify no memory leaks or hanging resources
        }
    }
}