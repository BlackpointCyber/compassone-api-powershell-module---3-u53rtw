using namespace System.IdentityModel.Tokens.Jwt # Version 7.0.0
using namespace System.Security # Version 4.0.0

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Validates the authenticity and expiration of a CompassOne API authentication token.

.DESCRIPTION
    Private function that performs comprehensive validation of CompassOne API tokens including
    JWT signature verification, expiration checks, and issuer validation. Implements secure
    token handling with detailed error tracking and audit logging.

.PARAMETER Token
    The JWT token to validate as a SecureString.

.PARAMETER CorrelationId
    Optional correlation ID for tracking related operations.

.PARAMETER ErrorAction
    Determines how the cmdlet responds to a non-terminating error.

.OUTPUTS
    System.Boolean
    Returns True if token is valid and not expired, False otherwise.

.NOTES
    File Name      : Test-CompassOneToken.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
    Required Modules: System.IdentityModel.Tokens.Jwt v7.0.0
                     System.Security v4.0.0
#>

[CmdletBinding()]
[OutputType([bool])]
param(
    [Parameter(Mandatory = $true)]
    [SecureString]$Token,

    [Parameter()]
    [string]$CorrelationId = [Guid]::NewGuid().ToString(),

    [Parameter()]
    [System.Management.Automation.ActionPreference]
    $ErrorAction = $ErrorActionPreference
)

begin {
    # Constants for token validation
    $ISSUER = "api.compassone.blackpoint.io"
    $AUDIENCE = "PSCompassOne"
    $CLOCK_SKEW = [TimeSpan]::FromMinutes(5)
    
    # Token validation parameters
    $tokenValidationParameters = @{
        ValidateIssuer = $true
        ValidIssuer = $ISSUER
        ValidateAudience = $true
        ValidAudience = $AUDIENCE
        ValidateLifetime = $true
        ClockSkew = $CLOCK_SKEW
        RequireSignedTokens = $true
        RequireExpirationTime = $true
    }
}

process {
    try {
        # Log validation attempt
        Write-CompassOneLog -Message "Starting token validation" `
                           -Level "Verbose" `
                           -Source "TokenValidator" `
                           -Context @{
                               "CorrelationId" = $CorrelationId
                               "Operation" = "TokenValidation"
                           }

        # Validate input parameter
        if (-not $Token -or $Token.Length -eq 0) {
            Write-CompassOneError -ErrorCategory "ValidationError" `
                                -ErrorCode 3001 `
                                -ErrorDetails @{
                                    "Message" = "Token parameter cannot be null or empty"
                                    "CorrelationId" = $CorrelationId
                                } `
                                -ErrorAction $ErrorAction
            return $false
        }

        # Convert SecureString to plain text for validation
        # Note: This is necessary for JWT validation but done securely
        $tokenString = $null
        try {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
            $tokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        finally {
            if ($BSTR) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
        }

        # Create JWT token handler with enhanced security
        $tokenHandler = New-Object JwtSecurityTokenHandler
        $tokenHandler.InboundClaimTypeMap.Clear()

        # Parse token without validation first to extract claims
        $jwtToken = $null
        try {
            $jwtToken = $tokenHandler.ReadJwtToken($tokenString)
        }
        catch {
            Write-CompassOneError -ErrorCategory "ValidationError" `
                                -ErrorCode 3002 `
                                -ErrorDetails @{
                                    "Message" = "Invalid JWT token format"
                                    "CorrelationId" = $CorrelationId
                                    "Error" = $_.Exception.Message
                                } `
                                -ErrorAction $ErrorAction
            return $false
        }

        # Validate token signature and claims
        try {
            # Create validation parameters
            $validationParameters = New-Object TokenValidationParameters
            foreach ($key in $tokenValidationParameters.Keys) {
                $validationParameters.$key = $tokenValidationParameters[$key]
            }

            # Perform comprehensive token validation
            $tokenHandler.ValidateToken(
                $tokenString,
                $validationParameters,
                [ref]$null
            )

            # Additional custom validations
            if ($jwtToken.ValidTo -lt [DateTime]::UtcNow) {
                throw "Token has expired"
            }

            # Log successful validation
            Write-CompassOneLog -Message "Token validation successful" `
                               -Level "Information" `
                               -Source "TokenValidator" `
                               -Context @{
                                   "CorrelationId" = $CorrelationId
                                   "TokenId" = $jwtToken.Id
                                   "Expiration" = $jwtToken.ValidTo.ToString('o')
                               }

            return $true
        }
        catch {
            # Handle specific validation failures
            $errorCode = switch -Regex ($_.Exception.Message) {
                "expired" { 6001 }  # Token expired
                "signature" { 6002 }  # Invalid signature
                "issuer" { 6003 }  # Invalid issuer
                "audience" { 6004 }  # Invalid audience
                default { 6000 }  # General token validation error
            }

            Write-CompassOneError -ErrorCategory "SecurityError" `
                                -ErrorCode $errorCode `
                                -ErrorDetails @{
                                    "Message" = "Token validation failed"
                                    "CorrelationId" = $CorrelationId
                                    "Error" = $_.Exception.Message
                                } `
                                -ErrorAction $ErrorAction
            return $false
        }
    }
    catch {
        # Handle unexpected errors
        Write-CompassOneError -ErrorCategory "SecurityError" `
                            -ErrorCode 6999 `
                            -ErrorDetails @{
                                "Message" = "Unexpected error during token validation"
                                "CorrelationId" = $CorrelationId
                                "Error" = $_.Exception.Message
                            } `
                            -ErrorAction $ErrorAction
        return $false
    }
    finally {
        # Clean up sensitive data
        if ($tokenString) {
            $tokenString = "0" * $tokenString.Length
            [System.GC]::Collect()
        }
        if ($jwtToken) {
            $jwtToken = $null
        }
    }
}