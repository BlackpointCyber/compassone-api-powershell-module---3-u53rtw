using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Pester, Microsoft.PowerShell.Security

BeforeAll {
    # Import required modules and mock dependencies
    $modulePath = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    . "$modulePath/Public/Incident/New-Incident.ps1"
    . "$modulePath/Private/Types/Incident.Types.ps1"

    # Mock API client functions
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method, $Body)
        $script:LastApiCall = @{
            EndpointPath = $EndpointPath
            Method = $Method
            Body = $Body
        }
        return [PSCustomObject]@{
            id = 'test-incident-id'
            title = $Body.title
            priority = $Body.priority
            status = 'New'
            createdOn = [DateTime]::UtcNow
        }
    }

    # Mock error handling
    Mock Write-CompassOneError {
        param($ErrorCategory, $ErrorCode, $ErrorDetails)
        throw "CompassOne Error [$ErrorCategory]: $($ErrorDetails.Message)"
    }

    # Mock logging
    Mock Write-CompassOneLog { }

    # Test data
    $script:ValidIncident = @{
        Title = "Test Critical Incident"
        Priority = [IncidentPriority]::P1
        Description = "Test incident description"
        RelatedFindingIds = @('finding-1', 'finding-2')
        AssignedTo = "test@domain.com"
        TicketId = "TICKET-123"
        TicketUrl = "https://tickets.example.com/123"
    }

    # Performance metrics
    $script:PerformanceThresholds = @{
        MaxResponseTime = 2000  # milliseconds
        MaxMemoryUsage = 100    # MB
    }
}

Describe 'New-Incident' {
    Context 'Parameter Validation' {
        It 'Should require Title parameter' {
            { New-Incident -Priority P1 } | 
                Should -Throw "*Parameter set cannot be resolved*"
        }

        It 'Should validate Title length' {
            $longTitle = "a" * 201
            { New-Incident -Title $longTitle -Priority P1 } |
                Should -Throw "*Title exceeds maximum length*"
        }

        It 'Should require valid Priority enum value' {
            { New-Incident -Title "Test" -Priority "Invalid" } |
                Should -Throw "*Cannot convert value*"
        }

        It 'Should validate AssignedTo email format' {
            { New-Incident -Title "Test" -Priority P1 -AssignedTo "invalid-email" } |
                Should -Throw "*ValidationError*"
        }

        It 'Should validate TicketUrl format' {
            { New-Incident -Title "Test" -Priority P1 -TicketUrl "invalid-url" } |
                Should -Throw "*ValidationError*"
        }

        It 'Should validate RelatedFindingIds format' {
            { New-Incident -Title "Test" -Priority P1 -RelatedFindingIds @("invalid-guid") } |
                Should -Throw "*ValidationError*"
        }

        It 'Should prevent XSS in Title' {
            { New-Incident -Title "<script>alert(1)</script>" -Priority P1 } |
                Should -Throw "*ValidationError*"
        }
    }

    Context 'API Integration' {
        It 'Should call API with correct endpoint and method' {
            New-Incident @script:ValidIncident
            $script:LastApiCall.EndpointPath | Should -Be "/incidents"
            $script:LastApiCall.Method | Should -Be "POST"
        }

        It 'Should properly serialize incident data' {
            New-Incident @script:ValidIncident
            $script:LastApiCall.Body | Should -Not -BeNullOrEmpty
            $script:LastApiCall.Body.title | Should -Be $script:ValidIncident.Title
            $script:LastApiCall.Body.priority | Should -Be $script:ValidIncident.Priority.ToString()
        }

        It 'Should handle API rate limits' {
            Mock Invoke-CompassOneApi { throw [HttpResponseException]::new(429) }
            { New-Incident @script:ValidIncident } | Should -Throw "*rate limit*"
        }

        It 'Should implement retry logic for failures' {
            $attempts = 0
            Mock Invoke-CompassOneApi {
                $attempts++
                if ($attempts -lt 3) { throw [HttpResponseException]::new(500) }
                return [PSCustomObject]@{ id = 'test-id' }
            }
            New-Incident @script:ValidIncident
            $attempts | Should -Be 3
        }

        It 'Should respect timeout settings' {
            $startTime = Get-Date
            New-Incident @script:ValidIncident
            $duration = (Get-Date) - $startTime
            $duration.TotalMilliseconds | Should -BeLessThan $script:PerformanceThresholds.MaxResponseTime
        }
    }

    Context 'Error Handling' {
        It 'Should write detailed error for invalid parameters' {
            { New-Incident -Title "" -Priority P1 } | 
                Should -Throw "*ValidationError*"
        }

        It 'Should handle API errors with proper context' {
            Mock Invoke-CompassOneApi { throw "API Error" }
            { New-Incident @script:ValidIncident } |
                Should -Throw "*CompassOne Error*"
        }

        It 'Should log security violations' {
            { New-Incident -Title "Test" -Priority P1 -TicketUrl "http://insecure.url" } |
                Should -Throw "*SecurityError*"
        }

        It 'Should handle timeout errors gracefully' {
            Mock Invoke-CompassOneApi { Start-Sleep -Seconds 3; throw "Timeout" }
            { New-Incident @script:ValidIncident } |
                Should -Throw "*timeout*"
        }

        It 'Should handle authentication failures' {
            Mock Invoke-CompassOneApi { throw [UnauthorizedAccessException]::new() }
            { New-Incident @script:ValidIncident } |
                Should -Throw "*Authentication*"
        }
    }

    Context 'Security' {
        It 'Should validate authentication token' {
            Mock Test-CompassOneToken { $false }
            { New-Incident @script:ValidIncident } |
                Should -Throw "*Authentication*"
        }

        It 'Should check user permissions' {
            Mock Test-SecurityContext { $false }
            { New-Incident @script:ValidIncident } |
                Should -Throw "*Unauthorized*"
        }

        It 'Should validate input sanitization' {
            $maliciousInput = @{
                Title = "'; DROP TABLE incidents; --"
                Priority = [IncidentPriority]::P1
            }
            { New-Incident @maliciousInput } |
                Should -Throw "*ValidationError*"
        }

        It 'Should verify audit logging' {
            New-Incident @script:ValidIncident
            Should -Invoke Write-CompassOneLog -Times 1 -ParameterFilter {
                $Level -eq 'Information' -and $Source -eq 'IncidentManager'
            }
        }

        It 'Should verify secure data handling' {
            $incident = New-Incident @script:ValidIncident -PassThru
            $incident | Get-Member | Where-Object { $_.Name -eq 'Password' -or $_.Name -eq 'Key' } |
                Should -BeNullOrEmpty
        }
    }

    Context 'Performance' {
        It 'Should complete within response time threshold' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            New-Incident @script:ValidIncident
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan $script:PerformanceThresholds.MaxResponseTime
        }

        It 'Should maintain efficient memory usage' {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            1..10 | ForEach-Object {
                New-Incident @script:ValidIncident
            }
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryDelta = ($finalMemory - $initialMemory) / 1MB
            $memoryDelta | Should -BeLessThan $script:PerformanceThresholds.MaxMemoryUsage
        }
    }

    Context 'Pipeline Support' {
        It 'Should support pipeline input' {
            $incidents = @(
                [PSCustomObject]@{ Title = "Test1"; Priority = "P1" }
                [PSCustomObject]@{ Title = "Test2"; Priority = "P2" }
            )
            $incidents | New-Incident
            Should -Invoke Invoke-CompassOneApi -Times 2
        }
    }
}