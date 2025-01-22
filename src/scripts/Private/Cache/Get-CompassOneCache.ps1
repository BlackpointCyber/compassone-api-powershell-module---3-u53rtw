using namespace System.Collections.Concurrent

#Requires -Version 5.1

<#
.SYNOPSIS
    Retrieves items from the PSCompassOne module's thread-safe memory cache.

.DESCRIPTION
    Private function that implements high-performance, thread-safe cache retrieval with 
    proper expiration checking, memory management, and comprehensive logging. Uses 
    ConcurrentDictionary for atomic operations and implements performance monitoring.

.PARAMETER Key
    The unique key to lookup in the cache.

.OUTPUTS
    PSObject
    Returns the cached value if found and not expired, null otherwise.

.NOTES
    File Name      : Get-CompassOneCache.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Required Modules: System.Collections.Concurrent v4.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Key
)

begin {
    # Constants for cache management
    $script:CacheCleanupThreshold = 100MB
    $script:PerformanceThreshold = 100 # milliseconds
}

process {
    try {
        $startTime = [System.Diagnostics.Stopwatch]::StartNew()

        # Validate cache initialization
        if (-not $Script:CompassOneCache) {
            $Script:CompassOneCache = [ConcurrentDictionary[string, PSObject]]::new()
            Write-CompassOneLog -Message "Cache initialized" -Level Information -Source "Cache" -Context @{
                Operation = "Initialize"
                CacheSize = 0
            }
        }

        # Attempt thread-safe cache lookup
        $cacheEntry = $null
        $found = $Script:CompassOneCache.TryGetValue($Key, [ref]$cacheEntry)

        if ($found) {
            # Check expiration with atomic operations
            if ($cacheEntry.Expiration -gt [DateTime]::UtcNow) {
                # Cache hit - log with performance metrics
                $elapsed = $startTime.ElapsedMilliseconds
                Write-CompassOneLog -Message "Cache hit" -Level Verbose -Source "Cache" -Context @{
                    Operation = "Get"
                    Key = $Key
                    ElapsedMs = $elapsed
                    CacheSize = $Script:CompassOneCache.Count
                }

                # Performance monitoring
                if ($elapsed -gt $script:PerformanceThreshold) {
                    Write-CompassOneLog -Message "Cache retrieval exceeded performance threshold" -Level Warning -Source "Cache" -Context @{
                        Operation = "Performance"
                        Key = $Key
                        ElapsedMs = $elapsed
                        Threshold = $script:PerformanceThreshold
                    }
                }

                return $cacheEntry.Value
            }
            else {
                # Remove expired entry atomically
                $null = $Script:CompassOneCache.TryRemove($Key, [ref]$cacheEntry)
                Write-CompassOneLog -Message "Removed expired cache entry" -Level Verbose -Source "Cache" -Context @{
                    Operation = "Expire"
                    Key = $Key
                    ExpiredAt = $cacheEntry.Expiration
                }
            }
        }

        # Check memory usage and cleanup if needed
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        if ($currentProcess.PrivateMemorySize64 -gt $script:CacheCleanupThreshold) {
            # Cleanup expired entries
            $expiredKeys = $Script:CompassOneCache.Keys.Where({
                $entry = $null
                $Script:CompassOneCache.TryGetValue($_, [ref]$entry) -and 
                $entry.Expiration -lt [DateTime]::UtcNow
            })

            foreach ($expiredKey in $expiredKeys) {
                $null = $Script:CompassOneCache.TryRemove($expiredKey, [ref]$null)
            }

            Write-CompassOneLog -Message "Performed cache cleanup" -Level Information -Source "Cache" -Context @{
                Operation = "Cleanup"
                RemovedEntries = $expiredKeys.Count
                MemoryUsage = $currentProcess.PrivateMemorySize64
                Threshold = $script:CacheCleanupThreshold
            }

            [System.GC]::Collect()
        }

        # Cache miss - log with context
        $elapsed = $startTime.ElapsedMilliseconds
        Write-CompassOneLog -Message "Cache miss" -Level Verbose -Source "Cache" -Context @{
            Operation = "Get"
            Key = $Key
            ElapsedMs = $elapsed
            CacheSize = $Script:CompassOneCache.Count
        }

        return $null
    }
    catch {
        # Log error with full context
        Write-CompassOneLog -Message "Cache operation failed: $_" -Level Error -Source "Cache" -Context @{
            Operation = "Get"
            Key = $Key
            Exception = $_.Exception.ToString()
        }
        throw
    }
    finally {
        if ($startTime) {
            $startTime.Stop()
        }
    }
}