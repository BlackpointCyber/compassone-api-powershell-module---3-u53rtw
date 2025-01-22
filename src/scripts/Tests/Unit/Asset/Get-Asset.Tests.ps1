using namespace System.Management.Automation
using namespace System.Collections.Generic

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Import required modules and mock dependencies
    $modulePath = Resolve-Path (Join-Path $PSScriptRoot '../../../')
    Import-Module (Join-Path $modulePath 'Public/Asset/Get-Asset.ps1') -Force
    Import-Module (Join-Path $modulePath 'Private/Types/Asset.Types.ps1') -Force

    # Initialize test data
    $script:TestAssets = @(
        @{
            Id = 'test-asset-001'
            Name = 'TestServer01'
            Class = 'Device'
            Status = 'Active'
            Tags = @('Production', 'Critical')
            LastSeenOn = [DateTime]::UtcNow
            Description = 'Test server 1'
        },
        @{
            Id = 'test-asset-002'
            Name = 'TestContainer01'
            Class = 'Container'
            Status = 'Active'
            Tags = @('Development')
            LastSeenOn = [DateTime]::UtcNow
            Description = 'Test container 1'
        }
    )

    # Mock API client
    Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne {
        param($EndpointPath, $Method, $QueryParameters)
        
        # Return single asset for ById requests
        if ($EndpointPath -match '/assets/([^/]+)$') {
            $assetId = $matches[1]
            $asset = $script:TestAssets | Where-Object { $_.Id -eq $assetId }
            if (-not $asset) {
                throw [ItemNotFoundException]::new("Asset not found: $assetId")
            }
            return $asset
        }

        # Return paginated results for list requests
        $pageSize = $QueryParameters['page_size'] ?? 50
        $page = $QueryParameters['page'] ?? 1
        
        # Apply filters if provided
        $filteredAssets = $script:TestAssets
        if ($QueryParameters['name']) {
            $filteredAssets = $filteredAssets | Where-Object { 
                $_.Name -like $QueryParameters['name'] 
            }
        }
        if ($QueryParameters['class']) {
            $filteredAssets = $filteredAssets | Where-Object { 
                $_.Class -eq $QueryParameters['class'] 
            }
        }
        if ($QueryParameters['status']) {
            $filteredAssets = $filteredAssets | Where-Object { 
                $_.Status -eq $QueryParameters['status'] 
            }
        }
        if ($QueryParameters['tags']) {
            $tags = $QueryParameters['tags'] -split ','
            $filteredAssets = $filteredAssets | Where-Object {
                $assetTags = $_.Tags
                $tags | ForEach-Object { $assetTags -contains $_ }
            }
        }

        return @{
            items = $filteredAssets
            total_count = $filteredAssets.Count
            page = $page
            page_size = $pageSize
        }
    }

    # Mock cache functions
    Mock -CommandName Get-CompassOneCache -ModuleName PSCompassOne {
        param($Key)
        return $null
    }

    Mock -CommandName Set-CompassOneCache -ModuleName PSCompassOne {
        param($Key, $Value)
        return $true
    }
}

