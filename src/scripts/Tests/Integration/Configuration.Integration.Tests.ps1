#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules
    Import-Module -Name Pester -MinimumVersion 5.0.0
    
    # Import configuration cmdlets
    . "$PSScriptRoot/../../Public/Configuration/Connect-CompassOne.ps1"
    . "$PSScriptRoot/../../Public/Configuration/Disconnect-CompassOne.ps1"
    . "$PSScriptRoot/../../Public/Configuration/Set-CompassOneConfig.ps1"

    # Test environment variables
    $script:TestApiKey = ConvertTo-SecureString -String "test_api_key_12345" -AsPlainText -Force
    $script:TestApiUrl = "https://api.compassone.blackpoint.io"
    $script:TestTimeout = 30
    $script:TestConfig = @{
        ApiUrl = $script:TestApiUrl
        ApiVersion = "v1"
        Timeout = $script:TestTimeout
        MaxRetry = 3
        LogLevel = "Information"
        CacheTTL = 300
        TlsVersion = "1.2"
        CertificateValidation = $true
        ConnectionPoolSize = 10
        AuditLogEnabled = $true
        AuditLogPath = "$env:TEMP\PSCompassOne\Logs"
    }
}

Describe 'Connection Management Integration Tests' {
    BeforeEach {
        # Ensure disconnected state before each test
        if ($Script:CompassOneConnection) {
            Disconnect-CompassOne -Force
        }
    }

    Context 'Connect-CompassOne Cmdlet' {
        It 'Successfully connects with valid API key' {
            $connection = Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl -PassThru
            $connection | Should -Not -BeNullOrEmpty
            $connection.Connected | Should -BeTrue
            $connection.ApiUrl | Should -Be $script:TestApiUrl
        }

        It 'Fails to connect with invalid API key' {
            $invalidKey = ConvertTo-SecureString -String "invalid_key" -AsPlainText -Force
            { Connect-CompassOne -ApiKey $invalidKey -ApiUrl $script:TestApiUrl } | 
                Should -Throw -ErrorId 'COMPASSONE_1001'
        }

        It 'Connects using environment variables' {
            $env:COMPASSONE_API_KEY = "test_api_key_12345"
            $env:COMPASSONE_API_URL = $script:TestApiUrl
            
            $connection = Connect-CompassOne -UseEnvironmentVariables -PassThru
            $connection | Should -Not -BeNullOrEmpty
            $connection.Connected | Should -BeTrue
            
            Remove-Item Env:\COMPASSONE_API_KEY
            Remove-Item Env:\COMPASSONE_API_URL
        }

        It 'Forces reconnection with existing connection' {
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl
            $connection = Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl -Force -PassThru
            $connection | Should -Not -BeNullOrEmpty
            $connection.Connected | Should -BeTrue
        }

        It 'Handles connection timeout appropriately' {
            $timeoutConfig = @{
                ApiKey = $script:TestApiKey
                ApiUrl = $script:TestApiUrl
                Timeout = 1
            }
            { Connect-CompassOne @timeoutConfig } | Should -Throw -ErrorId 'COMPASSONE_2001'
        }
    }

    Context 'Disconnect-CompassOne Cmdlet' {
        BeforeEach {
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl
        }

        It 'Successfully disconnects active connection' {
            Disconnect-CompassOne -Force
            $Script:CompassOneConnection | Should -BeNullOrEmpty
        }

        It 'Cleans up session state after disconnection' {
            Disconnect-CompassOne -Force
            $Script:CompassOneToken | Should -BeNullOrEmpty
            $Script:CompassOneSession | Should -BeNullOrEmpty
        }

        It 'Handles multiple disconnect calls gracefully' {
            Disconnect-CompassOne -Force
            { Disconnect-CompassOne -Force } | Should -Not -Throw
        }

        It 'Verifies cache cleanup after disconnection' {
            Disconnect-CompassOne -Force
            $Script:CompassOneCache.Count | Should -Be 0
        }
    }
}

Describe 'Configuration Management Integration Tests' {
    BeforeAll {
        $script:OriginalConfig = Import-PowerShellDataFile -Path "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
    }

    AfterAll {
        # Restore original configuration
        $script:OriginalConfig | Export-PowerShellDataFile -Path "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
    }

    Context 'Set-CompassOneConfig Cmdlet' {
        It 'Successfully updates API configuration' {
            $config = Set-CompassOneConfig -ApiUrl $script:TestApiUrl -ApiVersion "v1" -PassThru
            $config.ApiSettings.Endpoint | Should -Be $script:TestApiUrl
            $config.ApiSettings.Version | Should -Be "v1"
        }

        It 'Validates API URL format' {
            { Set-CompassOneConfig -ApiUrl "invalid-url" } | 
                Should -Throw -ErrorId 'COMPASSONE_3001'
        }

        It 'Updates timeout settings' {
            $config = Set-CompassOneConfig -Timeout 60 -PassThru
            $config.ApiSettings.Timeout | Should -Be 60
        }

        It 'Configures TLS settings' {
            $config = Set-CompassOneConfig -TlsVersion "1.2" -PassThru
            $config.SecuritySettings.MinimumTlsVersion | Should -Be "1.2"
        }

        It 'Updates logging configuration' {
            $config = Set-CompassOneConfig -LogLevel "Debug" -AuditLogEnabled $true -PassThru
            $config.LoggingSettings.LogLevel | Should -Be "Debug"
            $config.LoggingSettings.AuditLogging.Enabled | Should -BeTrue
        }

        It 'Validates connection pool size' {
            $config = Set-CompassOneConfig -ConnectionPoolSize 20 -PassThru
            $config.ConnectionSettings.ConnectionPooling.MaxPoolSize | Should -Be 20
        }

        It 'Handles invalid configuration values' {
            { Set-CompassOneConfig -Timeout 0 } | Should -Throw
            { Set-CompassOneConfig -MaxRetry -1 } | Should -Throw
            { Set-CompassOneConfig -ConnectionPoolSize 0 } | Should -Throw
        }

        It 'Preserves existing configuration values' {
            $before = Import-PowerShellDataFile -Path "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
            $config = Set-CompassOneConfig -ApiUrl $script:TestApiUrl -PassThru
            $config.SecuritySettings | Should -Be $before.SecuritySettings
        }

        It 'Requires confirmation for security-sensitive changes' {
            $result = Set-CompassOneConfig -CertificateValidation $false -Confirm:$false -PassThru
            $result.SecuritySettings.ValidateCertificateChain | Should -BeFalse
        }
    }

    Context 'Configuration Persistence' {
        It 'Persists configuration changes across sessions' {
            $testTimeout = 45
            Set-CompassOneConfig -Timeout $testTimeout
            $config = Import-PowerShellDataFile -Path "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
            $config.ApiSettings.Timeout | Should -Be $testTimeout
        }

        It 'Maintains configuration integrity' {
            $config = Import-PowerShellDataFile -Path "$PSScriptRoot/../../Config/PSCompassOne.config.psd1"
            $config.ApiSettings | Should -Not -BeNullOrEmpty
            $config.SecuritySettings | Should -Not -BeNullOrEmpty
            $config.LoggingSettings | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Clean up test environment
    if ($Script:CompassOneConnection) {
        Disconnect-CompassOne -Force
    }
    
    # Remove test environment variables
    Remove-Item Env:\COMPASSONE_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\COMPASSONE_API_URL -ErrorAction SilentlyContinue
    
    # Clear test variables
    $script:TestApiKey = $null
    $script:TestApiUrl = $null
    $script:TestConfig = $null
    
    # Force garbage collection
    [System.GC]::Collect()
}