#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules
    Import-Module -Name PSCompassOne -Force
    
    # Initialize test environment
    $script:testAssets = @()
    $script:correlationId = [guid]::NewGuid().ToString()
    
    # Test data fixtures
    $script:testData = @{
        ValidAsset = @{
            Name = "IntegrationTest-Asset-$([guid]::NewGuid().ToString().Substring(0,8))"
            Class = 'Device'
            Tags = @('Integration', 'Test')
            Description = 'Integration test asset'
        }
        UpdateAsset = @{
            Name = "IntegrationTest-UpdatedAsset-$([guid]::NewGuid().ToString().Substring(0,8))"
            Class = 'Container'
            Tags = @('Integration', 'Updated')
            Description = 'Updated integration test asset'
        }
        BatchSize = 10
        PerformanceThreshold = 2000 # 2 seconds in milliseconds
    }

    # Configure test isolation
    $script:testPrefix = "IntegrationTest-$([guid]::NewGuid().ToString().Substring(0,8))"
}

AfterAll {
    # Cleanup test assets
    $script:testAssets | ForEach-Object {
        try {
            Remove-Asset -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to cleanup test asset $($_.Id): $_"
        }
    }

    # Reset test environment
    $script:testAssets = $null
    [System.GC]::Collect()
}

Describe 'Asset Creation Tests' {
    Context 'Basic Asset Creation' {
        It 'Should create asset with valid required fields' {
            $asset = New-Asset @script:testData.ValidAsset -PassThru
            $asset | Should -Not -BeNullOrEmpty
            $asset.Name | Should -BeLike "*$script:testPrefix*"
            $asset.Class | Should -Be $script:testData.ValidAsset.Class
            $script:testAssets += $asset
        }

        It 'Should enforce validation rules' {
            { New-Asset -Name '' -Class 'Invalid' } | Should -Throw
            { New-Asset -Name $null -Class 'Device' } | Should -Throw
            { New-Asset -Name 'Test' -Class $null } | Should -Throw
        }

        It 'Should generate audit logs' {
            $asset = New-Asset @script:testData.ValidAsset -PassThru
            $script:testAssets += $asset
            
            $logs = Get-CompassOneLog -Source 'AssetManagement' -Operation 'Create' -AssetId $asset.Id
            $logs | Should -Not -BeNullOrEmpty
            $logs.Level | Should -Contain 'Information'
        }
    }

    Context 'Performance Requirements' {
        It 'Should complete creation within performance threshold' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $asset = New-Asset @script:testData.ValidAsset -PassThru
            $sw.Stop()
            
            $sw.ElapsedMilliseconds | Should -BeLessThan $script:testData.PerformanceThreshold
            $script:testAssets += $asset
        }

        It 'Should handle concurrent creation operations' {
            $jobs = 1..$script:testData.BatchSize | ForEach-Object {
                $assetData = $script:testData.ValidAsset.Clone()
                $assetData.Name += "-Concurrent-$_"
                
                Start-Job -ScriptBlock {
                    param($Data)
                    Import-Module PSCompassOne
                    New-Asset @Data -PassThru
                } -ArgumentList $assetData
            }

            $results = $jobs | Wait-Job | Receive-Job
            $results.Count | Should -Be $script:testData.BatchSize
            $script:testAssets += $results
        }
    }
}

Describe 'Asset Retrieval Tests' {
    BeforeAll {
        # Create test asset for retrieval tests
        $script:retrievalAsset = New-Asset @script:testData.ValidAsset -PassThru
        $script:testAssets += $script:retrievalAsset
    }

    Context 'Single Asset Retrieval' {
        It 'Should get asset by ID' {
            $asset = Get-Asset -Id $script:retrievalAsset.Id
            $asset | Should -Not -BeNullOrEmpty
            $asset.Id | Should -Be $script:retrievalAsset.Id
        }

        It 'Should handle non-existent assets' {
            { Get-Asset -Id ([guid]::NewGuid().ToString()) } | Should -Throw
        }
    }

    Context 'Asset Query and Filtering' {
        It 'Should filter assets by class' {
            $assets = Get-Asset -Class $script:testData.ValidAsset.Class
            $assets | Should -Not -BeNullOrEmpty
            $assets | ForEach-Object { $_.Class | Should -Be $script:testData.ValidAsset.Class }
        }

        It 'Should filter assets by tags' {
            $assets = Get-Asset -Tags 'Integration'
            $assets | Should -Not -BeNullOrEmpty
            $assets | ForEach-Object { $_.Tags | Should -Contain 'Integration' }
        }
    }

    Context 'Performance and Caching' {
        It 'Should utilize caching effectively' {
            $sw1 = [System.Diagnostics.Stopwatch]::StartNew()
            $result1 = Get-Asset -Id $script:retrievalAsset.Id
            $sw1.Stop()

            $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
            $result2 = Get-Asset -Id $script:retrievalAsset.Id -UseCache
            $sw2.Stop()

            $sw2.ElapsedMilliseconds | Should -BeLessThan $sw1.ElapsedMilliseconds
        }
    }
}

