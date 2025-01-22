using namespace System.Collections.Concurrent

#Requires -Version 5.1

<#
.SYNOPSIS
    Clears the PSCompassOne module's in-memory cache in a thread-safe manner.

.DESCRIPTION
    Private function that implements a thread-safe mechanism for clearing the PSCompassOne module's
    in-memory cache. Provides secure cleanup of cached API responses and session data with
    comprehensive logging, error handling, and memory optimization features.

.PARAMETER Force
    Bypasses the confirmation prompt when clearing the cache.

.NOTES
    File Name      : Clear-CompassOneCache.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
    Required Modules: System.Collections.Concurrent v4.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Force
)

begin {
    # Constants for memory tracking
    $BYTES_TO_MB = 1MB
    $GC_GENERATIONS = 2
}

process {
    try {
        # Verify cache instance exists
        if (-not $Script:CompassOneCache -or 
            -not ($Script:CompassOneCache -is [ConcurrentDictionary[string, object]])) {
            throw "Cache instance not initialized or invalid"
        }

        # Create operation context for logging
        $context = @{
            CorrelationId = [guid]::NewGuid().ToString()
            Operation = "CacheClear"
            InitialCount = $Script:CompassOneCache.Count
            InitialMemory = [Math]::Round(([GC]::GetTotalMemory($false) / $BYTES_TO_MB), 2)
        }

        # Log operation initiation
        Write-CompassOneLog -Message "Initiating cache clear operation" `
                           -Level Information `
                           -Source "Clear-CompassOneCache" `
                           -Context $context

        # Check if operation should proceed
        $clearMessage = "Clear PSCompassOne cache containing $($context.InitialCount) items"
        if ($Force -or $PSCmdlet.ShouldProcess($clearMessage, "Clear Cache", "Clear PSCompassOne Cache")) {
            # Acquire lock using monitor for thread safety
            $lockTaken = $false
            try {
                [System.Threading.Monitor]::Enter($Script:CompassOneCache, [ref]$lockTaken)

                if ($lockTaken) {
                    # Clear all items from cache
                    $Script:CompassOneCache.Clear()

                    # Verify cache is empty
                    if ($Script:CompassOneCache.Count -ne 0) {
                        throw "Cache clear operation failed - items still present"
                    }

                    # Dispose of any disposable cached items
                    foreach ($item in $Script:CompassOneCache.Values) {
                        if ($item -is [System.IDisposable]) {
                            $item.Dispose()
                        }
                    }

                    # Force garbage collection
                    [GC]::Collect($GC_GENERATIONS, [GCCollectionMode]::Forced, $true, $true)

                    # Calculate memory metrics
                    $finalMemory = [Math]::Round(([GC]::GetTotalMemory($true) / $BYTES_TO_MB), 2)
                    $memoryFreed = [Math]::Round(($context.InitialMemory - $finalMemory), 2)

                    # Update context with results
                    $context["FinalMemory"] = $finalMemory
                    $context["MemoryFreed"] = $memoryFreed
                    $context["Success"] = $true

                    # Log successful completion
                    Write-CompassOneLog -Message "Cache successfully cleared. Memory freed: $memoryFreed MB" `
                                       -Level Information `
                                       -Source "Clear-CompassOneCache" `
                                       -Context $context
                }
                else {
                    throw "Failed to acquire cache lock for clear operation"
                }
            }
            finally {
                # Release lock if acquired
                if ($lockTaken) {
                    [System.Threading.Monitor]::Exit($Script:CompassOneCache)
                }
            }
        }
        else {
            # Log operation cancellation
            $context["Cancelled"] = $true
            Write-CompassOneLog -Message "Cache clear operation cancelled by user" `
                               -Level Information `
                               -Source "Clear-CompassOneCache" `
                               -Context $context
        }
    }
    catch {
        # Prepare error context
        $errorContext = @{
            CorrelationId = $context.CorrelationId
            Operation = "CacheClear"
            ErrorMessage = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        }

        # Log error
        Write-CompassOneLog -Message "Failed to clear cache: $($_.Exception.Message)" `
                           -Level Error `
                           -Source "Clear-CompassOneCache" `
                           -Context $errorContext

        # Re-throw error
        throw
    }
}