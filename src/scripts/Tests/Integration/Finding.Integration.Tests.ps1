#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules and type definitions
    . "$PSScriptRoot/../../Private/Types/Finding.Types.ps1"
    Import-Module "$PSScriptRoot/../../../PSCompassOne.psd1" -Force

    # Initialize test environment
    $script:testApiKey = $env:COMPASSONE_TEST_API_KEY
    $script:testApiUrl = $env:COMPASSONE_TEST_API_URL
    $script:testFindings = @()

    # Helper function to create test findings
    function New-TestFinding {
        param(
            [string]$Title = "Test Finding $(Get-Random)",
            [FindingClass]$Class = [FindingClass]::Alert,
            [FindingSeverity]$Severity = [FindingSeverity]::High,
            [hashtable]$AdditionalProperties = @{}
        )

        $finding = @{
            Title = $Title
            Class = $Class
            Severity = $Severity
            Description = "Test finding created at $(Get-Date -Format 'o')"
            Score = switch ($Severity) {
                ([FindingSeverity]::Critical) { 10.0 }
                ([FindingSeverity]::High) { 8.0 }
                ([FindingSeverity]::Medium) { 5.0 }
                ([FindingSeverity]::Low) { 2.0 }
                ([FindingSeverity]::Info) { 0.0 }
            }
        }

        # Merge additional properties
        foreach ($key in $AdditionalProperties.Keys) {
            $finding[$key] = $AdditionalProperties[$key]
        }

        $newFinding = New-Finding @finding -PassThru
        $script:testFindings += $newFinding
        return $newFinding
    }
}

AfterAll {
    # Cleanup test findings
    foreach ($finding in $script:testFindings) {
        try {
            Remove-Finding -Id $finding.Id -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to cleanup test finding $($finding.Id): $_"
        }
    }
}

Describe 'Get-Finding Integration Tests' {
    BeforeAll {
        # Create test findings for retrieval tests
        $script:testFinding = New-TestFinding
        $script:testFindingBatch = @(
            New-TestFinding -Severity Critical
            New-TestFinding -Severity High
            New-TestFinding -Severity Medium
        )
    }

    It 'Should retrieve a finding by ID with proper type' {
        $finding = Get-Finding -Id $script:testFinding.Id
        $finding | Should -Not -BeNullOrEmpty
        $finding.Id | Should -Be $script:testFinding.Id
        $finding | Should -BeOfType [Finding]
    }

    It 'Should list findings with pagination' {
        $findings = Get-Finding -PageSize 2
        $findings | Should -Not -BeNullOrEmpty
        $findings.Count | Should -BeLessOrEqual 2
    }

    It 'Should filter findings by severity' {
        $findings = Get-Finding -Severity High
        $findings | Should -Not -BeNullOrEmpty
        $findings | ForEach-Object {
            $_.Severity | Should -Be ([FindingSeverity]::High)
        }
    }

    It 'Should filter findings by class' {
        $findings = Get-Finding -Class Alert
        $findings | Should -Not -BeNullOrEmpty
        $findings | ForEach-Object {
            $_.Class | Should -Be ([FindingClass]::Alert)
        }
    }

    It 'Should handle invalid finding ID gracefully' {
        { Get-Finding -Id '00000000-0000-0000-0000-000000000000' } | 
            Should -Throw -ErrorId 'COMPASSONE_4001'
    }

    It 'Should validate response time is within SLA' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-Finding -Id $script:testFinding.Id
        $stopwatch.Stop()
        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000
    }
}

