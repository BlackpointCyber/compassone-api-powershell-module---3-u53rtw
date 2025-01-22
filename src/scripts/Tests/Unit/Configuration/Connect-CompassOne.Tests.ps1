using namespace System.Security
using namespace System.Net.Http
using namespace System.Net.Security

#Requires -Version 5.1
#Requires -Modules Pester, Microsoft.PowerShell.SecretStore

BeforeAll {
    # Import required modules
    Import-Module Microsoft.PowerShell.SecretStore

    # Mock paths for imported functions
    . $PSScriptRoot/../../../Public/Configuration/Connect-CompassOne.ps1
    . $PSScriptRoot/../../../Private/Authentication/Get-CompassOneToken.ps1
    . $PSScriptRoot/../../../Private/Authentication/Set-CompassOneCredential.ps1
    . $PSScriptRoot/../../../Private/Logging/Write-CompassOneLog.ps1
    . $PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1

    # Test constants
    $script:TestApiKey = ConvertTo-SecureString -String "test_api_key_12345" -AsPlainText -Force
    $script:TestApiUrl = "https://api.compassone.blackpoint.io"
    $script:TestToken = ConvertTo-SecureString -String "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." -AsPlainText -Force
    $script:TestCorrelationId = [guid]::NewGuid().ToString()
}

Describe 'Connect-CompassOne' {
    BeforeEach {
        # Reset module state
        $Script:CompassOneConnection = $null
        $Script:CompassOneConnectionPool = $null

        # Mock functions
        Mock Write-CompassOneLog { }
        Mock Write-CompassOneError { throw $ErrorDetails.Message }
        Mock Get-CompassOneToken { return $script:TestToken }
        Mock Set-CompassOneCredential { return $true }
        Mock Invoke-CompassOneApi { return @{ status = "healthy" } }
        Mock Test-CompassOneToken { return $true }
    }

    Context 'Security Validation' {
        It 'Should enforce TLS 1.2 or higher' {
            # Arrange
            $currentTls = [System.Net.ServicePointManager]::SecurityProtocol

            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            [System.Net.ServicePointManager]::SecurityProtocol | Should -Match 'Tls12'
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -eq "Enforced TLS 1.2+" -and
                $Level -eq "Verbose"
            }
        }

        It 'Should securely store credentials' {
            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            Should -Invoke Set-CompassOneCredential -ParameterFilter {
                $ApiKey -eq $script:TestApiKey -and
                $ApiUrl -eq $script:TestApiUrl
            }
        }

        It 'Should validate authentication token' {
            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            Should -Invoke Get-CompassOneToken
            Should -Invoke Test-CompassOneToken
        }

        It 'Should handle certificate validation properly' {
            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback | 
                Should -BeNullOrEmpty
        }
    }

    Context 'Performance Validation' {
        It 'Should complete connection within 2 seconds' {
            # Arrange
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It 'Should implement connection pooling' {
            # Act
            1..5 | ForEach-Object {
                Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl
            }

            # Assert
            $Script:CompassOneConnectionPool.Count | Should -BeGreaterThan 0
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should properly manage connection resources' {
            # Arrange
            $initialMemory = [System.GC]::GetTotalMemory($true)

            # Act
            1..10 | ForEach-Object {
                Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl
            }
            [System.GC]::Collect()
            $finalMemory = [System.GC]::GetTotalMemory($true)

            # Assert
            ($finalMemory - $initialMemory) | Should -BeLessThan 100MB
        }
    }

    Context 'Error Handling' {
        It 'Should handle invalid API key' {
            # Arrange
            Mock Set-CompassOneCredential { throw "Invalid API key" }

            # Act & Assert
            { Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl } |
                Should -Throw -ExpectedMessage "*Invalid API key*"
        }

        It 'Should handle connection failures' {
            # Arrange
            Mock Invoke-CompassOneApi { throw "Connection failed" }

            # Act & Assert
            { Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl } |
                Should -Throw -ExpectedMessage "*Connection failed*"
        }

        It 'Should implement retry logic' {
            # Arrange
            $attempts = 0
            Mock Invoke-CompassOneApi {
                $attempts++
                if ($attempts -lt 3) { throw "Temporary failure" }
                return @{ status = "healthy" }
            }

            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            $attempts | Should -Be 3
        }

        It 'Should handle token validation failures' {
            # Arrange
            Mock Test-CompassOneToken { return $false }

            # Act & Assert
            { Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl } |
                Should -Throw -ExpectedMessage "*Invalid authentication token*"
        }
    }

    Context 'Environment Variable Support' {
        BeforeEach {
            $env:COMPASSONE_API_KEY = "env_test_key"
            $env:COMPASSONE_API_URL = $script:TestApiUrl
        }

        AfterEach {
            Remove-Item Env:\COMPASSONE_API_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:\COMPASSONE_API_URL -ErrorAction SilentlyContinue
        }

        It 'Should use environment variables when specified' {
            # Act
            Connect-CompassOne -UseEnvironmentVariables

            # Assert
            Should -Invoke Set-CompassOneCredential -ParameterFilter {
                $ApiUrl -eq $env:COMPASSONE_API_URL
            }
        }
    }

    Context 'Connection State Management' {
        It 'Should reuse existing connection when valid' {
            # Arrange
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            Should -Invoke Invoke-CompassOneApi -Times 2
        }

        It 'Should force new connection when specified' {
            # Arrange
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl -Force

            # Assert
            Should -Invoke Set-CompassOneCredential -Times 2
        }
    }

    Context 'Audit Logging' {
        It 'Should log connection attempts' {
            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -eq "Starting connection attempt" -and
                $Level -eq "Information"
            }
        }

        It 'Should log successful connections' {
            # Act
            Connect-CompassOne -ApiKey $script:TestApiKey -ApiUrl $script:TestApiUrl

            # Assert
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Message -eq "Successfully established connection" -and
                $Level -eq "Information"
            }
        }
    }
}

AfterAll {
    # Cleanup
    $Script:CompassOneConnection = $null
    $Script:CompassOneConnectionPool = $null
    [System.GC]::Collect()
}