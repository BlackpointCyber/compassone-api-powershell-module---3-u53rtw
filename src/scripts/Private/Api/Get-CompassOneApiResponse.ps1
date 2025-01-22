using namespace System.Net.Http # Version 7.0.0
using namespace System.Security.Cryptography

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Processes HTTP responses from the CompassOne API with comprehensive error handling and security validation.

.DESCRIPTION
    Private function that processes HTTP responses from the CompassOne API, implementing comprehensive
    response handling with secure data processing, intelligent caching, error management, and 
    performance optimization. Ensures consistent, secure, and efficient response processing across
    all API operations with full audit trail and compliance support.

.PARAMETER Response
    The HttpResponseMessage object from the API call.

.PARAMETER EndpointPath
    The API endpoint path for the request.

.PARAMETER UseCache
    Optional switch to enable response caching.

.PARAMETER RetryCount
    Optional retry count for transient failures. Default is 3.

.PARAMETER RetryInterval
    Optional base interval between retries. Default is 2 seconds.

.OUTPUTS
    PSObject. Processed and validated API response object or detailed error record.

.NOTES
    File Name      : Get-CompassOneApiResponse.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
#>

[CmdletBinding()]
[OutputType([PSObject])]
param(
    [Parameter(Mandatory = $true)]
    [HttpResponseMessage]$Response,

    [Parameter(Mandatory = $true)]
    [string]$EndpointPath,

    [Parameter()]
    [switch]$UseCache,

    [Parameter()]
    [int]$RetryCount = 3,

    [Parameter()]
    [timespan]$RetryInterval = [timespan]::FromSeconds(2)
)

begin {
    # Import Newtonsoft.Json for high-performance JSON processing
    Add-Type -AssemblyName "Newtonsoft.Json, Version=13.0.1.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed"

    # Constants for response processing
    $script:SecurityHeaders = @(
        'X-Content-Type-Options',
        'X-Frame-Options',
        'X-XSS-Protection',
        'Strict-Transport-Security'
    )

    # Rate limiting headers
    $script:RateLimitHeaders = @{
        'X-RateLimit-Limit' = $null
        'X-RateLimit-Remaining' = $null
        'X-RateLimit-Reset' = $null
    }
}

