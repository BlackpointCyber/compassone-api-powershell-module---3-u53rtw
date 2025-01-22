#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules and setup mocks
    . $PSScriptRoot/../../../Public/Incident/Remove-Incident.ps1
    . $PSScriptRoot/../../../Private/Types/Incident.Types.ps1

    # Mock API client
    Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne
    
    # Mock logging functions
    Mock -CommandName Write-CompassOneLog -ModuleName PSCompassOne
    Mock -CommandName Write-CompassOneError -ModuleName PSCompassOne

    # Create test data
    $script:testIncident = [Incident]::new(
        "Test Incident",
        [IncidentPriority]::P3,
        @("finding-123")
    )
    $script:testIncident.Status = [IncidentStatus]::Closed
    $script:testIncident.Id = "incident-123"
    $script:testIncident.TicketId = "TICKET-123"
}

Describe 'Remove-Incident' {
    Context 'Parameter Validation' {
        It 'Should throw on null Id' {
            { Remove-Incident -Id $null } | 
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'Should throw on empty Id' {
            { Remove-Incident -Id '' } | 
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'Should throw on invalid InputObject type' {
            { Remove-Incident -InputObject 'invalid' } | 
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'Should validate Id parameter from pipeline' {
            { 'incident-123' | Remove-Incident } | 
                Should -Not -Throw
        }

        It 'Should validate InputObject parameter from pipeline' {
            { $script:testIncident | Remove-Incident } | 
                Should -Not -Throw
        }
    }

    Context 'Successful Removal' {
        BeforeEach {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $EndpointPath -eq "/incidents/$($script:testIncident.Id)" -and $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $EndpointPath -eq "/incidents/$($script:testIncident.Id)" -and $Method -eq 'DELETE'
            } -MockWith { $true }
        }

        It 'Should call API with correct parameters' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke Invoke-CompassOneApi -ModuleName PSCompassOne -Times 1 -ParameterFilter {
                $EndpointPath -eq "/incidents/$($script:testIncident.Id)" -and $Method -eq 'DELETE'
            }
        }

        It 'Should log the removal operation' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke Write-CompassOneLog -ModuleName PSCompassOne -Times 2 -ParameterFilter {
                $Message -match 'Removing incident|Successfully removed incident'
            }
        }

        It 'Should handle successful response' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke Write-CompassOneError -ModuleName PSCompassOne -Times 0
        }

        It 'Should respect Force parameter' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke ShouldProcess -Times 0
        }
    }

    Context 'Pipeline Support' {
        BeforeEach {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'DELETE'
            } -MockWith { $true }
        }

        It 'Should accept pipeline input by value' {
            $script:testIncident | Remove-Incident -Force
            Should -Invoke Invoke-CompassOneApi -ModuleName PSCompassOne -Times 1 -ParameterFilter {
                $EndpointPath -eq "/incidents/$($script:testIncident.Id)" -and $Method -eq 'DELETE'
            }
        }

        It 'Should accept pipeline input by property name' {
            [PSCustomObject]@{ Id = $script:testIncident.Id } | Remove-Incident -Force
            Should -Invoke Invoke-CompassOneApi -ModuleName PSCompassOne -Times 1 -ParameterFilter {
                $EndpointPath -eq "/incidents/$($script:testIncident.Id)" -and $Method -eq 'DELETE'
            }
        }

        It 'Should handle multiple pipeline inputs' {
            $incidents = @(
                [PSCustomObject]@{ Id = 'incident-1' },
                [PSCustomObject]@{ Id = 'incident-2' }
            )
            $incidents | Remove-Incident -Force
            Should -Invoke Invoke-CompassOneApi -ModuleName PSCompassOne -Times 2 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent incident' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $null }

            { Remove-Incident -Id 'non-existent' -Force } | 
                Should -Throw -ErrorId 'ResourceNotFound*'
        }

        It 'Should handle invalid incident status' {
            $activeIncident = $script:testIncident.Clone()
            $activeIncident.Status = [IncidentStatus]::InProgress

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $activeIncident }

            { Remove-Incident -Id $activeIncident.Id -Force } | 
                Should -Throw -ErrorId 'InvalidOperation*'
        }

        It 'Should handle API errors' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'DELETE'
            } -MockWith { throw 'API Error' }

            { Remove-Incident -Id $script:testIncident.Id -Force } | 
                Should -Throw
        }

        It 'Should handle rate limiting' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'DELETE'
            } -MockWith { throw 'rate limit exceeded' }

            { Remove-Incident -Id $script:testIncident.Id -Force } | 
                Should -Throw -ErrorId '*8001'
        }
    }

    Context 'Security Controls' {
        BeforeEach {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'DELETE'
            } -MockWith { $true }
        }

        It 'Should require confirmation by default' {
            Mock -CommandName ShouldProcess -ModuleName PSCompassOne -MockWith { $false }
            Remove-Incident -Id $script:testIncident.Id
            Should -Invoke Invoke-CompassOneApi -ModuleName PSCompassOne -Times 0 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'Should bypass confirmation with Force' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke ShouldProcess -ModuleName PSCompassOne -Times 0
        }

        It 'Should log audit trail' {
            Remove-Incident -Id $script:testIncident.Id -Force
            Should -Invoke Write-CompassOneLog -ModuleName PSCompassOne -Times 2 -ParameterFilter {
                $Source -eq 'IncidentManagement'
            }
        }
    }

    Context 'Performance Tests' {
        BeforeEach {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'GET'
            } -MockWith { $script:testIncident }

            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne -ParameterFilter {
                $Method -eq 'DELETE'
            } -MockWith { $true }
        }

        It 'Should complete within timeout period' {
            $timeout = [System.Diagnostics.Stopwatch]::StartNew()
            Remove-Incident -Id $script:testIncident.Id -Force
            $timeout.Stop()
            $timeout.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It 'Should handle concurrent operations' {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    Remove-Incident -Id "incident-$_" -Force
                }
            }
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            $results.Count | Should -Be 5
        }

        It 'Should clean up resources' {
            [System.GC]::Collect()
            $initialMemory = [System.GC]::GetTotalMemory($true)
            1..10 | ForEach-Object {
                Remove-Incident -Id $script:testIncident.Id -Force
            }
            [System.GC]::Collect()
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryDiff = $finalMemory - $initialMemory
            $memoryDiff | Should -BeLessThan 1MB
        }
    }
}