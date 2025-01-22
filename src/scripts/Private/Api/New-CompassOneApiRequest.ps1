using namespace System.Net.Http # Version 7.0.0
using namespace System.Security # Version 4.0.0

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Creates standardized HTTP request objects for the CompassOne API.

.DESCRIPTION
    Private function that creates secure and properly configured HttpRequestMessage objects
    for CompassOne API communication. Implements comprehensive security controls, request
    tracing, and error handling.

.PARAMETER EndpointPath
    The API endpoint path (e.g., /assets, /findings).

.PARAMETER Method
    The HTTP method for the request (GET, POST, PUT, DELETE).

.PARAMETER Body
    Optional. The request body object to be serialized to JSON.

.PARAMETER QueryParameters
    Optional. Hashtable of query string parameters.

.OUTPUTS
    System.Net.Http.HttpRequestMessage
    Returns a fully configured request message with security headers and authentication.

.NOTES
    File Name      : New-CompassOneApiRequest.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: Newtonsoft.Json v13.0.1
                     System.Net.Http v7.0.0
#>

[CmdletBinding()]
[OutputType([System.Net.Http.HttpRequestMessage])]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^/[a-zA-Z0-9/-]+$')]
    [string]$EndpointPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
    [string]$Method,

    [Parameter()]
    [PSObject]$Body,

    [Parameter()]
    [hashtable]$QueryParameters
)

begin {
    # Constants
    $API_VERSION = 'v1'
    $DEFAULT_HEADERS = @{
        'Accept' = 'application/json'
        'Content-Type' = 'application/json'
        'User-Agent' = 'PSCompassOne/1.0'
        'X-API-Version' = $API_VERSION
        'Strict-Transport-Security' = 'max-age=31536000; includeSubDomains'
        'X-Content-Type-Options' = 'nosniff'
        'X-Frame-Options' = 'DENY'
        'X-XSS-Protection' = '1; mode=block'
    }
    $REQUEST_TIMEOUT = 30
    $MAX_RETRIES = 3

    # Generate correlation ID for request tracking
    $correlationId = [guid]::NewGuid().ToString()
}

process {
    try {
        Write-CompassOneLog -Message "Creating API request" `
                           -Level Information `
                           -Source "ApiClient" `
                           -Context @{
                               CorrelationId = $correlationId
                               Method = $Method
                               Endpoint = $EndpointPath
                           }

        # Get authentication token
        $authToken = Get-CompassOneToken -ErrorAction Stop
        if (-not $authToken) {
            throw "Failed to obtain authentication token"
        }

        # Validate token
        $tokenValid = Test-CompassOneToken -Token $authToken -CorrelationId $correlationId
        if (-not $tokenValid) {
            throw "Invalid authentication token"
        }

        # Create new request message
        $request = New-Object HttpRequestMessage -ArgumentList @(
            [HttpMethod]$Method,
            [Uri]::new([string]::Empty)  # URI will be set after base URL configuration
        )

        # Build full URI with query parameters
        $uriBuilder = New-Object UriBuilder
        $uriBuilder.Path = "api/$API_VERSION$EndpointPath"

        if ($QueryParameters) {
            $queryString = [System.Web.HttpUtility]::ParseQueryString([string]::Empty)
            foreach ($param in $QueryParameters.GetEnumerator()) {
                if ($null -ne $param.Value) {
                    $queryString.Add($param.Key, $param.Value.ToString())
                }
            }
            $uriBuilder.Query = $queryString.ToString()
        }

        $request.RequestUri = $uriBuilder.Uri

        # Add standard headers
        foreach ($header in $DEFAULT_HEADERS.GetEnumerator()) {
            $request.Headers.Add($header.Key, $header.Value)
        }

        # Add security and tracing headers
        $request.Headers.Add('X-Request-ID', $correlationId)
        $request.Headers.Add('X-Correlation-ID', $correlationId)

        # Add authentication header
        $tokenString = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($authToken)
        )
        $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue(
            "Bearer", $tokenString
        )

        # Add request body if provided
        if ($Body) {
            try {
                $jsonContent = [Newtonsoft.Json.JsonConvert]::SerializeObject(
                    $Body,
                    [Newtonsoft.Json.Formatting]::None,
                    (New-Object Newtonsoft.Json.JsonSerializerSettings -Property @{
                        NullValueHandling = [Newtonsoft.Json.NullValueHandling]::Ignore
                        DateFormatString = "yyyy-MM-ddTHH:mm:ss.fffZ"
                    })
                )
                $request.Content = New-Object StringContent(
                    $jsonContent,
                    [System.Text.Encoding]::UTF8,
                    "application/json"
                )
            }
            catch {
                Write-CompassOneError -ErrorCategory ValidationError `
                                    -ErrorCode 3001 `
                                    -ErrorDetails @{
                                        Message = "Failed to serialize request body"
                                        CorrelationId = $correlationId
                                        Error = $_.Exception.Message
                                    } `
                                    -ErrorAction Stop
            }
        }

        # Configure request properties
        $request.Properties.Add("RequestTimeout", $REQUEST_TIMEOUT)
        $request.Properties.Add("MaxRetries", $MAX_RETRIES)

        # Log request creation success
        Write-CompassOneLog -Message "Successfully created API request" `
                           -Level Verbose `
                           -Source "ApiClient" `
                           -Context @{
                               CorrelationId = $correlationId
                               Method = $Method
                               Endpoint = $EndpointPath
                               HasBody = $null -ne $Body
                           }

        return $request
    }
    catch {
        # Handle specific error categories
        $errorCode = switch -Regex ($_.Exception.Message) {
            'token' { 2001 }      # Token-related errors
            'serialize' { 2002 }   # Serialization errors
            'uri' { 2003 }        # URI construction errors
            default { 2000 }      # General request creation errors
        }

        Write-CompassOneError -ErrorCategory ConnectionError `
                             -ErrorCode $errorCode `
                             -ErrorDetails @{
                                 Message = "Failed to create API request: $($_.Exception.Message)"
                                 CorrelationId = $correlationId
                                 Method = $Method
                                 Endpoint = $EndpointPath
                             } `
                             -ErrorAction Stop
        throw
    }
    finally {
        # Clean up sensitive data
        if ($tokenString) {
            $tokenString = "0" * $tokenString.Length
        }
        if ($authToken) {
            $authToken.Dispose()
        }
        [System.GC]::Collect()
    }
}