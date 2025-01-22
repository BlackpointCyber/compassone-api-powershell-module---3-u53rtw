using namespace System.Collections.Concurrent # Version 7.0.0
using namespace System.Security.Cryptography

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Sets a value in the PSCompassOne module's thread-safe memory cache.

.DESCRIPTION
    Private function that implements a thread-safe, secure caching system for the PSCompassOne module.
    Provides configurable cache entry management with expiration, memory optimization, and comprehensive
    error handling. Ensures data protection through secure handling and proper cleanup of sensitive information.

.PARAMETER Key
    The unique key for the cache entry.

.PARAMETER Value
    The value to be cached.

.PARAMETER TimeToLive
    Optional. The time span for which the cache entry should remain valid.
    Defaults to value from $env:COMPASSONE_CACHE_TTL or 3600 seconds (1 hour).

.OUTPUTS
    System.Boolean
    Returns True if cache operation succeeds, False if operation fails.

.NOTES
    File Name      : Set-CompassOneCache.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Key,

    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Value,

    [Parameter(Mandatory = $false)]
    [TimeSpan]$TimeToLive = (New-TimeSpan -Seconds ([int]($env:COMPASSONE_CACHE_TTL ?? 3600)))
)

begin {
    # Initialize thread-safe cache if not exists
    if (-not $Script:CompassOneCache) {
        $Script:CompassOneCache = [ConcurrentDictionary[string, PSObject]]::new()
    }

    # Memory pressure threshold (70%)
    $MEMORY_THRESHOLD = 0.7
}

process {
    try {
        Write-Verbose "Setting cache entry for key: $Key"

        # Check memory pressure
        $memoryInfo = [System.GC]::GetTotalMemory($false)
        $memoryLimit = [System.Environment]::WorkingSet
        $memoryUsage = $memoryInfo / $memoryLimit

        if ($memoryUsage -gt $MEMORY_THRESHOLD) {
            Write-Verbose "Memory pressure detected ($([math]::Round($memoryUsage * 100))%). Initiating cache cleanup."
            
            # Remove expired entries
            $expiredKeys = $Script:CompassOneCache.Keys.Where({
                $Script:CompassOneCache[$_].ExpiresAt -lt [DateTime]::UtcNow
            })
            
            foreach ($expiredKey in $expiredKeys) {
                $null = $Script:CompassOneCache.TryRemove($expiredKey, [ref]$null)
            }
            
            [System.GC]::Collect()
        }

        # Create secure cache entry
        $cacheEntry = [PSCustomObject]@{
            Value = $Value
            ExpiresAt = [DateTime]::UtcNow.Add($TimeToLive)
            CreatedAt = [DateTime]::UtcNow
            Hash = $null
        }

        # Generate hash for integrity checking
        if ($Value) {
            try {
                $sha256 = [SHA256]::Create()
                $valueBytes = [System.Text.Encoding]::UTF8.GetBytes(
                    ($Value | ConvertTo-Json -Compress -Depth 10)
                )
                $hashBytes = $sha256.ComputeHash($valueBytes)
                $cacheEntry.Hash = [Convert]::ToBase64String($hashBytes)
            }
            finally {
                if ($sha256) { $sha256.Dispose() }
            }
        }

        # Attempt to add/update cache entry with retry logic
        $maxRetries = 3
        $retryCount = 0
        $success = $false

        while (-not $success -and $retryCount -lt $maxRetries) {
            $success = $Script:CompassOneCache.AddOrUpdate(
                $Key,
                $cacheEntry,
                {
                    param($k, $existingValue)
                    $cacheEntry
                }
            ) -ne $null

            if (-not $success) {
                $retryCount++
                Start-Sleep -Milliseconds (100 * $retryCount)
            }
        }

        if (-not $success) {
            throw "Failed to set cache entry after $maxRetries attempts"
        }

        # Verify cache entry
        $verifiedEntry = $Script:CompassOneCache[$Key]
        if (-not $verifiedEntry -or $verifiedEntry.ExpiresAt -ne $cacheEntry.ExpiresAt) {
            throw "Cache entry verification failed"
        }

        # Log successful cache operation
        Write-CompassOneLog -Message "Cache entry set successfully" `
                           -Level 'Verbose' `
                           -Source 'Cache' `
                           -Context @{
                               'Key' = $Key
                               'ExpiresAt' = $cacheEntry.ExpiresAt
                               'Operation' = 'Set'
                           }

        return $true
    }
    catch {
        # Handle cache operation errors
        Write-CompassOneError -ErrorCategory 'InvalidOperation' `
                             -ErrorCode 7001 `
                             -ErrorDetails @{
                                 'Operation' = 'SetCache'
                                 'Key' = $Key
                                 'Error' = $_.Exception.Message
                             } `
                             -ErrorAction $ErrorActionPreference

        return $false
    }
    finally {
        # Clean up sensitive data
        if ($cacheEntry) {
            $cacheEntry.Value = $null
            $cacheEntry.Hash = $null
        }
        [System.GC]::Collect()
    }
}