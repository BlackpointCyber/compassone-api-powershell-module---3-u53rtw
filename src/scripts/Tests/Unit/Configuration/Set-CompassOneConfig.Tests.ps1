#Requires -Version 7.0
using namespace System
using namespace System.Security

BeforeAll {
    # Import required modules
    Import-Module Pester -MinimumVersion 5.0.0

    # Import functions under test
    . "$PSScriptRoot/../../../Public/Configuration/Set-CompassOneConfig.ps1"
    . "$PSScriptRoot/../../../Private/Validation/Test-CompassOneParameter.ps1"
    . "$PSScriptRoot/../../../Private/Validation/ConvertTo-CompassOneParameter.ps1"

    # Initialize test configurations
    $script:TestConfig = @{
        ApiUrl = 'https://api.test.compassone.blackpoint.io'
        ApiVersion = 'v1'
        Timeout = 30
        MaxRetry = 3
        LogLevel = 'Information'
        CacheTTL = 300
        TlsVersion = '1.2'
        CertificateValidation = $true
        ConnectionPoolSize = 10
        AuditLogEnabled = $true
        AuditLogPath = TestDrive:\Logs
    }

    $script:TestInvalidConfig = @{
        ApiUrl = 'http://invalid.url'
        Timeout = -1
        TlsVersion = '1.0'
        MaxRetry = 'invalid'
        ConnectionPoolSize = 0
    }

    # Mock functions
    Mock Write-Error { }
    Mock Write-Verbose { }
    Mock Test-CompassOneParameter { $true }
    Mock ConvertTo-CompassOneParameter { $args[0] }
}

Describe 'Set-CompassOneConfig' {
    Context 'When providing valid configuration values' {
        BeforeAll {
            # Create test config file
            $configPath = "TestDrive:\PSCompassOne.config.psd1"
            @{} | Export-PowerShellDataFile -Path $configPath
        }

        It 'Should accept valid API URL' {
            $result = Set-CompassOneConfig -ApiUrl $TestConfig.ApiUrl -PassThru
            $result.ApiUrl | Should -Be $TestConfig.ApiUrl
            Should -Not -Invoke Write-Error
        }

        It 'Should enforce HTTPS for API URL' {
            { Set-CompassOneConfig -ApiUrl 'http://invalid.url' } | 
                Should -Throw 'API URL must use HTTPS protocol'
        }

        It 'Should validate TLS version requirements' {
            $result = Set-CompassOneConfig -TlsVersion '1.2' -PassThru
            $result.TlsVersion | Should -Be '1.2'
            { Set-CompassOneConfig -TlsVersion '1.0' } | 
                Should -Throw 'TLS version must be 1.2 or higher for security compliance'
        }

        It 'Should configure certificate validation' {
            $result = Set-CompassOneConfig -CertificateValidation $true -PassThru
            $result.CertificateValidation | Should -BeTrue
        }

        It 'Should require confirmation when disabling certificate validation' {
            Mock $PSCmdlet.ShouldContinue { $false }
            { Set-CompassOneConfig -CertificateValidation $false } |
                Should -Throw 'Certificate validation change cancelled by user'
        }

        It 'Should validate timeout range' {
            $result = Set-CompassOneConfig -Timeout 30 -PassThru
            $result.Timeout | Should -Be 30
            { Set-CompassOneConfig -Timeout -1 } |
                Should -Throw
        }

        It 'Should validate connection pool size' {
            $result = Set-CompassOneConfig -ConnectionPoolSize 10 -PassThru
            $result.ConnectionSettings.ConnectionPooling.MaxPoolSize | Should -Be 10
            { Set-CompassOneConfig -ConnectionPoolSize 0 } |
                Should -Throw
        }

        It 'Should validate cache TTL' {
            $result = Set-CompassOneConfig -CacheTTL 300 -PassThru
            $result.CacheTTL | Should -Be 300
            { Set-CompassOneConfig -CacheTTL 30 } |
                Should -Throw
        }
    }

    Context 'When configuring security settings' {
        It 'Should enforce FIPS compliance' {
            $result = Set-CompassOneConfig -PassThru
            $result.SecuritySettings.Compliance.EnforceFips | Should -BeTrue
        }

        It 'Should validate audit log path' {
            $result = Set-CompassOneConfig -AuditLogPath 'TestDrive:\Logs' -AuditLogEnabled $true -PassThru
            $result.AuditLogPath | Should -Be 'TestDrive:\Logs'
            $result.AuditLogEnabled | Should -BeTrue
        }

        It 'Should reject invalid audit log paths' {
            { Set-CompassOneConfig -AuditLogPath 'Invalid:\Path' } |
                Should -Throw 'Invalid audit log path specified'
        }

        It 'Should validate log levels' {
            $validLevels = @('Debug', 'Information', 'Warning', 'Error')
            foreach ($level in $validLevels) {
                $result = Set-CompassOneConfig -LogLevel $level -PassThru
                $result.LogLevel | Should -Be $level
            }
        }
    }

    Context 'When configuring performance settings' {
        It 'Should validate retry attempts' {
            $result = Set-CompassOneConfig -MaxRetry 3 -PassThru
            $result.MaxRetry | Should -Be 3
            { Set-CompassOneConfig -MaxRetry 11 } |
                Should -Throw
        }

        It 'Should configure connection pooling' {
            $result = Set-CompassOneConfig -ConnectionPoolSize 10 -PassThru
            $result.ConnectionSettings.ConnectionPooling.MaxPoolSize | Should -Be 10
            $result.ConnectionSettings.ConnectionPooling.Enabled | Should -BeTrue
        }

        It 'Should validate timeout settings' {
            $result = Set-CompassOneConfig -Timeout 30 -PassThru
            $result.Timeout | Should -Be 30
            { Set-CompassOneConfig -Timeout 301 } |
                Should -Throw
        }

        It 'Should configure caching parameters' {
            $result = Set-CompassOneConfig -CacheTTL 300 -PassThru
            $result.CacheTTL | Should -Be 300
            { Set-CompassOneConfig -CacheTTL 3601 } |
                Should -Throw
        }
    }

    Context 'When using WhatIf parameter' {
        It 'Should not modify configuration when using WhatIf' {
            $before = Get-Content -Path $configPath
            Set-CompassOneConfig -ApiUrl $TestConfig.ApiUrl -WhatIf
            $after = Get-Content -Path $configPath
            $after | Should -Be $before
        }
    }

    Context 'When handling errors' {
        It 'Should throw on invalid parameter combinations' {
            { Set-CompassOneConfig -CacheTTL 30 -Timeout -1 } |
                Should -Throw
        }

        It 'Should validate parameter dependencies' {
            { Set-CompassOneConfig -AuditLogEnabled $true -AuditLogPath $null } |
                Should -Throw
        }

        It 'Should handle file system errors gracefully' {
            Mock Export-PowerShellDataFile { throw 'Access denied' }
            { Set-CompassOneConfig -ApiUrl $TestConfig.ApiUrl } |
                Should -Throw 'Failed to update configuration: Access denied'
        }
    }
}

AfterAll {
    # Cleanup test artifacts
    Remove-Item -Path TestDrive:\* -Recurse -Force -ErrorAction SilentlyContinue
}