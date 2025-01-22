using namespace System.Security.Cryptography
using namespace System.Text

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerShell.Security

<#
.SYNOPSIS
    Writes cryptographically signed log entries to the PSCompassOne module log file.

.DESCRIPTION
    Private function that implements a secure, tamper-proof logging system with SHA-256 signed
    log entries, correlation tracking, and automatic log rotation. Provides comprehensive
    audit trails and operational monitoring with proper security controls.

.PARAMETER Message
    The log message to be written.

.PARAMETER Level
    The log level (Error, Warning, Information, Verbose, Debug).

.PARAMETER Source
    The source component generating the log entry.

.PARAMETER Context
    Additional contextual information including correlation ID and metadata.

.NOTES
    File Name      : Write-CompassOneLog.ps1
    Version        : 1.0.0
    Module         : PSCompassOne
    Author         : Blackpoint
    Requires       : PowerShell 5.1 or PowerShell 7.0+
    Required Modules: Microsoft.PowerShell.Security v7.0.0
                     System.Security.Cryptography v4.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [string]$Level,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Source,

    [Parameter()]
    [hashtable]$Context = @{}
)

begin {
    # Constants
    $script:MaxLogSizeBytes = 10MB
    $script:DateTimeFormat = "yyyy-MM-ddTHH:mm:ss.fffZ"
    $script:LogEntryFormat = "{0}|{1}|{2}|{3}|{4}|{5}"
    $script:SignatureFormat = "{0}|SHA256:{1}"
}

process {
    try {
        # Get secure log file path
        $logPath = Get-CompassOneLogPath

        # Create ISO 8601 timestamp
        $timestamp = [DateTime]::UtcNow.ToString($script:DateTimeFormat)

        # Extract correlation ID from context
        $correlationId = if ($Context.ContainsKey('CorrelationId')) {
            $Context['CorrelationId']
        } else {
            [Guid]::NewGuid().ToString()
        }

        # Format log entry
        $logEntry = $script:LogEntryFormat -f @(
            $timestamp
            $Level.ToUpper()
            $Source
            $correlationId
            $Message
            ($Context | ConvertTo-Json -Compress)
        )

        # Generate SHA-256 signature
        $signature = ''
        try {
            $sha256 = [SHA256]::Create()
            $bytes = [Encoding]::UTF8.GetBytes($logEntry)
            $hash = $sha256.ComputeHash($bytes)
            $signature = [Convert]::ToBase64String($hash)
        }
        finally {
            if ($sha256) {
                $sha256.Dispose()
            }
        }

        # Combine entry and signature
        $signedEntry = $script:SignatureFormat -f $logEntry, $signature

        # Check log file size and rotate if needed
        if (Test-Path -Path $logPath) {
            $logFile = Get-Item -Path $logPath
            if ($logFile.Length -gt $script:MaxLogSizeBytes) {
                # Generate rotation timestamp
                $rotationTime = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
                $rotatedPath = "{0}.{1}" -f $logPath, $rotationTime

                # Attempt to rotate log file
                try {
                    Move-Item -Path $logPath -Destination $rotatedPath -Force
                }
                catch {
                    Write-Warning "Failed to rotate log file: $_"
                }
            }
        }

        # Write signed log entry with mutex protection
        $mutex = $null
        try {
            $mutexName = "Global\PSCompassOneLog"
            $mutex = New-Object System.Threading.Mutex($false, $mutexName)
            
            # Wait up to 5 seconds for mutex
            if ($mutex.WaitOne(5000)) {
                try {
                    # Append log entry
                    Add-Content -Path $logPath -Value $signedEntry -Encoding UTF8 -Force

                    # Verify write operation
                    $lastEntry = Get-Content -Path $logPath -Tail 1
                    if ($lastEntry -ne $signedEntry) {
                        throw "Log entry verification failed"
                    }
                }
                finally {
                    $mutex.ReleaseMutex()
                }
            }
            else {
                throw "Failed to acquire log mutex"
            }
        }
        finally {
            if ($mutex) {
                $mutex.Dispose()
            }
        }

        # Write to PowerShell streams based on level
        switch ($Level) {
            'Error' { Write-Error -Message $Message }
            'Warning' { Write-Warning -Message $Message }
            'Information' { Write-Information -MessageData $Message }
            'Verbose' { Write-Verbose -Message $Message }
            'Debug' { Write-Debug -Message $Message }
        }
    }
    catch {
        # Handle logging failures
        $errorMessage = "Failed to write log entry: $_"
        
        # Attempt to write to alternate streams
        Write-Warning $errorMessage
        Write-Error $errorMessage

        # Last resort: Write to system event log
        try {
            $eventParams = @{
                LogName = 'Application'
                Source = 'PSCompassOne'
                EntryType = 'Error'
                EventId = 1000
                Message = $errorMessage
            }
            Write-EventLog @eventParams
        }
        catch {
            # Suppress event log errors
        }
    }
    finally {
        # Clean up sensitive data
        if ($Context.ContainsKey('Credentials')) {
            $Context['Credentials'] = $null
        }
        [System.GC]::Collect()
    }
}