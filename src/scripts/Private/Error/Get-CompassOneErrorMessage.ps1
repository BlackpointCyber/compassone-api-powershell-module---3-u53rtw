#Requires -Version 5.1
using namespace System.Management.Automation # Version 7.0.0

<#
.SYNOPSIS
    Generates standardized error messages for the PSCompassOne module.

.DESCRIPTION
    Private function that generates standardized error messages based on error categories and codes.
    Provides consistent error message formatting with support for detailed error information and
    proper error code formatting across the PSCompassOne module.

.PARAMETER ErrorCategory
    The category of the error. Must be one of the predefined error categories.

.PARAMETER ErrorCode
    The numeric error code (1000-9999) that identifies the specific error.

.PARAMETER ErrorDetails
    Optional hashtable containing additional error details to be included in the message.

.OUTPUTS
    System.String. Returns a formatted error message string.

.NOTES
    Private function for internal module use only.
    Error Code Ranges:
    - Authentication (1000-1999)
    - Connection (2000-2999)
    - Validation (3000-3999)
    - Resource (4000-4999)
    - Operation (5000-5999)
    - Security (6000-6999)
    - General (7000-7999)
    - Limit (8000-8999)
#>
function Get-CompassOneErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'AuthenticationError',
            'ConnectionError',
            'ValidationError',
            'ResourceNotFound',
            'OperationTimeout',
            'SecurityError',
            'InvalidOperation',
            'LimitExceeded'
        )]
        [string]$ErrorCategory,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1000, 9999)]
        [int]$ErrorCode,

        [Parameter(Mandatory = $false)]
        [hashtable]$ErrorDetails
    )

    begin {
        # Define error message templates
        $errorTemplates = @{
            AuthenticationError = 'Authentication failed: {0}. [Code: {1}] {2}'
            ConnectionError    = 'Connection error: {0}. [Code: {1}] {2}'
            ValidationError    = 'Validation failed: {0}. [Code: {1}] {2}'
            ResourceNotFound   = 'Resource not found: {0}. [Code: {1}] {2}'
            OperationTimeout   = 'Operation timed out: {0}. [Code: {1}] {2}'
            SecurityError      = 'Security violation: {0}. [Code: {1}] {2}'
            InvalidOperation   = 'Invalid operation: {0}. [Code: {1}] {2}'
            LimitExceeded      = 'Limit exceeded: {0}. [Code: {1}] {2}'
        }

        # Validate error code ranges
        $errorCodeRanges = @{
            AuthenticationError = 1000..1999
            ConnectionError    = 2000..2999
            ValidationError    = 3000..3999
            ResourceNotFound   = 4000..4999
            OperationTimeout   = 5000..5999
            SecurityError      = 6000..6999
            InvalidOperation   = 7000..7999
            LimitExceeded      = 8000..8999
        }
    }

    process {
        try {
            # Validate error code is in the correct range for the category
            if (-not ($errorCodeRanges[$ErrorCategory] -contains $ErrorCode)) {
                throw "Error code $ErrorCode is not valid for category $ErrorCategory"
            }

            # Format the error code with proper padding
            $formattedErrorCode = "ERR-{0:D4}" -f $ErrorCode

            # Initialize the base error message
            $baseMessage = "An error occurred"
            $additionalDetails = ""

            # Process error details if provided
            if ($ErrorDetails) {
                # Sanitize and validate error details
                $sanitizedDetails = foreach ($key in $ErrorDetails.Keys) {
                    $value = [System.Web.HttpUtility]::HtmlEncode($ErrorDetails[$key])
                    "$key`: $value"
                }
                $additionalDetails = $sanitizedDetails -join "; "
            }

            # Get the appropriate message template
            $template = $errorTemplates[$ErrorCategory]

            # Format the final message using culture-invariant formatting
            $errorMessage = [string]::Format(
                [System.Globalization.CultureInfo]::InvariantCulture,
                $template,
                $baseMessage,
                $formattedErrorCode,
                $additionalDetails
            )

            # Return the formatted error message
            return $errorMessage.Trim()
        }
        catch {
            # Handle any errors in message generation
            $fallbackMessage = "Error message generation failed. Original error: $($_.Exception.Message)"
            Write-Warning $fallbackMessage
            return $fallbackMessage
        }
    }
}