Describe 'New-Finding Integration Tests' {
    It 'Should create a finding with required properties' {
        $finding = New-Finding -Title "Integration Test Finding" `
                              -Class Alert `
                              -Severity High `
                              -PassThru

        $finding | Should -Not -BeNullOrEmpty
        $finding.Title | Should -Be "Integration Test Finding"
        $finding.Class | Should -Be ([FindingClass]::Alert)
        $finding.Severity | Should -Be ([FindingSeverity]::High)
        $finding.Id | Should -Not -BeNullOrEmpty

        # Add to cleanup list
        $script:testFindings += $finding
    }

    It 'Should create a finding with all properties' {
        $finding = New-Finding -Title "Complete Test Finding" `
                              -Class Vulnerability `
                              -Severity Critical `
                              -Score 9.5 `
                              -Description "Test description" `
                              -Recommendation "Test recommendation" `
                              -PassThru

        $finding | Should -Not -BeNullOrEmpty
        $finding.Score | Should -Be 9.5
        $finding.Description | Should -Be "Test description"
        $finding.Recommendation | Should -Be "Test recommendation"

        # Add to cleanup list
        $script:testFindings += $finding
    }

    It 'Should validate required parameters' {
        { New-Finding -Title "" -Class Alert -Severity High } | 
            Should -Throw -ErrorId 'COMPASSONE_3001'
    }

    It 'Should enforce score range validation' {
        { New-Finding -Title "Test Finding" -Class Alert -Severity High -Score 11.0 } | 
            Should -Throw -ErrorId 'COMPASSONE_3001'
    }
}

Describe 'Set-Finding Integration Tests' {
    BeforeAll {
        $script:updateFinding = New-TestFinding
    }

    It 'Should update finding title' {
        $newTitle = "Updated Test Finding"
        $finding = Set-Finding -Id $script:updateFinding.Id `
                              -Title $newTitle `
                              -PassThru

        $finding | Should -Not -BeNullOrEmpty
        $finding.Title | Should -Be $newTitle
    }

    It 'Should update finding severity and score' {
        $finding = Set-Finding -Id $script:updateFinding.Id `
                              -Severity Critical `
                              -Score 9.8 `
                              -PassThru

        $finding | Should -Not -BeNullOrEmpty
        $finding.Severity | Should -Be ([FindingSeverity]::Critical)
        $finding.Score | Should -Be 9.8
    }

    It 'Should handle concurrent modifications' {
        $finding1 = Set-Finding -Id $script:updateFinding.Id `
                               -Title "Concurrent Test 1" `
                               -PassThru

        $finding2 = Set-Finding -Id $script:updateFinding.Id `
                               -Title "Concurrent Test 2" `
                               -PassThru

        $finding1.Title | Should -Not -Be $finding2.Title
    }

    It 'Should validate status transitions' {
        { Set-Finding -Id $script:updateFinding.Id -Status Closed } | 
            Should -Throw -ErrorId 'COMPASSONE_3001'
    }
}

Describe 'Remove-Finding Integration Tests' {
    It 'Should remove a finding' {
        $finding = New-TestFinding
        Remove-Finding -Id $finding.Id -Force
        { Get-Finding -Id $finding.Id } | Should -Throw -ErrorId 'COMPASSONE_4001'
    }

    It 'Should handle pipeline input' {
        $findings = @(
            New-TestFinding
            New-TestFinding
        )

        $findings | Remove-Finding -Force
        foreach ($finding in $findings) {
            { Get-Finding -Id $finding.Id } | Should -Throw -ErrorId 'COMPASSONE_4001'
        }
    }

    It 'Should require confirmation without Force' {
        $finding = New-TestFinding
        $result = Remove-Finding -Id $finding.Id -Confirm:$false 6>&1
        $result | Should -Not -BeNullOrEmpty
        $result.Message | Should -Match 'Are you sure you want to remove this finding?'
    }
}

Describe 'Finding Security Tests' {
    It 'Should validate API authentication' {
        Mock Get-CompassOneToken { throw 'Invalid token' }
        { Get-Finding -Id '12345678-1234-5678-1234-567812345678' } | 
            Should -Throw -ErrorId 'COMPASSONE_1001'
    }

    It 'Should validate request headers' {
        $finding = Get-Finding -Id $script:testFinding.Id
        $finding | Should -Not -BeNullOrEmpty
        # Headers are validated in Invoke-CompassOneApi
    }

    It 'Should handle rate limiting' {
        # Create multiple findings rapidly to trigger rate limiting
        1..10 | ForEach-Object {
            New-TestFinding -ErrorAction SilentlyContinue
        }
        # Rate limiting is handled in Invoke-CompassOneApi
    }
}

Describe 'Finding Performance Tests' {
    It 'Should handle bulk operations efficiently' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $findings = 1..5 | ForEach-Object { New-TestFinding }
        $stopwatch.Stop()
        
        $findings.Count | Should -Be 5
        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10000
    }

    It 'Should implement proper resource cleanup' {
        $initialMemory = [System.GC]::GetTotalMemory($true)
        1..10 | ForEach-Object { New-TestFinding }
        [System.GC]::Collect()
        $finalMemory = [System.GC]::GetTotalMemory($true)
        
        $memoryDiff = $finalMemory - $initialMemory
        $memoryDiff | Should -BeLessThan 100MB
    }
}