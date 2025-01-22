using namespace System.Management.Automation
using namespace System.Security

#Requires -Version 5.1
#Requires -Modules Pester, Microsoft.PowerShell.Security

BeforeAll {
    # Import required modules and functions
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../../'
    $publicPath = Join-Path -Path $modulePath -ChildPath 'Public/Asset'
    $privatePath = Join-Path -Path $modulePath -ChildPath 'Private/Types'

    . "$publicPath/Remove-Asset.ps1"
    . "$privatePath/Asset.Types.ps1"

    # Set strict mode for better error detection
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Create test data
    $validAsset = [Asset]::new("TestAsset1", [AssetClass]::Device)
    $validAsset.Id = "test-asset-001"
    $validAsset.Status = [AssetStatus]::Active

    $validAssets = @(
        [Asset]::new("TestAsset2", [AssetClass]::Device),
        [Asset]::new("TestAsset3", [AssetClass]::Container)
    )
    $validAssets[0].Id = "test-asset-002"
    $validAssets[1].Id = "test-asset-003"

    $invalidAsset = [Asset]::new("InvalidAsset", [AssetClass]::Unknown)
    $invalidAsset.Id = "invalid-id"
    $invalidAsset.Status = [AssetStatus]::Deleted

    # Mock API client
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method)
        
        if ($EndpointPath -match '/assets/test-asset-\d{3}$' -and $Method -eq 'DELETE') {
            return $true
        }
        elseif ($EndpointPath -match '/assets/invalid-id') {
            throw "Asset not found"
        }
        elseif ($EndpointPath -match '/assets/error-') {
            throw "API error"
        }
    }

    # Mock error handler
    Mock Write-CompassOneError {
        param($ErrorCategory, $ErrorCode, $ErrorDetails)
        throw "CompassOne Error: [$ErrorCategory] $ErrorCode - $($ErrorDetails.Message)"
    }

    # Mock logging
    Mock Write-CompassOneLog { }
}

Describe 'Remove-Asset' {
    Context 'Parameter Validation' {
        It 'Should require either Id or InputObject parameter' {
            { Remove-Asset } | Should -Throw
        }

        It 'Should validate Id format' {
            { Remove-Asset -Id "invalid id format" } | Should -Throw
        }

        It 'Should accept valid Id format' {
            { Remove-Asset -Id "test-asset-001" -Force } | Should -Not -Throw
        }

        It 'Should validate InputObject type as Asset' {
            { Remove-Asset -InputObject "not an asset" } | Should -Throw
        }

        It 'Should accept valid Asset object' {
            { Remove-Asset -InputObject $validAsset -Force } | Should -Not -Throw
        }

        It 'Should validate BatchSize range' {
            { Remove-Asset -Id "test-asset-001" -BatchSize 0 } | Should -Throw
            { Remove-Asset -Id "test-asset-001" -BatchSize 101 } | Should -Throw
            { Remove-Asset -Id "test-asset-001" -BatchSize 50 -Force } | Should -Not -Throw
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept single asset through pipeline' {
            $validAsset | Remove-Asset -Force
            Should -Invoke Invoke-CompassOneApi -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $EndpointPath -eq "/assets/$($validAsset.Id)"
            }
        }

        It 'Should accept multiple assets through pipeline' {
            $validAssets | Remove-Asset -Force
            Should -Invoke Invoke-CompassOneApi -Times $validAssets.Count
        }

        It 'Should process assets in batches' {
            $batchSize = 2
            $largeAssetSet = 1..5 | ForEach-Object {
                $asset = [Asset]::new("BatchAsset$_", [AssetClass]::Device)
                $asset.Id = "test-asset-00$_"
                $asset
            }
            
            $largeAssetSet | Remove-Asset -BatchSize $batchSize -Force
            Should -Invoke Invoke-CompassOneApi -Times $largeAssetSet.Count
        }

        It 'Should handle pipeline input with PassThru' {
            $result = $validAsset | Remove-Asset -Force -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be $validAsset.Id
        }
    }

    Context 'Error Handling' {
        It 'Should handle asset not found errors' {
            { Remove-Asset -Id "invalid-id" -Force } | Should -Throw
        }

        It 'Should handle API errors' {
            { Remove-Asset -Id "error-500" -Force } | Should -Throw
        }

        It 'Should handle validation errors' {
            { Remove-Asset -InputObject $invalidAsset -Force } | Should -Throw
        }

        It 'Should handle batch processing errors' {
            $mixedAssets = @($validAsset, $invalidAsset)
            { $mixedAssets | Remove-Asset -Force } | Should -Throw
        }

        It 'Should handle rate limiting errors' {
            Mock Invoke-CompassOneApi { throw "Rate limit exceeded" }
            { Remove-Asset -Id "test-asset-001" -Force } | Should -Throw
        }
    }

    Context 'Security Validation' {
        It 'Should require confirmation without Force parameter' {
            Mock ShouldProcess { return $false }
            $validAsset | Remove-Asset
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It 'Should bypass confirmation with Force parameter' {
            $validAsset | Remove-Asset -Force
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It 'Should validate WhatIf parameter' {
            $validAsset | Remove-Asset -WhatIf
            Should -Invoke Invoke-CompassOneApi -Times 0
        }

        It 'Should log deletion operations' {
            $validAsset | Remove-Asset -Force
            Should -Invoke Write-CompassOneLog -Times 2 -ParameterFilter {
                $Source -eq 'AssetManagement'
            }
        }

        It 'Should handle security policy violations' {
            Mock Invoke-CompassOneApi { throw "Access denied" }
            { Remove-Asset -Id "test-asset-001" -Force } | Should -Throw
        }
    }

    Context 'Performance and Resource Management' {
        It 'Should handle large batch operations efficiently' {
            $largeAssetSet = 1..20 | ForEach-Object {
                $asset = [Asset]::new("PerfAsset$_", [AssetClass]::Device)
                $asset.Id = "test-asset-$_"
                $asset
            }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $largeAssetSet | Remove-Asset -BatchSize 5 -Force
            $sw.Stop()

            $sw.ElapsedMilliseconds | Should -BeLessThan 5000
        }

        It 'Should cleanup resources after batch processing' {
            $initialMemory = [System.GC]::GetTotalMemory($true)
            $largeAssetSet = 1..50 | ForEach-Object {
                $asset = [Asset]::new("MemAsset$_", [AssetClass]::Device)
                $asset.Id = "test-asset-$_"
                $asset
            }

            $largeAssetSet | Remove-Asset -BatchSize 10 -Force
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryDiff = $finalMemory - $initialMemory
            $memoryDiff | Should -BeLessThan 1MB
        }
    }
}