Describe 'Asset Update Tests' {
    BeforeAll {
        # Create test asset for update tests
        $script:updateAsset = New-Asset @script:testData.ValidAsset -PassThru
        $script:testAssets += $script:updateAsset
    }

    Context 'Basic Updates' {
        It 'Should update single property' {
            $newName = "Updated-$($script:updateAsset.Name)"
            $result = Set-Asset -Id $script:updateAsset.Id -Name $newName -PassThru
            $result.Name | Should -Be $newName
        }

        It 'Should update multiple properties atomically' {
            $result = Set-Asset -Id $script:updateAsset.Id @script:testData.UpdateAsset -PassThru
            $result.Name | Should -Be $script:testData.UpdateAsset.Name
            $result.Class | Should -Be $script:testData.UpdateAsset.Class
            $result.Tags | Should -Contain 'Updated'
        }
    }

    Context 'Validation and Security' {
        It 'Should enforce update permissions' {
            Mock -CommandName Test-CompassOnePermission -MockWith { return $false }
            { Set-Asset -Id $script:updateAsset.Id -Name 'Unauthorized' } | Should -Throw
        }

        It 'Should validate input parameters' {
            { Set-Asset -Id $script:updateAsset.Id -Class 'Invalid' } | Should -Throw
            { Set-Asset -Id 'invalid-guid' -Name 'Test' } | Should -Throw
        }
    }

    Context 'Performance Under Load' {
        It 'Should maintain performance during concurrent updates' {
            $jobs = 1..$script:testData.BatchSize | ForEach-Object {
                $updateData = @{
                    Id = $script:updateAsset.Id
                    Description = "Concurrent update $_"
                }
                
                Start-Job -ScriptBlock {
                    param($Data)
                    Import-Module PSCompassOne
                    Set-Asset @Data
                } -ArgumentList $updateData
            }

            { $jobs | Wait-Job -Timeout 30 | Receive-Job } | Should -Not -Throw
        }
    }
}

Describe 'Asset Deletion Tests' {
    Context 'Single Asset Deletion' {
        It 'Should delete asset with confirmation' {
            $asset = New-Asset @script:testData.ValidAsset -PassThru
            { Remove-Asset -Id $asset.Id -Confirm:$false } | Should -Not -Throw
            { Get-Asset -Id $asset.Id } | Should -Throw
        }

        It 'Should require confirmation by default' {
            $asset = New-Asset @script:testData.ValidAsset -PassThru
            $script:testAssets += $asset
            
            Mock -CommandName ShouldProcess -MockWith { return $false }
            Remove-Asset -Id $asset.Id
            Get-Asset -Id $asset.Id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Bulk Deletion' {
        It 'Should support pipeline input' {
            $assets = 1..3 | ForEach-Object {
                New-Asset @script:testData.ValidAsset -PassThru
            }
            
            $assets | Remove-Asset -Force
            $assets | ForEach-Object {
                { Get-Asset -Id $_.Id } | Should -Throw
            }
        }

        It 'Should handle batch operations efficiently' {
            $assets = 1..$script:testData.BatchSize | ForEach-Object {
                New-Asset @script:testData.ValidAsset -PassThru
            }
            
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $assets | Remove-Asset -Force -BatchSize $script:testData.BatchSize
            $sw.Stop()
            
            $sw.ElapsedMilliseconds | Should -BeLessThan ($script:testData.PerformanceThreshold * 2)
        }
    }
}