process {
    try {
        # Extract correlation ID from response headers
        $correlationId = $Response.Headers.GetValues('X-Correlation-ID') | 
            Select-Object -First 1 ?? [Guid]::NewGuid().ToString()

        # Validate security headers
        $missingSecurityHeaders = $script:SecurityHeaders.Where({
            -not $Response.Headers.Contains($_)
        })

        if ($missingSecurityHeaders) {
            Write-CompassOneLog -Message "Missing security headers detected" `
                               -Level 'Warning' `
                               -Source 'ApiResponse' `
                               -Context @{
                                   'CorrelationId' = $correlationId
                                   'MissingHeaders' = $missingSecurityHeaders
                               }
        }

        # Process rate limiting headers
        foreach ($header in $script:RateLimitHeaders.Keys) {
            if ($Response.Headers.Contains($header)) {
                $script:RateLimitHeaders[$header] = $Response.Headers.GetValues($header) |
                    Select-Object -First 1
            }
        }

        # Check if we're approaching rate limits
        if ($script:RateLimitHeaders['X-RateLimit-Remaining'] -and 
            [int]$script:RateLimitHeaders['X-RateLimit-Remaining'] -lt 10) {
            Write-CompassOneLog -Message "Approaching rate limit" `
                               -Level 'Warning' `
                               -Source 'ApiResponse' `
                               -Context $script:RateLimitHeaders
        }

        # Process response based on status code
        switch ($Response.StatusCode) {
            # Success responses
            { $_ -ge 200 -and $_ -lt 300 } {
                # Read response content with timeout protection
                $contentTask = $Response.Content.ReadAsStringAsync()
                if (-not $contentTask.Wait(30000)) {
                    throw "Response content read timeout"
                }
                $content = $contentTask.Result

                # Validate and parse JSON response
                if (-not [string]::IsNullOrEmpty($content)) {
                    try {
                        $parsedContent = [Newtonsoft.Json.JsonConvert]::DeserializeObject(
                            $content,
                            [Newtonsoft.Json.JsonSerializerSettings]@{
                                DateParseHandling = [Newtonsoft.Json.DateParseHandling]::DateTimeOffset
                                MaxDepth = 32
                                TypeNameHandling = [Newtonsoft.Json.TypeNameHandling]::None
                            }
                        )

                        # Cache successful response if requested
                        if ($UseCache -and $parsedContent) {
                            $cacheKey = "API:$EndpointPath"
                            $null = Set-CompassOneCache -Key $cacheKey -Value $parsedContent
                        }

                        # Return processed response
                        return $parsedContent
                    }
                    catch {
                        throw "JSON parsing error: $($_.Exception.Message)"
                    }
                }
                return $null
            }

            # Rate limit exceeded
            429 {
                $retryAfter = if ($Response.Headers.Contains('Retry-After')) {
                    [int]($Response.Headers.GetValues('Retry-After') | Select-Object -First 1)
                } else {
                    30 # Default retry delay
                }

                Write-CompassOneLog -Message "Rate limit exceeded" `
                                   -Level 'Warning' `
                                   -Source 'ApiResponse' `
                                   -Context @{
                                       'CorrelationId' = $correlationId
                                       'RetryAfter' = $retryAfter
                                   }

                if ($RetryCount -gt 0) {
                    Start-Sleep -Seconds $retryAfter
                    return $false # Signal retry needed
                }
                
                throw "Rate limit exceeded and no retries remaining"
            }

            # Client errors
            { $_ -ge 400 -and $_ -lt 500 } {
                $errorContent = $Response.Content.ReadAsStringAsync().Result
                $errorDetails = @{
                    'StatusCode' = $Response.StatusCode
                    'ReasonPhrase' = $Response.ReasonPhrase
                    'Content' = $errorContent
                    'CorrelationId' = $correlationId
                }

                Write-CompassOneError -ErrorCategory 'InvalidOperation' `
                                     -ErrorCode 7002 `
                                     -ErrorDetails $errorDetails `
                                     -ErrorAction 'Stop'
            }

            # Server errors
            { $_ -ge 500 } {
                if ($RetryCount -gt 0) {
                    # Implement exponential backoff
                    $delay = $RetryInterval.TotalSeconds * [Math]::Pow(2, 3 - $RetryCount)
                    Start-Sleep -Seconds $delay
                    return $false # Signal retry needed
                }

                $errorContent = $Response.Content.ReadAsStringAsync().Result
                $errorDetails = @{
                    'StatusCode' = $Response.StatusCode
                    'ReasonPhrase' = $Response.ReasonPhrase
                    'Content' = $errorContent
                    'CorrelationId' = $correlationId
                }

                Write-CompassOneError -ErrorCategory 'ConnectionError' `
                                     -ErrorCode 2001 `
                                     -ErrorDetails $errorDetails `
                                     -ErrorAction 'Stop'
            }
        }
    }
    catch {
        # Handle unexpected errors
        Write-CompassOneError -ErrorCategory 'InvalidOperation' `
                             -ErrorCode 7003 `
                             -ErrorDetails @{
                                 'Operation' = 'ProcessApiResponse'
                                 'EndpointPath' = $EndpointPath
                                 'Error' = $_.Exception.Message
                                 'CorrelationId' = $correlationId
                             } `
                             -ErrorAction 'Stop'
    }
    finally {
        # Ensure proper disposal of response
        if ($Response) {
            if ($Response.Content) {
                $Response.Content.Dispose()
            }
            $Response.Dispose()
        }

        # Clean up sensitive data
        if ($content) {
            $content = $null
        }
        if ($parsedContent) {
            $parsedContent = $null
        }
        [System.GC]::Collect()
    }
}