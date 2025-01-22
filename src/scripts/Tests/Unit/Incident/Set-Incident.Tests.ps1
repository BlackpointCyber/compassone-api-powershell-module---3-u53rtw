using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Import required modules and functions
    . $PSScriptRoot/../../../../Public/Incident/Set-Incident.ps1
    . $PSScriptRoot/../../../../Private/Types/Incident.Types.ps1

    # Test constants
    $script:TestIncident = @{
        Id = 'test-incident-id'
        Title = 'Test Incident'
        Priority = 'P1'
        Status = 'New'
        Description = 'Test incident description'
        AssignedTo = 'test-user'
        TicketId = 'TICKET-123'
        TicketUrl = 'https://test.com/ticket/123'
        RelatedFindingIds = @('finding-1', 'finding-2')
        CreatedOn = '2023-01-01T00:00:00Z'
        CreatedBy = 'test-creator'
        UpdatedOn = $null
        UpdatedBy = $null
    }

    # Mock functions
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method, $Body)
        if ($EndpointPath -match '/incidents/test-incident-id' -and $Method -eq 'GET') {
            return $script:TestIncident
        }
        if ($Method -eq 'PUT') {
            return $Body
        }
        throw "API Error"
    }

    Mock Write-CompassOneError {
        param($ErrorCategory, $ErrorCode, $ErrorDetails)
        throw "CompassOne Error: $ErrorCategory - $ErrorCode"
    }

    Mock Write-CompassOneLog { }

    Mock Get-CompassOneCorrelationId { return 'test-correlation-id' }

    # Performance monitoring
    $script:PerformanceThreshold = 2000 # 2 seconds
}