Describe 'Get-Asset Functionality' {
    Context 'Parameter Validation' {
        It 'Should validate Id parameter format' {
            { Get-Asset -Id '' } | Should -Throw
            { Get-Asset -Id $null } | Should -Throw
        }

        It 'Should validate PageSize range' {
            { Get-Asset -PageSize 0 } | Should -Throw
            { Get-Asset -PageSize 101 } | Should -Throw
            { Get-Asset -PageSize 50 } | Should -Not -Throw
        }

        It 'Should validate Class parameter values' {
            { Get-Asset -Class 'InvalidClass' } | Should -Throw
            { Get-Asset -Class 'Device' } | Should -Not -Throw
        }

        It 'Should validate Status parameter values' {
            { Get-Asset -Status 'InvalidStatus' } | Should -Throw
            { Get-Asset -Status 'Active' } | Should -Not -Throw
        }
    }

    Context 'Single Asset Retrieval' {
        It 'Should retrieve asset by valid ID' {
            $asset = Get-Asset -Id 'test-asset-001'
            $asset | Should -Not -BeNullOrEmpty
            $asset.Id | Should -Be 'test-asset-001'
            $asset.Name | Should -Be 'TestServer01'
            $asset.Class | Should -Be 'Device'
            $asset.Status | Should -Be 'Active'
            $asset.Tags | Should -Contain 'Production'
        }

        It 'Should throw on non-existent asset ID' {
            { Get-Asset -Id 'non-existent' } | Should -Throw
        }

        It 'Should handle API errors gracefully' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne {
                throw [System.Net.WebException]::new('API Error')
            }
            { Get-Asset -Id 'test-asset-001' } | Should -Throw
        }
    }

    Context 'Bulk Asset Retrieval' {
        It 'Should retrieve assets with pagination' {
            $assets = Get-Asset -PageSize 1 -Page 1
            $assets.Count | Should -Be 1
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should filter assets by name' {
            $assets = Get-Asset -Name 'TestServer*'
            $assets.Count | Should -Be 1
            $assets[0].Name | Should -BeLike 'TestServer*'
        }

        It 'Should filter assets by class' {
            $assets = Get-Asset -Class 'Container'
            $assets.Count | Should -Be 1
            $assets[0].Class | Should -Be 'Container'
        }

        It 'Should filter assets by tags' {
            $assets = Get-Asset -Tags 'Production'
            $assets.Count | Should -Be 1
            $assets[0].Tags | Should -Contain 'Production'
        }
    }
}

Describe 'Get-Asset Performance' {
    Context 'Response Time' {
        It 'Should complete within 2 seconds' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Get-Asset -Id 'test-asset-001'
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000
        }
    }

    Context 'Memory Usage' {
        It 'Should maintain memory usage under 100MB' {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            $null = Get-Asset -PageSize 50
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryUsed = ($finalMemory - $initialMemory) / 1MB
            $memoryUsed | Should -BeLessThan 100
        }
    }

    Context 'Caching' {
        It 'Should use cache when available' {
            Mock -CommandName Get-CompassOneCache -ModuleName PSCompassOne {
                return $script:TestAssets[0]
            }
            $asset = Get-Asset -Id 'test-asset-001' -UseCache
            Should -Invoke Get-CompassOneCache -Times 1
            Should -Not -Invoke Invoke-CompassOneApi
        }

        It 'Should bypass cache with Force parameter' {
            Mock -CommandName Get-CompassOneCache -ModuleName PSCompassOne {
                return $script:TestAssets[0]
            }
            $asset = Get-Asset -Id 'test-asset-001' -UseCache -Force
            Should -Not -Invoke Get-CompassOneCache
            Should -Invoke Invoke-CompassOneApi -Times 1
        }
    }
}

Describe 'Get-Asset Security' {
    Context 'Authentication' {
        It 'Should handle authentication failures' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne {
                throw [System.UnauthorizedAccessException]::new('Invalid API key')
            }
            { Get-Asset -Id 'test-asset-001' } | Should -Throw 'Invalid API key'
        }
    }

    Context 'Authorization' {
        It 'Should handle insufficient permissions' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne {
                throw [System.Security.SecurityException]::new('Access denied')
            }
            { Get-Asset -Id 'test-asset-001' } | Should -Throw 'Access denied'
        }
    }

    Context 'Data Protection' {
        It 'Should not expose sensitive data in errors' {
            Mock -CommandName Invoke-CompassOneApi -ModuleName PSCompassOne {
                throw [System.Exception]::new('API key: sk_live_123abc')
            }
            { Get-Asset -Id 'test-asset-001' } | Should -Not -Throw '*sk_live*'
        }
    }
}