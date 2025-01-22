BeforeAll {
    # Import required modules and functions
    . "$PSScriptRoot/../../../Public/Asset/Set-Asset.ps1"
    . "$PSScriptRoot/../../../Private/Types/Asset.Types.ps1"
    . "$PSScriptRoot/../../../Private/Api/Invoke-CompassOneApi.ps1"

    # Mock API calls
    Mock Invoke-CompassOneApi {
        param($EndpointPath, $Method, $Body)
        
        # Return mock response based on input
        $response = [PSCustomObject]@{
            Id = $Body.Id ?? "test-asset-001"
            Name = $Body.Name ?? "Test Asset"
            Class = $Body.Class ?? [AssetClass]::Device
            Status = $Body.Status ?? [AssetStatus]::Active
            Tags = $Body.Tags ?? @("Test")
            Description = $Body.Description ?? "Test Description"
            UpdatedOn = [DateTime]::UtcNow
            UpdatedBy = $env:USERNAME
        }

        return $response
    }

    # Mock error handling
    Mock Write-CompassOneError {
        param($ErrorCategory, $ErrorCode, $ErrorDetails)
        throw $ErrorDetails.Message
    }

    # Create test data
    $validAsset = @{
        Id = "test-asset-001"
        Name = "Updated Test Asset"
        Class = [AssetClass]::Device
        Status = [AssetStatus]::Active
        Tags = @("Test", "Updated")
        Description = "Updated test description"
    }

    $invalidAsset = @{
        Id = ""
        Name = "<script>alert(1)</script>"
        Class = "InvalidClass"
        Status = "InvalidStatus"
        Tags = @("<script>", "invalid")
    }
}

Describe "Set-Asset" {
    Context "Parameter Validation" {
        It "Should require Id parameter" {
            { Set-Asset } | Should -Throw "*Parameter set cannot be resolved*"
        }

        It "Should validate Id format" {
            { Set-Asset -Id "invalid-id" } | Should -Throw "*Invalid asset ID format*"
        }

        It "Should validate asset class" {
            { Set-Asset -Id $validAsset.Id -Class "InvalidClass" } | 
                Should -Throw "*Invalid asset class*"
        }

        It "Should validate asset status" {
            { Set-Asset -Id $validAsset.Id -Status "InvalidStatus" } | 
                Should -Throw "*Invalid asset status*"
        }

        It "Should validate tag format" {
            { Set-Asset -Id $validAsset.Id -Tags @("<script>") } | 
                Should -Throw "*Invalid tag value*"
        }

        It "Should accept pipeline input by property name" {
            $asset = [PSCustomObject]$validAsset
            $asset | Set-Asset -PassThru | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-CompassOneApi -Times 1
        }

        It "Should support WhatIf parameter" {
            Set-Asset -Id $validAsset.Id -Name "Test" -WhatIf
            Should -Invoke Invoke-CompassOneApi -Times 0
        }
    }

    Context "API Interaction" {
        It "Should call API with correct parameters" {
            Set-Asset @validAsset
            Should -Invoke Invoke-CompassOneApi -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and 
                $EndpointPath -eq "/assets/$($validAsset.Id)"
            }
        }

        It "Should handle API errors appropriately" {
            Mock Invoke-CompassOneApi { throw "API Error" }
            { Set-Asset @validAsset } | Should -Throw "*API Error*"
        }

        It "Should return asset object when PassThru specified" {
            $result = Set-Asset @validAsset -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be $validAsset.Id
            $result.Name | Should -Be $validAsset.Name
        }

        It "Should track correlation IDs" {
            Set-Asset @validAsset
            Should -Invoke Invoke-CompassOneApi -Times 1 -ParameterFilter {
                $null -ne $CorrelationId -and $CorrelationId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            }
        }

        It "Should validate API responses" {
            Mock Invoke-CompassOneApi { return $null }
            { Set-Asset @validAsset -PassThru } | Should -Throw "*Updated asset validation failed*"
        }
    }

    Context "Error Handling" {
        It "Should write detailed error for invalid parameters" {
            { Set-Asset @invalidAsset } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1 -ParameterFilter {
                $ErrorCategory -eq 'InvalidOperation' -and
                $ErrorCode -eq 3001
            }
        }

        It "Should handle concurrent update conflicts" {
            Mock Invoke-CompassOneApi { throw "Conflict" }
            { Set-Asset @validAsset } | Should -Throw "*Conflict*"
        }

        It "Should maintain audit trail for failures" {
            { Set-Asset @invalidAsset } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1 -ParameterFilter {
                $ErrorDetails.ContainsKey('CorrelationId')
            }
        }

        It "Should prevent information disclosure in errors" {
            { Set-Asset @invalidAsset } | Should -Throw
            Should -Invoke Write-CompassOneError -Times 1 -ParameterFilter {
                -not $ErrorDetails.ToString().Contains("script")
            }
        }
    }

    Context "Security Controls" {
        It "Should sanitize input parameters" {
            { Set-Asset -Id $validAsset.Id -Name "<script>alert(1)</script>" } |
                Should -Throw "*Invalid Name parameter*"
        }

        It "Should validate status transitions" {
            { Set-Asset -Id $validAsset.Id -Status "Deleted" } |
                Should -Throw "*DeletedOn*"
        }

        It "Should enforce proper audit trail" {
            $result = Set-Asset @validAsset -PassThru
            $result.UpdatedBy | Should -Not -BeNullOrEmpty
            $result.UpdatedOn | Should -BeOfType [DateTime]
        }

        It "Should clean up sensitive data" {
            Set-Asset @validAsset
            [System.GC]::Collect()
            $Error | Should -Not -Contain "*password*"
            $Error | Should -Not -Contain "*secret*"
            $Error | Should -Not -Contain "*key*"
        }
    }

    Context "Performance" {
        It "Should handle large tag collections" {
            $largeTags = 1..100 | ForEach-Object { "Tag$_" }
            $result = Set-Asset -Id $validAsset.Id -Tags $largeTags -PassThru
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should process pipeline input efficiently" {
            $assets = 1..10 | ForEach-Object {
                [PSCustomObject]@{
                    Id = "test-asset-$_"
                    Name = "Test Asset $_"
                }
            }
            $assets | Set-Asset
            Should -Invoke Invoke-CompassOneApi -Times 10
        }

        It "Should handle concurrent requests" {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    Set-Asset -Id "test-asset-$_" -Name "Concurrent Test $_"
                }
            }
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            $results | Should -Not -BeNullOrEmpty
        }
    }
}