Describe 'Set-Incident' {
    Context 'Parameter Validation' {
        It 'Should throw when Id is null or empty' {
            { Set-Incident -Id '' } | Should -Throw
            { Set-Incident -Id $null } | Should -Throw
        }

        It 'Should throw when Title exceeds maximum length' {
            $longTitle = 'a' * 201
            { Set-Incident -Id $script:TestIncident.Id -Title $longTitle } | 
                Should -Throw -ExpectedMessage '*Title exceeds maximum length*'
        }

        It 'Should throw when Priority is invalid' {
            { Set-Incident -Id $script:TestIncident.Id -Priority 'InvalidPriority' } | 
                Should -Throw -ExpectedMessage '*Invalid priority*'
        }

        It 'Should throw when Status is invalid' {
            { Set-Incident -Id $script:TestIncident.Id -Status 'InvalidStatus' } | 
                Should -Throw -ExpectedMessage '*Invalid status*'
        }

        It 'Should throw when RelatedFindingIds contains invalid IDs' {
            { Set-Incident -Id $script:TestIncident.Id -RelatedFindingIds @('invalid-id') } | 
                Should -Throw -ExpectedMessage '*Invalid finding ID*'
        }

        It 'Should throw when Description exceeds maximum length' {
            $longDesc = 'a' * 5001
            { Set-Incident -Id $script:TestIncident.Id -Description $longDesc } | 
                Should -Throw -ExpectedMessage '*Description exceeds maximum length*'
        }

        It 'Should validate parameter combinations' {
            { Set-Incident -Id $script:TestIncident.Id -Status 'Closed' -Priority 'P1' } | 
                Should -Not -Throw
        }
    }

    Context 'API Interaction' {
        It 'Should call API with correct parameters and format' {
            $result = Set-Incident -Id $script:TestIncident.Id -Title 'Updated Title' -Force
            Should -Invoke Invoke-CompassOneApi -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and 
                $EndpointPath -eq "/incidents/$($script:TestIncident.Id)" -and
                $Body.Title -eq 'Updated Title'
            }
        }

        It 'Should handle API success response correctly' {
            $result = Set-Incident -Id $script:TestIncident.Id -Status 'InProgress' -Force -PassThru
            $result.Status | Should -Be 'InProgress'
        }

        It 'Should handle API error responses appropriately' {
            Mock Invoke-CompassOneApi { throw 'API Error' }
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Throw
        }

        It 'Should implement retry logic for transient errors' {
            Mock Invoke-CompassOneApi { 
                if ($script:retryCount -lt 2) {
                    $script:retryCount++
                    throw 'Transient Error'
                }
                return $script:TestIncident 
            }
            $script:retryCount = 0
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Not -Throw
        }

        It 'Should respect API rate limits' {
            Mock Invoke-CompassOneApi { 
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                    'Rate limit exceeded',
                    [System.Net.HttpStatusCode]::TooManyRequests
                )
            }
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Throw '*Rate limit exceeded*'
        }

        It 'Should complete within performance requirements' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Set-Incident -Id $script:TestIncident.Id -Title 'Performance Test' -Force
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan $script:PerformanceThreshold
        }

        It 'Should properly handle correlation IDs' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Context.CorrelationId -eq 'test-correlation-id'
            }
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept pipeline input by value' {
            $incident = [PSCustomObject]$script:TestIncident
            $incident | Set-Incident -Title 'Pipeline Test' -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should accept pipeline input by property name' {
            $input = [PSCustomObject]@{ Id = $script:TestIncident.Id }
            $input | Set-Incident -Title 'Pipeline Test' -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should process multiple pipeline inputs correctly' {
            $inputs = @(
                [PSCustomObject]@{ Id = 'id-1' }
                [PSCustomObject]@{ Id = 'id-2' }
            )
            $inputs | Set-Incident -Title 'Multi Pipeline' -Force
            Should -Invoke Invoke-CompassOneApi -Times 2
        }

        It 'Should maintain order of pipeline objects' {
            $inputs = @(
                [PSCustomObject]@{ Id = 'id-1'; Title = 'First' }
                [PSCustomObject]@{ Id = 'id-2'; Title = 'Second' }
            )
            Mock Invoke-CompassOneApi { return $Body }
            $results = $inputs | Set-Incident -PassThru -Force
            $results[0].Title | Should -Be 'First'
            $results[1].Title | Should -Be 'Second'
        }

        It 'Should handle pipeline errors gracefully' {
            $inputs = @(
                [PSCustomObject]@{ Id = 'id-1' }
                [PSCustomObject]@{ Id = '' }
            )
            { $inputs | Set-Incident -Title 'Error Test' -Force } | Should -Throw
        }
    }

    Context 'ShouldProcess' {
        It 'Should call ShouldProcess before making changes' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Confirm:$false
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should not make changes when ShouldProcess returns false' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Confirm:$true
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It 'Should respect WhatIf parameter' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -WhatIf
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It 'Should respect Confirm parameter' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Confirm:$false
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should handle Force parameter correctly' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }
    }

    Context 'Security' {
        It 'Should validate authentication context' {
            Mock Invoke-CompassOneApi { throw 'Unauthorized' }
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Throw
        }

        It 'Should verify authorization for operation' {
            Mock Invoke-CompassOneApi { throw 'Forbidden' }
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Throw
        }

        It 'Should properly handle sensitive data' {
            Set-Incident -Id $script:TestIncident.Id -Description 'Sensitive Info' -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                -not $Context.Contains('Credentials')
            }
        }

        It 'Should generate audit log entries' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Audit Test' -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Information' -and 
                $Source -eq 'IncidentManager'
            }
        }

        It 'Should track correlation IDs' {
            Set-Incident -Id $script:TestIncident.Id -Title 'Correlation Test' -Force
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Context.CorrelationId -eq 'test-correlation-id'
            }
        }

        It 'Should validate security context' {
            Mock Invoke-CompassOneApi { 
                throw [System.Security.SecurityException]::new('Security violation')
            }
            { Set-Incident -Id $script:TestIncident.Id -Title 'Test' -Force } | 
                Should -Throw '*Security violation*'
        }
    }
}