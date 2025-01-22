using namespace System.Net.Http # Version 7.0.0
using namespace System.Security # Version 4.0.0

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Executes HTTP requests to the CompassOne API with comprehensive error handling and security controls.

.DESCRIPTION
    Private function that handles all HTTP communication with the CompassOne API. Implements secure
    request creation, sending, response handling, retries, and error management with comprehensive
    security, performance optimizations, and resource cleanup.

.PARAMETER EndpointPath
    The API endpoint path (e.g., /assets, /findings).

.PARAMETER Method
    The HTTP method for the request (GET, POST, PUT, DELETE).

.PARAMETER Body
    Optional. The request body object to be serialized to JSON.

.PARAMETER QueryParameters
    Optional. Hashtable of query string parameters.

.PARAMETER UseCache
    Optional. Switch to enable response caching.

.PARAMETER RetryCount
    Optional. Number of retry attempts for failed requests. Default is 3.

.PARAMETER RetryIntervalSeconds
    Optional. Base interval between retries in seconds. Default is 2.

.PARAMETER CorrelationId
    Optional. Correlation ID for request tracking.

.OUTPUTS
    PSObject. Processed API response or detailed error record with correlation.

.NOTES
    File Name      : Invoke-CompassOneApi.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: System.Net.Http v7.0.0
                     System.Security v4.0.0
#>

[CmdletBinding()]
[OutputType([PSObject])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EndpointPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
    [string]$Method,

    [Parameter()]
    [PSObject]$Body,

    [Parameter()]
    [hashtable]$QueryParameters,

    [Parameter()]
    [switch]$UseCache,

    [Parameter()]
    [int]$RetryCount = 3,

    [Parameter()]
    [int]$RetryIntervalSeconds = 2,

    [Parameter()]
    [string]$CorrelationId = [Guid]::NewGuid().ToString()
)

begin {
    # Configure security protocols
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Initialize HttpClient with connection pooling
    $handler = New-Object HttpClientHandler
    $handler.UseDefaultCredentials = $false
    $handler.MaxConnectionsPerServer = 20

    $client = New-Object HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
}

process {
    try {
        Write-CompassOneLog -Message "Starting API request" `
                           -Level Information `
                           -Source "ApiClient" `
                           -Context @{
                               CorrelationId = $CorrelationId
                               Method = $Method
                               Endpoint = $EndpointPath
                           }

        # Check cache for GET requests
        if ($Method -eq 'GET' -and $UseCache) {
            $cachedResponse = Get-CompassOneCache -Key "API:$EndpointPath"
            if ($cachedResponse) {
                Write-CompassOneLog -Message "Returning cached response" `
                                   -Level Verbose `
                                   -Source "ApiClient" `
                                   -Context @{
                                       CorrelationId = $CorrelationId
                                       CacheHit = $true
                                   }
                return $cachedResponse
            }
        }

        # Create API request with security headers
        $request = New-CompassOneApiRequest `
            -EndpointPath $EndpointPath `
            -Method $Method `
            -Body $Body `
            -QueryParameters $QueryParameters

        # Initialize retry loop variables
        $currentRetry = 0
        $shouldRetry = $false
        $response = $null

        do {
            try {
                if ($currentRetry -gt 0) {
                    # Calculate exponential backoff delay
                    $delay = $RetryIntervalSeconds * [Math]::Pow(2, $currentRetry - 1)
                    Start-Sleep -Seconds $delay

                    Write-CompassOneLog -Message "Retrying request" `
                                       -Level Warning `
                                       -Source "ApiClient" `
                                       -Context @{
                                           CorrelationId = $CorrelationId
                                           Attempt = $currentRetry + 1
                                           MaxAttempts = $RetryCount
                                           Delay = $delay
                                       }
                }

                # Send request with proper exception handling
                $sendTask = $client.SendAsync($request)
                if (-not $sendTask.Wait(30000)) {
                    throw "Request timeout after 30 seconds"
                }
                $response = $sendTask.Result

                # Process response with retry logic
                $result = Get-CompassOneApiResponse `
                    -Response $response `
                    -EndpointPath $EndpointPath `
                    -UseCache:$UseCache `
                    -RetryCount ($RetryCount - $currentRetry) `
                    -RetryInterval ([TimeSpan]::FromSeconds($RetryIntervalSeconds))

                if ($result -eq $false) {
                    # Response handler indicates retry needed
                    $shouldRetry = $currentRetry -lt $RetryCount
                    $currentRetry++
                }
                else {
                    # Successful response
                    return $result
                }
            }
            catch {
                # Determine if error is retryable
                $shouldRetry = $currentRetry -lt $RetryCount -and (
                    $_.Exception.Message -match 'timeout|connection|5\d{2}' -or
                    $response.StatusCode -ge 500
                )

                if ($shouldRetry) {
                    $currentRetry++
                }
                else {
                    # Non-retryable error or max retries exceeded
                    Write-CompassOneError -ErrorCategory ConnectionError `
                                        -ErrorCode 2001 `
                                        -ErrorDetails @{
                                            Message = "API request failed: $($_.Exception.Message)"
                                            CorrelationId = $CorrelationId
                                            Endpoint = $EndpointPath
                                            Method = $Method
                                            Attempts = $currentRetry
                                        } `
                                        -ErrorAction Stop
                }
            }
            finally {
                # Cleanup response resources
                if ($response) {
                    if ($response.Content) {
                        $response.Content.Dispose()
                    }
                    $response.Dispose()
                }
            }
        } while ($shouldRetry)

        throw "Request failed after $RetryCount attempts"
    }
    catch {
        # Handle unexpected errors
        Write-CompassOneError -ErrorCategory InvalidOperation `
                             -ErrorCode 7001 `
                             -ErrorDetails @{
                                 Message = "Unexpected error in API operation: $($_.Exception.Message)"
                                 CorrelationId = $CorrelationId
                                 Endpoint = $EndpointPath
                                 Method = $Method
                             } `
                             -ErrorAction Stop
    }
    finally {
        # Cleanup resources
        if ($request) {
            $request.Dispose()
        }
        if ($handler) {
            $handler.Dispose()
        }
        if ($client) {
            $client.Dispose()
        }
        [System.GC]::Collect()
    }
}