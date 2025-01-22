using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules and functions
    . $PSScriptRoot/../../../Public/Incident/Get-Incident.ps1
    . $PSScriptRoot/../../../Private/Types/Incident.Types.ps1

    # Initialize test data
    $script:testIncidents = @(
        @{
            id = 'test-incident-1'
            title = 'Critical Server Outage'
            status = 'New'
            priority = 'P1'
            assignedTo = 'admin'
            createdOn = '2024-01-15T10:00:00Z'
            lastModifiedOn = '2024-01-15T10:30:00Z'
            description = 'Production server outage'
            relatedFindingIds = @('finding-1', 'finding-2')
            ticketId = 'TICKET-001'
            ticketUrl = 'https://tickets.example.com/TICKET-001'
        },
        @{
            id = 'test-incident-2'
            title = 'Security Alert Investigation'
            status = 'InProgress'
            priority = 'P2'
            assignedTo = 'analyst'
            createdOn = '2024-01-15T09:00:00Z'
            lastModifiedOn = '2024-01-15T11:00:00Z'
            description = 'Investigating security alert'
            relatedFindingIds = @('finding-3')
            ticketId = 'TICKET-002'
            ticketUrl = 'https://tickets.example.com/TICKET-002'
        }
    )

    # Mock API client function
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method, $QueryParameters)
        
        if ($EndpointPath -match '/incidents/([^/]+)$') {
            $id = $Matches[1]
            $incident = $script:testIncidents | Where-Object { $_.id -eq $id }
            if (-not $incident) {
                throw [ItemNotFoundException]::new("Incident not found: $id")
            }
            return $incident
        }
        
        return @{
            items = $script:testIncidents
            totalCount = $script:testIncidents.Count
            pageSize = $QueryParameters.pageSize ?? 50
            page = $QueryParameters.page ?? 1
        }
    }

    # Mock error handling function
    Mock Write-CompassOneError {
        param($ErrorCategory, $ErrorCode, $ErrorDetails)
        throw [ErrorRecord]::new(
            [Exception]::new($ErrorDetails.Message),
            "COMPASSONE_$ErrorCode",
            $ErrorCategory,
            $null
        )
    }

    # Mock cache functions
    Mock Get-CompassOneCache { return $null }
    Mock Set-CompassOneCache { return $true }
    Mock Write-CompassOneLog { }
}

Describe 'Get-Incident' {
    Context 'Parameter Validation' {
        It 'Should validate Id parameter' {
            { Get-Incident -Id '' } | Should -Throw
            { Get-Incident -Id $null } | Should -Throw
        }

        It 'Should validate PageSize parameter' {
            { Get-Incident -PageSize 0 } | Should -Throw
            { Get-Incident -PageSize 101 } | Should -Throw
        }

        It 'Should validate Page parameter' {
            { Get-Incident -Page 0 } | Should -Throw
        }

        It 'Should validate Status parameter' {
            { Get-Incident -Status 'Invalid' } | Should -Throw
            { Get-Incident -Status 'New' } | Should -Not -Throw
        }

        It 'Should validate Priority parameter' {
            { Get-Incident -Priority 'Invalid' } | Should -Throw
            { Get-Incident -Priority 'High' } | Should -Not -Throw
        }
    }

    Context 'Single Incident Retrieval' {
        It 'Should retrieve a single incident by ID' {
            $result = Get-Incident -Id 'test-incident-1'
            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be 'test-incident-1'
            $result.Title | Should -Be 'Critical Server Outage'
            $result.PSObject.TypeNames[0] | Should -Be 'PSCompassOne.Incident'
        }

        It 'Should throw when incident is not found' {
            { Get-Incident -Id 'non-existent' } | Should -Throw
        }

        It 'Should use cache when available' {
            Mock Get-CompassOneCache { return [PSCustomObject]@{
                Id = 'test-incident-1'
                Title = 'Cached Incident'
            }}

            $result = Get-Incident -Id 'test-incident-1'
            $result.Title | Should -Be 'Cached Incident'
            Should -Invoke Get-CompassOneCache -Times 1
            Should -Invoke Invoke-CompassOneApi -Times 0
        }
    }

    Context 'Incident List Retrieval' {
        It 'Should retrieve all incidents with default parameters' {
            $result = Get-Incident
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSCompassOne.Incident'
        }

        It 'Should apply filtering by Status' {
            $result = Get-Incident -Status 'New'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'New'
        }

        It 'Should apply filtering by Priority' {
            $result = Get-Incident -Priority 'P1'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].Priority | Should -Be 'P1'
        }

        It 'Should handle pagination' {
            $result = Get-Incident -PageSize 1 -Page 1
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
        }

        It 'Should apply sorting' {
            $result = Get-Incident -SortBy 'CreatedOn' -SortOrder 'Ascending'
            $result | Should -Not -BeNullOrEmpty
            $result[0].CreatedOn | Should -BeLessThan $result[1].CreatedOn
        }
    }

    Context 'Error Handling' {
        It 'Should handle API errors gracefully' {
            Mock Invoke-CompassOneApi { throw 'API Error' }
            { Get-Incident } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1
        }

        It 'Should handle rate limiting' {
            Mock Invoke-CompassOneApi {
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                    'Rate limit exceeded',
                    [System.Net.HttpStatusCode]::TooManyRequests
                )
            }
            { Get-Incident } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1
        }

        It 'Should handle authentication errors' {
            Mock Invoke-CompassOneApi {
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                    'Unauthorized',
                    [System.Net.HttpStatusCode]::Unauthorized
                )
            }
            { Get-Incident } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1
        }
    }

    Context 'Performance' {
        It 'Should handle large result sets efficiently' {
            $largeDataSet = 1..100 | ForEach-Object {
                @{
                    id = "test-incident-$_"
                    title = "Test Incident $_"
                    status = 'New'
                    priority = 'P3'
                    createdOn = '2024-01-15T10:00:00Z'
                }
            }
            Mock Invoke-CompassOneApi {
                return @{
                    items = $largeDataSet
                    totalCount = $largeDataSet.Count
                    pageSize = 50
                    page = 1
                }
            }

            $result = Get-Incident
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 100
            $result | ForEach-Object {
                $_.PSObject.TypeNames[0] | Should -Be 'PSCompassOne.Incident'
            }
        }

        It 'Should clean up resources properly' {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            1..10 | ForEach-Object { Get-Incident }
            [System.GC]::Collect()
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryDiff = $finalMemory - $initialMemory
            $memoryDiff | Should -BeLessThan 1MB
        }
    }

    Context 'Raw Output' {
        It 'Should return raw API response when requested' {
            $result = Get-Incident -Raw
            $result | Should -Not -BeNullOrEmpty
            $result.items | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Not -Be 'PSCompassOne.Incident'
        }
    }
}