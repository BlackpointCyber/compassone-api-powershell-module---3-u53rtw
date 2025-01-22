using namespace System.Net.NetworkInformation # Version 4.0.0
using namespace System.Security # Version 4.0.0

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Tests the connection to the CompassOne API with comprehensive validation.

.DESCRIPTION
    Public cmdlet that performs comprehensive testing of the CompassOne API connection,
    including network connectivity, authentication, TLS configuration, and API availability.
    Implements secure connection testing with detailed error handling and audit logging.

.PARAMETER Detailed
    Switch to return detailed diagnostic information about the connection test.

.PARAMETER ErrorAction
    Determines how the cmdlet responds to a non-terminating error.

.PARAMETER CorrelationId
    Optional correlation ID for tracking related operations.

.OUTPUTS
    PSCustomObject. Connection test result containing status, latency, and diagnostics.

.EXAMPLE
    Test-CompassOneConnection
    Tests the basic connection to CompassOne API.

.EXAMPLE
    Test-CompassOneConnection -Detailed
    Tests the connection and returns detailed diagnostic information.

.NOTES
    File Name      : Test-CompassOneConnection.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: System.Net.NetworkInformation v4.0.0
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [switch]$Detailed,

    [Parameter()]
    [System.Management.Automation.ActionPreference]
    $ErrorAction = $ErrorActionPreference,

    [Parameter()]
    [string]$CorrelationId = [Guid]::NewGuid().ToString()
)

begin {
    # Constants
    $REQUIRED_TLS_VERSION = 'Tls12'
    $CONNECTION_TIMEOUT = 30000  # 30 seconds
    $TEST_ENDPOINT = '/health'
    $PING_COUNT = 3
}

process {
    try {
        Write-CompassOneLog -Message "Starting connection test" `
                           -Level Information `
                           -Source "ConnectionTest" `
                           -Context @{
                               CorrelationId = $CorrelationId
                               Detailed = $Detailed.IsPresent
                           }

        # Initialize result object
        $result = [PSCustomObject]@{
            Success = $false
            Status = "Testing"
            Timestamp = [DateTime]::UtcNow
            CorrelationId = $CorrelationId
            Latency = $null
            Details = @{
                TLS = $null
                Network = $null
                Authentication = $null
                API = $null
            }
        }

        # Step 1: Validate TLS configuration
        Write-Verbose "Validating TLS configuration..."
        $currentTLS = [System.Net.ServicePointManager]::SecurityProtocol
        $tlsValid = $currentTLS -band [System.Net.SecurityProtocolType]::$REQUIRED_TLS_VERSION

        if (-not $tlsValid) {
            throw "TLS 1.2 or higher is required. Current: $currentTLS"
        }

        $result.Details.TLS = @{
            Version = $currentTLS.ToString()
            Valid = $true
        }

        # Step 2: Test network connectivity
        Write-Verbose "Testing network connectivity..."
        $ping = New-Object System.Net.NetworkInformation.Ping
        $pingResults = @()

        for ($i = 0; $i -lt $PING_COUNT; $i++) {
            try {
                $pingResult = $ping.Send("api.compassone.blackpoint.io", 1000)
                $pingResults += $pingResult.RoundtripTime
            }
            catch {
                Write-CompassOneLog -Message "Ping attempt $($i+1) failed" `
                                   -Level Warning `
                                   -Source "ConnectionTest" `
                                   -Context @{
                                       CorrelationId = $CorrelationId
                                       Error = $_.Exception.Message
                                   }
            }
        }

        if ($pingResults.Count -eq 0) {
            throw "Network connectivity test failed. Unable to reach API endpoint."
        }

        $result.Details.Network = @{
            AverageLatency = ($pingResults | Measure-Object -Average).Average
            PacketLoss = (($PING_COUNT - $pingResults.Count) / $PING_COUNT) * 100
            Successful = $pingResults.Count -gt 0
        }

        # Step 3: Validate authentication token
        Write-Verbose "Validating authentication..."
        $token = Get-CompassOneToken -ErrorAction Stop
        $tokenValid = Test-CompassOneToken -Token $token -CorrelationId $CorrelationId

        if (-not $tokenValid) {
            throw "Authentication validation failed. Invalid or expired token."
        }

        $result.Details.Authentication = @{
            Valid = $true
            TokenPresent = $true
        }

        # Step 4: Test API connectivity
        Write-Verbose "Testing API connectivity..."
        $apiResponse = Invoke-CompassOneApi -EndpointPath $TEST_ENDPOINT `
                                          -Method 'GET' `
                                          -CorrelationId $CorrelationId `
                                          -ErrorAction Stop

        if (-not $apiResponse) {
            throw "API health check failed. No response received."
        }

        $result.Details.API = @{
            Available = $true
            StatusCode = 200
            Response = if ($Detailed) { $apiResponse } else { $null }
        }

        # Update final result
        $result.Success = $true
        $result.Status = "Connected"
        $result.Latency = $result.Details.Network.AverageLatency

        Write-CompassOneLog -Message "Connection test completed successfully" `
                           -Level Information `
                           -Source "ConnectionTest" `
                           -Context @{
                               CorrelationId = $CorrelationId
                               Success = $true
                               Latency = $result.Latency
                           }

        # Return appropriate result based on -Detailed switch
        if ($Detailed) {
            return $result
        }
        else {
            return [PSCustomObject]@{
                Success = $result.Success
                Status = $result.Status
                Latency = $result.Latency
                Timestamp = $result.Timestamp
            }
        }
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'TLS' { 2001 }        # TLS configuration error
            'network' { 2002 }    # Network connectivity error
            'token' { 2003 }      # Authentication error
            'API' { 2004 }        # API availability error
            default { 2000 }      # General connection error
        }

        Write-CompassOneError -ErrorCategory ConnectionError `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Connection test failed: $($_.Exception.Message)"
                                 CorrelationId = $CorrelationId
                                 Stage = $result.Status
                             } `
                             -ErrorAction $ErrorAction

        # Return failed result
        $result.Success = $false
        $result.Status = "Failed"
        return $result
    }
    finally {
        # Clean up resources
        if ($ping) {
            $ping.Dispose()
        }
        if ($token) {
            $token.Dispose()
        }
        [System.GC]::Collect()
    }
}