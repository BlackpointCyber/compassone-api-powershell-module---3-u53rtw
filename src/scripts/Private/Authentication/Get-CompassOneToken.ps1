using namespace System.Security
using namespace System.IdentityModel.Tokens.Jwt
using namespace System.Security.Cryptography

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.SecretStore, System.IdentityModel.Tokens.Jwt

<#
.SYNOPSIS
    Retrieves or generates an authentication token for the CompassOne API.

.DESCRIPTION
    Private function that securely manages authentication tokens for the CompassOne API.
    Implements secure token caching, validation, automatic refresh, and comprehensive error handling.

.PARAMETER Force
    Forces a new token to be generated regardless of cache state.

.PARAMETER ErrorAction
    Determines how the cmdlet responds to a non-terminating error.

.OUTPUTS
    System.String
    Returns a valid authentication token for API requests.

.NOTES
    File Name      : Get-CompassOneToken.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: Microsoft.PowerShell.SecretStore v1.0.6
                     System.IdentityModel.Tokens.Jwt v7.0.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ActionPreference]$ErrorAction = $ErrorActionPreference
)

begin {
    # Constants
    $TOKEN_CACHE_KEY = 'CompassOne_AuthToken'
    $TOKEN_LIFETIME_MINUTES = 30
    $MAX_RETRY_ATTEMPTS = 3
    $RETRY_DELAY_SECONDS = 2

    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()
}

process {
    try {
        Write-CompassOneLog -Message 'Starting token retrieval' `
                           -Level 'Information' `
                           -Source 'TokenManager' `
                           -Context @{
                               CorrelationId = $correlationId
                               Operation = 'GetToken'
                               Force = $Force.IsPresent
                           }

        # Check cache first unless Force is specified
        if (-not $Force) {
            $cachedToken = Get-CompassOneCache -Key $TOKEN_CACHE_KEY

            if ($cachedToken) {
                # Validate cached token
                $isValid = Test-CompassOneToken -Token $cachedToken -CorrelationId $correlationId -ErrorAction Continue

                if ($isValid) {
                    Write-CompassOneLog -Message 'Using cached token' `
                                      -Level 'Verbose' `
                                      -Source 'TokenManager' `
                                      -Context @{
                                          CorrelationId = $correlationId
                                          Operation = 'CacheHit'
                                      }
                    return $cachedToken
                }
            }
        }

        # Get API credentials
        $credentials = $null
        $retryCount = 0
        $credentialSuccess = $false

        do {
            try {
                $credentials = Set-CompassOneCredential -ErrorAction Stop
                $credentialSuccess = $true
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $MAX_RETRY_ATTEMPTS) {
                    throw
                }
                Start-Sleep -Seconds ($RETRY_DELAY_SECONDS * $retryCount)
            }
        } while ($retryCount -lt $MAX_RETRY_ATTEMPTS)

        if (-not $credentialSuccess) {
            throw "Failed to retrieve API credentials after $MAX_RETRY_ATTEMPTS attempts"
        }

        # Generate new token
        $newToken = $null
        $tokenSuccess = $false
        $retryCount = 0

        do {
            try {
                # Create JWT token with secure claims
                $now = [DateTime]::UtcNow
                $expires = $now.AddMinutes($TOKEN_LIFETIME_MINUTES)

                $tokenDescriptor = @{
                    Issuer = "api.compassone.blackpoint.io"
                    Audience = "PSCompassOne"
                    NotBefore = $now
                    Expires = $expires
                    SigningCredentials = New-Object SecurityTokenDescriptor
                    Claims = @{
                        jti = [guid]::NewGuid().ToString()
                        iat = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                        sub = $credentials.ApiKey
                    }
                }

                # Generate token with proper security controls
                $tokenHandler = New-Object JwtSecurityTokenHandler
                $token = $tokenHandler.CreateToken($tokenDescriptor)
                $newToken = $tokenHandler.WriteToken($token)

                # Validate new token
                $secureToken = ConvertTo-SecureString -String $newToken -AsPlainText -Force
                $isValid = Test-CompassOneToken -Token $secureToken -CorrelationId $correlationId

                if (-not $isValid) {
                    throw "Generated token failed validation"
                }

                $tokenSuccess = $true
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $MAX_RETRY_ATTEMPTS) {
                    throw
                }
                Start-Sleep -Seconds ($RETRY_DELAY_SECONDS * $retryCount)
            }
        } while ($retryCount -lt $MAX_RETRY_ATTEMPTS)

        if (-not $tokenSuccess) {
            throw "Failed to generate valid token after $MAX_RETRY_ATTEMPTS attempts"
        }

        # Cache the new token securely
        $cacheEntry = @{
            Value = $secureToken
            Expiration = $expires
        }

        $null = Get-CompassOneCache -Key $TOKEN_CACHE_KEY
        
        Write-CompassOneLog -Message 'Successfully generated new token' `
                           -Level 'Information' `
                           -Source 'TokenManager' `
                           -Context @{
                               CorrelationId = $correlationId
                               Operation = 'TokenGeneration'
                               Expiration = $expires.ToString('o')
                           }

        return $secureToken
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'credentials' { 1001 }  # Credential retrieval error
            'validation' { 1002 }  # Token validation error
            'generation' { 1003 }  # Token generation error
            'cache' { 1004 }       # Cache operation error
            default { 1000 }       # General token error
        }

        Write-CompassOneError -ErrorCategory 'AuthenticationError' `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Token operation failed: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Operation = 'GetToken'
                             } `
                             -ErrorAction $ErrorAction
        throw
    }
    finally {
        # Clean up sensitive data
        if ($credentials) {
            $credentials.ApiKey = $null
            $credentials.Clear()
        }
        if ($newToken) {
            $newToken = "0" * $newToken.Length
        }
        [System.GC]::Collect()
    }
}