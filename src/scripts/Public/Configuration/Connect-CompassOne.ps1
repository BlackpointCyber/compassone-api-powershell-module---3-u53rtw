using namespace System.Security
using namespace System.Net.Security

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.SecretStore

<#
.SYNOPSIS
    Establishes a secure connection to the CompassOne platform.

.DESCRIPTION
    Public cmdlet that establishes a secure connection to the CompassOne platform by validating
    credentials, obtaining an authentication token, and setting up the session. Implements multiple
    authentication methods, secure credential handling, and comprehensive logging.

.PARAMETER ApiKey
    The API key for authentication as a SecureString.

.PARAMETER ApiUrl
    The CompassOne API endpoint URL.

.PARAMETER Force
    Switch to force a new connection even if one exists.

.PARAMETER PassThru
    Switch to return the connection object.

.PARAMETER UseEnvironmentVariables
    Switch to use environment variables for authentication.

.PARAMETER SkipCertificateCheck
    Switch to skip SSL/TLS certificate validation (not recommended for production).

.EXAMPLE
    Connect-CompassOne -ApiKey $secureApiKey -ApiUrl "https://api.compassone.blackpoint.io"

.EXAMPLE
    Connect-CompassOne -UseEnvironmentVariables -Force

.NOTES
    File Name      : Connect-CompassOne.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: Microsoft.PowerShell.SecretStore v1.0.6
#>

[CmdletBinding(DefaultParameterSetName='ApiKey', SupportsShouldProcess=$true)]
[OutputType([PSObject])]
param(
    [Parameter(ParameterSetName='ApiKey', Mandatory=$true)]
    [SecureString]$ApiKey,

    [Parameter(ParameterSetName='ApiKey', Mandatory=$true)]
    [Parameter(ParameterSetName='Environment')]
    [ValidatePattern('^https://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/?.*$')]
    [string]$ApiUrl,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$PassThru,

    [Parameter(ParameterSetName='Environment', Mandatory=$true)]
    [switch]$UseEnvironmentVariables,

    [Parameter()]
    [switch]$SkipCertificateCheck,

    [Parameter()]
    [ActionPreference]$ErrorAction = $ErrorActionPreference
)

