@{
    # API Settings - Core API configuration with security controls
    ApiSettings = @{
        Endpoint = 'https://api.compassone.blackpoint.io'
        Version = 'v1'
        Timeout = 30  # Seconds
        RetryAttempts = 3
        RateLimitPerMinute = 300
        EnableCompression = $true
    }

    # Connection Settings - Enhanced security and reliability configuration
    ConnectionSettings = @{
        UseSecureConnection = $true
        ValidateCertificate = $true
        ConnectionTimeout = 30  # Seconds
        MinimumTlsVersion = '1.2'
        MaxConcurrentConnections = 10
        EnableKeepAlive = $true
        ConnectionPooling = @{
            Enabled = $true
            MinPoolSize = 1
            MaxPoolSize = 10
            PoolIdleTimeout = 300  # Seconds
        }
    }

    # Cache Settings - Performance optimization with security considerations
    CacheSettings = @{
        EnableCache = $true
        CacheDuration = 300  # Seconds
        MaxCacheSize = 100  # MB
        CacheStrategy = 'LRU'  # Least Recently Used
        EnableCompression = $true
        MinimumCacheHits = 2
        TypeCaching = @{
            Asset = $true
            Finding = $true
            Incident = $true
        }
        ExcludeFromCache = @(
            'SecureString',
            'PSCredential'
        )
    }

    # Logging Settings - Comprehensive audit and troubleshooting support
    LoggingSettings = @{
        LogLevel = 'Information'  # Debug, Information, Warning, Error
        LogPath = '$env:ProgramData\PSCompassOne\Logs'
        EnableVerboseLogging = $false
        EnablePerformanceLogging = $true
        MaxLogSizeMB = 100
        LogRetentionDays = 30
        AuditLogging = @{
            Enabled = $true
            IncludeUserIdentity = $true
            IncludeHostDetails = $true
            SignLogs = $true
        }
    }

    # Security Settings - Enhanced security controls and compliance
    SecuritySettings = @{
        EnforceHttps = $true
        ValidateCertificateChain = $true
        EnableAuditLogging = $true
        AllowedIpRanges = @('*')  # Restrict if needed
        EnableEncryption = $true
        EncryptionKeyPath = '$env:ProgramData\PSCompassOne\Keys'
        Authentication = @{
            RequireSecureCredentials = $true
            TokenExpirationMinutes = 60
            MaxFailedAttempts = 3
            LockoutDurationMinutes = 15
        }
        Compliance = @{
            EnforceFips = $true
            RequireModuleSigning = $true
            ValidateHashAlgorithm = 'SHA512'
        }
    }

    # Performance Settings - Optimization configuration
    PerformanceSettings = @{
        MaxParallelOperations = 10
        BatchSize = 100
        EnableConnectionPooling = $true
        PoolSize = 10
        CommandTimeout = 300  # Seconds
        EnableAsyncOperations = $true
        ResourceManagement = @{
            MaxMemoryMB = 1024
            GarbageCollectionThreshold = 80  # Percent
            EnableMemoryOptimization = $true
        }
        Throttling = @{
            Enabled = $true
            RequestsPerSecond = 50
            BurstSize = 100
            EnableAdaptiveThrottling = $true
        }
    }

    # Type Configuration - Enhanced type system integration
    TypeSettings = @{
        Asset = @{
            DefaultDisplayProperties = @('Id', 'Name', 'AssetClass', 'Status', 'LastSeenOn')
            ValidationRules = @{
                RequireUniqueNames = $true
                ValidateRelationships = $true
                EnforceStatusFlow = $true
            }
        }
        Finding = @{
            DefaultDisplayProperties = @('Id', 'Title', 'Severity', 'Status', 'Score')
            ValidationRules = @{
                RequireSeverityScore = $true
                ValidateStatusTransitions = $true
                EnforceRelatedAssets = $true
            }
        }
        Incident = @{
            DefaultDisplayProperties = @('Id', 'Title', 'Priority', 'Status', 'AssignedTo')
            ValidationRules = @{
                RequirePriority = $true
                ValidateWorkflow = $true
                EnforceResolutionFlow = $true
            }
        }
    }

    # Module Behavior Settings - General module configuration
    ModuleSettings = @{
        StrictMode = $true
        ErrorActionPreference = 'Stop'
        WarningPreference = 'Continue'
        VerbosePreference = 'SilentlyContinue'
        DebugPreference = 'SilentlyContinue'
        ProgressPreference = 'Continue'
        FormatEnumerationLimit = 16
        DefaultParameterValues = @{
            'Confirm:$false' = $true
            'Verbose:$false' = $false
            'Debug:$false' = $false
        }
    }
}