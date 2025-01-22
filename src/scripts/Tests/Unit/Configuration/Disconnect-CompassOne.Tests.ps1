using namespace System.Security
using namespace System.Threading

#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required functions
    . $PSScriptRoot/../../../Public/Configuration/Disconnect-CompassOne.ps1
    . $PSScriptRoot/../../../Private/Authentication/Test-CompassOneToken.ps1
    . $PSScriptRoot/../../../Private/Cache/Clear-CompassOneCache.ps1
    . $PSScriptRoot/../../../Private/Logging/Write-CompassOneLog.ps1

    # Initialize mock session state
    $Script:CompassOneSession = [hashtable]::Synchronized(@{
        SessionId = 'TEST-SESSION-001'
        UserAgent = 'PSCompassOne/1.0.0'
        Connected = $true
        LastActivity = [DateTime]::UtcNow
    })

    # Create mock secure token
    $mockToken = ConvertTo-SecureString -String "TEST-TOKEN-12345" -AsPlainText -Force
    $Script:CompassOneToken = $mockToken

    # Initialize correlation tracking
    $Script:CorrelationId = [guid]::NewGuid().ToString()

    # Mock Test-CompassOneToken
    Mock Test-CompassOneToken {
        param($Token, $CorrelationId)
        return $true
    } -Verifiable

    # Mock Clear-CompassOneCache
    Mock Clear-CompassOneCache {
        param($Force)
        return $true
    } -Verifiable

    # Mock Write-CompassOneLog
    Mock Write-CompassOneLog {
        param($Message, $Level, $Source, $Context)
    } -Verifiable
}

Describe 'Disconnect-CompassOne' {
    Context 'Security Operations' {
        It 'Should securely dispose authentication token' {
            # Arrange
            $initialToken = $Script:CompassOneToken.Copy()

            # Act
            Disconnect-CompassOne -Force

            # Assert
            $Script:CompassOneToken | Should -BeNullOrEmpty
            Should -Invoke Test-CompassOneToken -Times 1 -Exactly
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Information' -and 
                $Message -like '*Successfully disconnected*'
            }
        }

        It 'Should perform thread-safe cache clearing' {
            # Arrange
            $Script:CompassOneSession = [hashtable]::Synchronized(@{
                SessionId = 'TEST-SESSION-002'
                Connected = $true
            })

            # Act
            $lockTaken = $false
            $result = Disconnect-CompassOne -Force

            # Assert
            Should -Invoke Clear-CompassOneCache -Times 1 -Exactly -ParameterFilter {
                $Force -eq $true
            }
            $Script:CompassOneSession | Should -BeNullOrEmpty
        }

        It 'Should maintain correlation tracking through disconnection' {
            # Arrange
            $correlationId = [guid]::NewGuid().ToString()
            Mock Write-CompassOneLog {
                param($Message, $Level, $Source, $Context)
                $Context.CorrelationId | Should -Not -BeNullOrEmpty
                $Context.Operation | Should -Be 'Disconnect'
            }

            # Act
            Disconnect-CompassOne -Force

            # Assert
            Should -Invoke Write-CompassOneLog -Times 2 -Exactly
        }

        It 'Should handle invalid session state securely' {
            # Arrange
            $Script:CompassOneSession = $null
            $Script:CompassOneToken = $null

            # Act & Assert
            { Disconnect-CompassOne -Force } | Should -Not -Throw
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Information' -and 
                $Message -like '*No active CompassOne connection*'
            }
        }

        It 'Should verify complete cleanup of sensitive data' {
            # Arrange
            $Script:CompassOneSession = [hashtable]::Synchronized(@{
                SessionId = 'TEST-SESSION-003'
                Connected = $true
                Credentials = ConvertTo-SecureString -String "TEST-CRED" -AsPlainText -Force
            })

            # Act
            Disconnect-CompassOne -Force

            # Assert
            $Script:CompassOneSession | Should -BeNullOrEmpty
            $Script:CompassOneToken | Should -BeNullOrEmpty
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Information' -and 
                $Context.Status -eq 'Success'
            }
        }

        It 'Should respect ShouldProcess for confirmation' {
            # Arrange
            $Script:CompassOneSession = [hashtable]::Synchronized(@{
                SessionId = 'TEST-SESSION-004'
                Connected = $true
            })

            # Act & Assert
            Disconnect-CompassOne -WhatIf
            $Script:CompassOneSession.Connected | Should -Be $true
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Information' -and 
                $Message -like '*WhatIf*'
            }
        }

        It 'Should log security-relevant events' {
            # Arrange
            $Script:CompassOneSession = [hashtable]::Synchronized(@{
                SessionId = 'TEST-SESSION-005'
                Connected = $true
            })

            # Act
            Disconnect-CompassOne -Force

            # Assert
            Should -Invoke Write-CompassOneLog -Times 2 -Exactly -ParameterFilter {
                $Source -eq 'Disconnect-CompassOne' -and
                $Context.Operation -eq 'Disconnect'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle token disposal failures securely' {
            # Arrange
            Mock Test-CompassOneToken { throw 'Token disposal error' }

            # Act & Assert
            { Disconnect-CompassOne -Force } | Should -Throw
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Error' -and
                $Message -like '*Failed to disconnect*'
            }
        }

        It 'Should handle cache clearing failures gracefully' {
            # Arrange
            Mock Clear-CompassOneCache { throw 'Cache clearing error' }

            # Act & Assert
            { Disconnect-CompassOne -Force } | Should -Throw
            Should -Invoke Write-CompassOneLog -ParameterFilter {
                $Level -eq 'Error'
            }
        }
    }
}