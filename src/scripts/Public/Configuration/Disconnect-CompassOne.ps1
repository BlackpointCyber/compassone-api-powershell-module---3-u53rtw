using namespace System.Security
using namespace System.Threading

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Safely disconnects from the CompassOne platform with secure token cleanup.

.DESCRIPTION
    Public cmdlet that implements a secure disconnection from the CompassOne platform
    with comprehensive token cleanup, thread-safe state management, audit logging,
    and proper security controls.

.PARAMETER Force
    Bypasses the confirmation prompt when disconnecting.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.

.PARAMETER Confirm
    Prompts you for confirmation before running the cmdlet.

.EXAMPLE
    PS C:\> Disconnect-CompassOne
    Safely disconnects from CompassOne with confirmation prompt.

.EXAMPLE
    PS C:\> Disconnect-CompassOne -Force
    Forces disconnection without confirmation.

.NOTES
    File Name      : Disconnect-CompassOne.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [switch]$Force
)

begin {
    # Generate correlation ID for tracking
    $correlationId = "DCO-{0}-{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")), ([guid]::NewGuid().ToString())

    # Context for logging
    $logContext = @{
        CorrelationId = $correlationId
        Operation = "Disconnect"
        SessionId = $Script:CompassOneSession.SessionId
        UserAgent = $Script:CompassOneSession.UserAgent
    }
}

process {
    try {
        # Log disconnection attempt
        Write-CompassOneLog -Message "Initiating disconnection from CompassOne" `
                           -Level Information `
                           -Source "Disconnect-CompassOne" `
                           -Context $logContext

        # Verify active connection
        $tokenValid = Test-CompassOneToken -Token $Script:CompassOneToken `
                                         -CorrelationId $correlationId `
                                         -ErrorAction Stop

        if (-not $tokenValid) {
            $errorDetails = @{
                Message = "No active CompassOne connection found"
                CorrelationId = $correlationId
            }
            Write-CompassOneError -ErrorCategory InvalidOperation `
                                -ErrorCode 7001 `
                                -ErrorDetails $errorDetails `
                                -ErrorAction Stop
            return
        }

        # Confirmation message with security implications
        $confirmMessage = "Disconnecting from CompassOne will clear all session data and cached credentials"
        $caption = "Confirm CompassOne Disconnection"
        $warning = "This operation cannot be undone"

        if ($Force -or $PSCmdlet.ShouldProcess($confirmMessage, $warning, $caption)) {
            # Acquire synchronization lock for thread safety
            $lockTaken = $false
            try {
                [Monitor]::Enter($Script:CompassOneSession, [ref]$lockTaken)

                if ($lockTaken) {
                    # Clear authentication token securely
                    if ($Script:CompassOneToken -is [SecureString]) {
                        $Script:CompassOneToken.Dispose()
                        $Script:CompassOneToken = $null
                    }

                    # Clear session state atomically
                    $Script:CompassOneSession.Clear()
                    $Script:CompassOneSession = $null

                    # Clear cached data securely
                    Clear-CompassOneCache -Force -ErrorAction Stop

                    # Log successful disconnection
                    $logContext["Status"] = "Success"
                    Write-CompassOneLog -Message "Successfully disconnected from CompassOne" `
                                      -Level Information `
                                      -Source "Disconnect-CompassOne" `
                                      -Context $logContext

                    # Verify cleanup
                    if ($Script:CompassOneToken -or 
                        $Script:CompassOneSession -or 
                        ($Script:CompassOneCache -and $Script:CompassOneCache.Count -gt 0)) {
                        throw "Session cleanup verification failed"
                    }

                    # Force garbage collection for security
                    [GC]::Collect()
                }
                else {
                    throw "Failed to acquire session lock for disconnection"
                }
            }
            finally {
                # Release lock if acquired
                if ($lockTaken) {
                    [Monitor]::Exit($Script:CompassOneSession)
                }
            }
        }
        else {
            # Log cancelled operation
            $logContext["Status"] = "Cancelled"
            Write-CompassOneLog -Message "Disconnection cancelled by user" `
                              -Level Information `
                              -Source "Disconnect-CompassOne" `
                              -Context $logContext
        }
    }
    catch {
        # Prepare error context
        $errorContext = @{
            CorrelationId = $correlationId
            Message = $_.Exception.Message
            SessionState = if ($Script:CompassOneSession) { "Active" } else { "Unknown" }
            StackTrace = $_.ScriptStackTrace
        }

        # Log error with security context
        Write-CompassOneLog -Message "Failed to disconnect from CompassOne: $($_.Exception.Message)" `
                           -Level Error `
                           -Source "Disconnect-CompassOne" `
                           -Context $errorContext

        # Throw error with security-safe details
        Write-CompassOneError -ErrorCategory SecurityError `
                            -ErrorCode 6010 `
                            -ErrorDetails $errorContext `
                            -ErrorAction Stop
    }
    finally {
        # Ensure sensitive data is cleared
        $logContext = $null
        $errorContext = $null
        [GC]::Collect()
    }
}