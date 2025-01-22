using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules and functions
    . $PSScriptRoot/../../../Public/Finding/Get-Finding.ps1
    . $PSScriptRoot/../../../Private/Types/Finding.Types.ps1
    . $PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1

    # Helper function to create test findings
    function Initialize-TestFinding {
        param(
            [string]$Id = [Guid]::NewGuid().ToString(),
            [FindingClass]$Class = [FindingClass]::Alert,
            [FindingSeverity]$Severity = [FindingSeverity]::High,
            [FindingStatus]$Status = [FindingStatus]::New,
            [float]$Score = 8.0,
            [DateTime]$CreatedOn = [DateTime]::UtcNow.AddDays(-1),
            [DateTime]$LastUpdatedOn = [DateTime]::UtcNow
        )

        $finding = [Finding]::new("Test Finding", $Class, $Severity)
        $finding.Id = $Id
        $finding.Status = $Status
        $finding.Score = $Score
        $finding.CreatedOn = $CreatedOn
        $finding.UpdatedOn = $LastUpdatedOn
        return $finding
    }
}

Describe 'Get-Finding' {
    BeforeAll {
        # Setup common test data
        $testFinding = Initialize-TestFinding
        $testFindings = @(
            Initialize-TestFinding -Class Alert -Severity Critical
            Initialize-TestFinding -Class Event -Severity High
            Initialize-TestFinding -Class Vulnerability -Severity Medium
        )
    }

    Context 'Parameter Validation' {
        It 'Should throw when Id is null or empty' {
            { Get-Finding -Id $null } | Should -Throw
            { Get-Finding -Id '' } | Should -Throw
        }

        It 'Should throw when Id format is invalid' {
            { Get-Finding -Id 'invalid-id' } | Should -Throw
        }

        It 'Should throw when Class is not a valid FindingClass enum value' {
            { Get-Finding -Class 'InvalidClass' } | Should -Throw
        }

        It 'Should throw when Severity is not a valid FindingSeverity enum value' {
            { Get-Finding -Severity 'InvalidSeverity' } | Should -Throw
        }

        It 'Should throw when Status is not a valid FindingStatus enum value' {
            { Get-Finding -Status 'InvalidStatus' } | Should -Throw
        }

        It 'Should throw when PageSize is less than 1' {
            { Get-Finding -PageSize 0 } | Should -Throw
        }

        It 'Should throw when PageSize exceeds maximum allowed value' {
            { Get-Finding -PageSize 101 } | Should -Throw
        }

        It 'Should throw when Page is less than 1' {
            { Get-Finding -Page 0 } | Should -Throw
        }

        It 'Should throw when StartDate is later than EndDate' {
            $endDate = [DateTime]::UtcNow.AddDays(-1)
            $startDate = $endDate.AddDays(1)
            { Get-Finding -StartDate $startDate -EndDate $endDate } | Should -Throw
        }

        It 'Should throw when EndDate is in the future' {
            { Get-Finding -EndDate ([DateTime]::UtcNow.AddDays(1)) } | Should -Throw
        }

        It 'Should validate AssetId format' {
            { Get-Finding -AssetId 'invalid-uuid' } | Should -Throw
            { Get-Finding -AssetId '123e4567-e89b-12d3-a456-426614174000' } | Should -Not -Throw
        }
    }

    Context 'Get Finding By Id' {
        BeforeEach {
            Mock Invoke-CompassOneApi {
                return $testFinding
            }
        }

        It 'Should return single finding when valid Id is provided' {
            $result = Get-Finding -Id $testFinding.Id
            $result | Should -Not -BeNull
            $result.Id | Should -Be $testFinding.Id
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should throw ObjectNotFound when finding Id does not exist' {
            Mock Invoke-CompassOneApi { throw 'Not Found' }
            { Get-Finding -Id ([Guid]::NewGuid().ToString()) } | Should -Throw
        }

        It 'Should handle API authentication errors gracefully' {
            Mock Invoke-CompassOneApi { throw 'Unauthorized' }
            { Get-Finding -Id $testFinding.Id } | Should -Throw
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should handle API rate limit errors with retry' {
            Mock Invoke-CompassOneApi { throw 'Rate limit exceeded' }
            { Get-Finding -Id $testFinding.Id } | Should -Throw
            Should -Invoke Invoke-CompassOneApi -Times 3
        }

        It 'Should return cached finding when available' {
            Mock Get-CompassOneCache { return $testFinding }
            $result = Get-Finding -Id $testFinding.Id
            $result | Should -Not -BeNull
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It 'Should force refresh when Force parameter is used' {
            Mock Get-CompassOneCache { return $testFinding }
            $result = Get-Finding -Id $testFinding.Id -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }
    }

    Context 'Get Findings List' {
        BeforeEach {
            Mock Invoke-CompassOneApi {
                return @{
                    items = $testFindings
                    totalItems = $testFindings.Count
                    totalPages = 1
                }
            }
        }

        It 'Should return all findings when no filters provided' {
            $results = Get-Finding
            $results | Should -HaveCount $testFindings.Count
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should filter by Class correctly' {
            $results = Get-Finding -Class Alert
            $results | Should -Not -BeNull
            $results | Where-Object Class -eq Alert | Should -Not -BeNullOrEmpty
        }

        It 'Should filter by Severity correctly' {
            $results = Get-Finding -Severity High
            $results | Should -Not -BeNull
            $results | Where-Object Severity -eq High | Should -Not -BeNullOrEmpty
        }

        It 'Should filter by Status correctly' {
            $results = Get-Finding -Status New
            $results | Should -Not -BeNull
            $results | Where-Object Status -eq New | Should -Not -BeNullOrEmpty
        }

        It 'Should respect PageSize parameter' {
            $results = Get-Finding -PageSize 2
            $results | Should -HaveCount 2
        }

        It 'Should handle Page parameter correctly' {
            Mock Invoke-CompassOneApi {
                return @{
                    items = $testFindings[2..2]
                    totalItems = $testFindings.Count
                    totalPages = 2
                }
            }
            $results = Get-Finding -PageSize 2 -Page 2
            $results | Should -HaveCount 1
        }
    }

    Context 'Pipeline Support' {
        BeforeEach {
            Mock Invoke-CompassOneApi {
                return $testFinding
            }
        }

        It 'Should accept pipeline input for Id' {
            $ids = @($testFinding.Id, [Guid]::NewGuid().ToString())
            $results = $ids | Get-Finding
            $results | Should -Not -BeNull
            Should -Invoke Invoke-CompassOneApi -Times $ids.Count
        }

        It 'Should process multiple pipeline inputs correctly' {
            $findings = $testFindings | Get-Finding
            $findings | Should -HaveCount $testFindings.Count
        }

        It 'Should maintain object order in pipeline' {
            $orderedIds = $testFindings.Id
            $results = $orderedIds | Get-Finding
            $results.Id | Should -Be $orderedIds
        }
    }

    Context 'Performance and Resource Usage' {
        BeforeEach {
            Mock Invoke-CompassOneApi {
                Start-Sleep -Milliseconds 100
                return $testFinding
            }
        }

        It 'Should complete single finding retrieval within 2 seconds' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-Finding -Id $testFinding.Id
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It 'Should handle bulk retrieval efficiently' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-Finding -PageSize 50
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan 5000
        }

        It 'Should implement proper resource cleanup' {
            $memBefore = [System.GC]::GetTotalMemory($true)
            1..10 | ForEach-Object { Get-Finding -Id $testFinding.Id }
            [System.GC]::Collect()
            $memAfter = [System.GC]::GetTotalMemory($true)
            $memDiff = $memAfter - $memBefore
            $memDiff | Should -BeLessThan 1MB
        }
    }
}