begin {
    # Constants
    $REQUIRED_TLS_VERSION = 'Tls12'
    $CONNECTION_TIMEOUT = 30
    $MAX_RETRY_ATTEMPTS = 3
    $RETRY_DELAY_SECONDS = 2

    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()

    # Initialize connection state
    if (-not $Script:CompassOneConnection) {
        $Script:CompassOneConnection = $null
    }

    # Initialize connection pool if not exists
    if (-not $Script:CompassOneConnectionPool) {
        $Script:CompassOneConnectionPool = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
}

process {
    try {
        Write-CompassOneLog -Message "Starting connection attempt" `
                           -Level Information `
                           -Source "ConnectionManager" `
                           -Context @{
                               CorrelationId = $correlationId
                               UseEnvironment = $UseEnvironmentVariables.IsPresent
                               Force = $Force.IsPresent
                           }

        # Enforce TLS 1.2 or higher
        $currentTls = [System.Net.ServicePointManager]::SecurityProtocol
        if (-not ($currentTls -band [System.Net.SecurityProtocolType]::$REQUIRED_TLS_VERSION)) {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::$REQUIRED_TLS_VERSION
            Write-CompassOneLog -Message "Enforced TLS 1.2+" `
                               -Level Verbose `
                               -Source "ConnectionManager" `
                               -Context @{ CorrelationId = $correlationId }
        }

        # Check existing connection
        if (-not $Force -and $Script:CompassOneConnection) {
            # Validate existing connection
            $testResult = Invoke-CompassOneApi -EndpointPath "/health" `
                                             -Method "GET" `
                                             -ErrorAction SilentlyContinue

            if ($testResult) {
                Write-CompassOneLog -Message "Using existing connection" `
                                   -Level Information `
                                   -Source "ConnectionManager" `
                                   -Context @{ CorrelationId = $correlationId }

                if ($PassThru) {
                    return $Script:CompassOneConnection
                }
                return
            }
        }

        # Process credentials based on authentication method
        if ($UseEnvironmentVariables) {
            $ApiUrl = $env:COMPASSONE_API_URL ?? $ApiUrl
            $envApiKey = $env:COMPASSONE_API_KEY

            if (-not $ApiUrl -or -not $envApiKey) {
                Write-CompassOneError -ErrorCategory AuthenticationError `
                                    -ErrorCode 1001 `
                                    -ErrorDetails @{
                                        Message = "Required environment variables not found"
                                        CorrelationId = $correlationId
                                    } `
                                    -ErrorAction Stop
            }

            $ApiKey = ConvertTo-SecureString -String $envApiKey -AsPlainText -Force
        }

        # Validate API URL
        if (-not $ApiUrl) {
            Write-CompassOneError -ErrorCategory ValidationError `
                                -ErrorCode 3001 `
                                -ErrorDetails @{
                                    Message = "API URL is required"
                                    CorrelationId = $correlationId
                                } `
                                -ErrorAction Stop
        }

        if ($PSCmdlet.ShouldProcess("CompassOne API", "Connect")) {
            # Configure SSL/TLS certificate validation
            if (-not $SkipCertificateCheck) {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
            }
            else {
                Write-CompassOneLog -Message "Certificate validation disabled" `
                                   -Level Warning `
                                   -Source "ConnectionManager" `
                                   -Context @{ CorrelationId = $correlationId }

                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            }

            # Store credentials securely
            $credentialResult = Set-CompassOneCredential -ApiKey $ApiKey `
                                                       -ApiUrl $ApiUrl `
                                                       -Force:$Force

            if (-not $credentialResult) {
                throw "Failed to store credentials securely"
            }

            # Obtain authentication token
            $authToken = Get-CompassOneToken -Force:$Force
            if (-not $authToken) {
                throw "Failed to obtain authentication token"
            }

            # Test connection with retry logic
            $connected = $false
            $retryCount = 0

            do {
                try {
                    $testResult = Invoke-CompassOneApi -EndpointPath "/health" `
                                                     -Method "GET"
                    if ($testResult) {
                        $connected = $true
                        break
                    }
                }
                catch {
                    $retryCount++
                    if ($retryCount -ge $MAX_RETRY_ATTEMPTS) {
                        throw
                    }
                    Start-Sleep -Seconds ($RETRY_DELAY_SECONDS * $retryCount)
                }
            } while ($retryCount -lt $MAX_RETRY_ATTEMPTS)

            if (-not $connected) {
                throw "Failed to establish connection after $MAX_RETRY_ATTEMPTS attempts"
            }

            # Create connection object
            $connection = [PSCustomObject]@{
                PSTypeName = 'CompassOne.Connection'
                Connected = $true
                ApiUrl = $ApiUrl
                ConnectedOn = [DateTime]::UtcNow
                LastActivity = [DateTime]::UtcNow
                CorrelationId = $correlationId
            }

            # Update connection state
            $Script:CompassOneConnection = $connection
            $null = $Script:CompassOneConnectionPool.AddOrUpdate(
                $correlationId,
                $connection,
                { param($k, $v) $connection }
            )

            Write-CompassOneLog -Message "Successfully established connection" `
                               -Level Information `
                               -Source "ConnectionManager" `
                               -Context @{
                                   CorrelationId = $correlationId
                                   ApiUrl = $ApiUrl
                                   Connected = $true
                               }

            if ($PassThru) {
                return $connection
            }
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'credentials' { 1001 }  # Credential error
            'token' { 1002 }       # Token error
            'connection' { 2001 }   # Connection error
            'certificate' { 2002 }  # Certificate error
            default { 1000 }        # General error
        }

        Write-CompassOneError -ErrorCategory AuthenticationError `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Connection failed: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 ApiUrl = $ApiUrl
                             } `
                             -ErrorAction Stop
    }
    finally {
        # Clean up sensitive data
        if ($ApiKey) {
            $ApiKey.Dispose()
        }
        if ($envApiKey) {
            $envApiKey = $null
        }
        [System.GC]::Collect()
    }
}