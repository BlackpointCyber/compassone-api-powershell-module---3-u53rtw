#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretManagement'; ModuleVersion='1.0.0' }

BeforeAll {
    # Import required modules
    Import-Module PSCompassOne -Force
    
    # Initialize test configuration
    $script:testConfig = @{
        ApiUrl = 'https://api.compassone.blackpoint.io'
        CorrelationId = [guid]::NewGuid().ToString()
        TestIncidents = @()
    }

    # Setup secure test credentials
    $script:testApiKey = $env:COMPASSONE_TEST_API_KEY
    if (-not $testApiKey) {
        throw "Test API key not found in environment variables"
    }

    # Connect to test environment
    Connect-CompassOne -ApiUrl $testConfig.ApiUrl -ApiKey $testApiKey

    # Initialize test data
    $script:testIncidents = @(
        @{
            Title = "Test Incident 1"
            Priority = [IncidentPriority]::P1
            Description = "Integration test incident 1"
            RelatedFindingIds = @()
        },
        @{
            Title = "Test Incident 2"
            Priority = [IncidentPriority]::P2
            Description = "Integration test incident 2"
            RelatedFindingIds = @()
        }
    )
}

AfterAll {
    # Cleanup test incidents
    foreach ($incident in $script:testConfig.TestIncidents) {
        try {
            Remove-Incident -Id $incident.Id -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to cleanup test incident $($incident.Id): $_"
        }
    }

    # Disconnect from test environment
    Disconnect-CompassOne
}

Describe 'Incident Management Integration Tests' {
    Context 'Incident Creation' {
        It 'Should create incident with valid parameters' {
            $incident = New-Incident -Title $testIncidents[0].Title `
                                   -Priority $testIncidents[0].Priority `
                                   -Description $testIncidents[0].Description `
                                   -PassThru

            $incident | Should -Not -BeNullOrEmpty
            $incident.Title | Should -Be $testIncidents[0].Title
            $incident.Priority | Should -Be $testIncidents[0].Priority
            $incident.Status | Should -Be ([IncidentStatus]::New)

            # Store for cleanup
            $script:testConfig.TestIncidents += $incident
        }

        It 'Should validate required parameters' {
            { New-Incident -Title "" -Priority P1 } | Should -Throw
            { New-Incident -Title "Test" -Priority "Invalid" } | Should -Throw
        }

        It 'Should support -WhatIf parameter' {
            $before = (Get-Incident).Count
            New-Incident -Title "WhatIf Test" -Priority P3 -WhatIf
            $after = (Get-Incident).Count
            $after | Should -Be $before
        }
    }

    Context 'Incident Retrieval' {
        BeforeAll {
            # Create test incident for retrieval tests
            $script:retrievalTest = New-Incident -Title $testIncidents[1].Title `
                                               -Priority $testIncidents[1].Priority `
                                               -Description $testIncidents[1].Description `
                                               -PassThru
            $script:testConfig.TestIncidents += $script:retrievalTest
        }

        It 'Should retrieve incident by ID' {
            $incident = Get-Incident -Id $retrievalTest.Id
            $incident | Should -Not -BeNullOrEmpty
            $incident.Id | Should -Be $retrievalTest.Id
            $incident.Title | Should -Be $retrievalTest.Title
        }

        It 'Should filter incidents by status' {
            $incidents = Get-Incident -Status New
            $incidents | Should -Not -BeNullOrEmpty
            $incidents | ForEach-Object { $_.Status | Should -Be ([IncidentStatus]::New) }
        }

        It 'Should handle not found errors' {
            { Get-Incident -Id "nonexistent" } | Should -Throw
        }

        It 'Should support pagination' {
            $page1 = Get-Incident -PageSize 1 -Page 1
            $page2 = Get-Incident -PageSize 1 -Page 2
            $page1[0].Id | Should -Not -Be $page2[0].Id
        }
    }

    Context 'Incident Updates' {
        BeforeAll {
            # Create test incident for update tests
            $script:updateTest = New-Incident -Title "Update Test" `
                                           -Priority P3 `
                                           -Description "Test incident for updates" `
                                           -PassThru
            $script:testConfig.TestIncidents += $script:updateTest
        }

        It 'Should update incident properties' {
            $updated = Set-Incident -Id $updateTest.Id `
                                  -Title "Updated Title" `
                                  -Priority P2 `
                                  -PassThru

            $updated | Should -Not -BeNullOrEmpty
            $updated.Title | Should -Be "Updated Title"
            $updated.Priority | Should -Be ([IncidentPriority]::P2)
        }

        It 'Should validate status transitions' {
            # Valid transition
            $updated = Set-Incident -Id $updateTest.Id `
                                  -Status InProgress `
                                  -PassThru
            $updated.Status | Should -Be ([IncidentStatus]::InProgress)

            # Invalid transition
            { Set-Incident -Id $updateTest.Id -Status Closed } | Should -Throw
        }

        It 'Should maintain audit trail' {
            $before = Get-Incident -Id $updateTest.Id
            Start-Sleep -Seconds 1
            
            $updated = Set-Incident -Id $updateTest.Id `
                                  -Description "Updated description" `
                                  -PassThru

            $updated.UpdatedOn | Should -BeGreaterThan $before.UpdatedOn
            $updated.UpdatedBy | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Incident Deletion' {
        BeforeAll {
            # Create test incident for deletion tests
            $script:deletionTest = New-Incident -Title "Deletion Test" `
                                             -Priority P4 `
                                             -Description "Test incident for deletion" `
                                             -PassThru
        }

        It 'Should require incident to be closed or resolved' {
            { Remove-Incident -Id $deletionTest.Id -Force } | Should -Throw
        }

        It 'Should successfully delete resolved incident' {
            Set-Incident -Id $deletionTest.Id -Status Resolved -Force
            { Remove-Incident -Id $deletionTest.Id -Force } | Should -Not -Throw
            { Get-Incident -Id $deletionTest.Id } | Should -Throw
        }

        It 'Should support -WhatIf parameter' {
            $incident = New-Incident -Title "WhatIf Deletion" -Priority P5 -PassThru
            Set-Incident -Id $incident.Id -Status Resolved -Force
            Remove-Incident -Id $incident.Id -WhatIf
            { Get-Incident -Id $incident.Id } | Should -Not -Throw
            Remove-Incident -Id $incident.Id -Force
        }
    }

    Context 'Error Handling' {
        It 'Should handle API errors gracefully' {
            Mock Invoke-CompassOneApi { throw "API Error" }
            { New-Incident -Title "Error Test" -Priority P1 } | Should -Throw
        }

        It 'Should handle timeout scenarios' {
            Mock Invoke-CompassOneApi { Start-Sleep -Seconds 31; return $null }
            { Get-Incident -Id "timeout-test" } | Should -Throw
        }

        It 'Should handle concurrent updates' {
            $incident = New-Incident -Title "Concurrency Test" -Priority P3 -PassThru
            $script:testConfig.TestIncidents += $incident

            $update1 = {
                Set-Incident -Id $incident.Id -Title "Update 1" -Priority P2
            }
            $update2 = {
                Set-Incident -Id $incident.Id -Title "Update 2" -Priority P1
            }

            $job1 = Start-Job -ScriptBlock $update1
            $job2 = Start-Job -ScriptBlock $update2

            Wait-Job -Job $job1, $job2 | Out-Null
            Receive-Job -Job $job1, $job2 -ErrorAction SilentlyContinue

            $final = Get-Incident -Id $incident.Id
            $final.UpdatedOn | Should -Not -BeNullOrEmpty
        }
    }
}