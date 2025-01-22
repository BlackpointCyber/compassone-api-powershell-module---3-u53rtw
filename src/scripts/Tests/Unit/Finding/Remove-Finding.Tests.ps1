using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required functions
    . $PSScriptRoot/../../../Public/Finding/Remove-Finding.ps1
    . $PSScriptRoot/../../../Private/Types/Finding.Types.ps1
    . $PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1

    # Test data
    $script:testFinding = [Finding]::new(
        "Test Finding",
        [FindingClass]::Alert,
        [FindingSeverity]::High
    )
    $script:testFinding.Id = "12345678-1234-5678-1234-567812345678"
    $script:testFinding.Status = [FindingStatus]::New

    # Mock Write-CompassOneLog to avoid actual logging
    Mock Write-CompassOneLog { }
}

Describe 'Remove-Finding' {
    BeforeEach {
        # Reset all mocks before each test
        Mock Invoke-CompassOneApi { }
        Mock Write-CompassOneError { }
        Mock Write-Error { }
    }

    Context 'Parameter Validation' {
        It 'Should throw when no parameters are provided' {
            { Remove-Finding } | Should -Throw
        }

        It 'Should throw when invalid Id format is provided' {
            { Remove-Finding -Id 'invalid-id' } | Should -Throw
            Should -Invoke Write-CompassOneError -ParameterFilter {
                $ErrorCategory -eq 'ValidationError' -and
                $ErrorCode -eq 3001
            }
        }

        It 'Should accept valid Finding Id' {
            Mock Invoke-CompassOneApi { $script:testFinding }
            { Remove-Finding -Id $script:testFinding.Id -Force } | Should -Not -Throw
        }

        It 'Should accept pipeline input by value' {
            Mock Invoke-CompassOneApi { $script:testFinding }
            { $script:testFinding | Remove-Finding -Force } | Should -Not -Throw
        }

        It 'Should accept pipeline input by property name' {
            Mock Invoke-CompassOneApi { $script:testFinding }
            { [PSCustomObject]@{ Id = $script:testFinding.Id } | Remove-Finding -Force } | Should -Not -Throw
        }
    }

    Context 'API Interaction' {
        BeforeEach {
            Mock Invoke-CompassOneApi { $script:testFinding } -ParameterFilter { 
                $Method -eq 'GET' 
            }
        }

        It 'Should call Invoke-CompassOneApi with correct endpoint and method' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Invoke-CompassOneApi -ParameterFilter {
                $EndpointPath -eq "/findings/$($script:testFinding.Id)" -and
                $Method -eq 'DELETE'
            }
        }

        It 'Should include correlation ID in API call' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Invoke-CompassOneApi -ParameterFilter {
                $PSBoundParameters.ContainsKey('CorrelationId')
            }
        }

        It 'Should handle 404 Not Found response' {
            Mock Invoke-CompassOneApi { throw 'Not Found' } -ParameterFilter { 
                $Method -eq 'GET' 
            }
            Remove-Finding -Id $script:testFinding.Id -Force -ErrorAction SilentlyContinue
            Should -Invoke Write-CompassOneError -ParameterFilter {
                $ErrorCategory -eq 'ResourceNotFound' -and
                $ErrorCode -eq 4001
            }
        }

        It 'Should handle unauthorized response' {
            Mock Invoke-CompassOneApi { throw 'Unauthorized' }
            Remove-Finding -Id $script:testFinding.Id -Force -ErrorAction SilentlyContinue
            Should -Invoke Write-CompassOneError
        }

        It 'Should handle server error response' {
            Mock Invoke-CompassOneApi { throw 'Internal Server Error' }
            Remove-Finding -Id $script:testFinding.Id -Force -ErrorAction SilentlyContinue
            Should -Invoke Write-CompassOneError
        }
    }

    Context 'ShouldProcess Implementation' {
        BeforeEach {
            Mock Invoke-CompassOneApi { $script:testFinding }
        }

        It 'Should prompt for confirmation without -Force' {
            Mock $PSCmdlet.ShouldProcess { $true }
            Remove-Finding -Id $script:testFinding.Id
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should not prompt for confirmation with -Force' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should not delete when confirmation is denied' {
            Mock $PSCmdlet.ShouldProcess { $false }
            Remove-Finding -Id $script:testFinding.Id
            Should -Invoke Invoke-CompassOneApi -Times 0 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'Audit Logging' {
        BeforeEach {
            Mock Invoke-CompassOneApi { $script:testFinding }
        }

        It 'Should log finding deletion attempt' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -match 'Starting finding removal operation'
            }
        }

        It 'Should log successful deletion' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -match 'Finding removed successfully'
            }
        }

        It 'Should log failed deletion' {
            Mock Invoke-CompassOneApi { throw 'Error' }
            Remove-Finding -Id $script:testFinding.Id -Force -ErrorAction SilentlyContinue
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Error'
            }
        }

        It 'Should include correlation ID in logs' {
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Context.ContainsKey('CorrelationId')
            }
        }
    }

    Context 'Resource Cleanup' {
        BeforeEach {
            Mock Invoke-CompassOneApi { $script:testFinding }
        }

        It 'Should clean up resources after successful deletion' {
            Mock [System.GC]::Collect { }
            Remove-Finding -Id $script:testFinding.Id -Force
            Should -Invoke ([System.GC]::Collect)
        }

        It 'Should clean up resources after failed deletion' {
            Mock [System.GC]::Collect { }
            Mock Invoke-CompassOneApi { throw 'Error' }
            Remove-Finding -Id $script:testFinding.Id -Force -ErrorAction SilentlyContinue
            Should -Invoke ([System.GC]::Collect)
        }
    }

    Context 'PassThru Parameter' {
        BeforeEach {
            Mock Invoke-CompassOneApi { $script:testFinding }
        }

        It 'Should return nothing without -PassThru' {
            $result = Remove-Finding -Id $script:testFinding.Id -Force
            $result | Should -BeNullOrEmpty
        }

        It 'Should return finding object with -PassThru' {
            $result = Remove-Finding -Id $script:testFinding.Id -Force -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be $script:testFinding.Id
        }
    }
}