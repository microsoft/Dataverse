. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'New-PSDVBatchRequest' {
    It 'builds POST operations for create batches' {
        InModuleScope Dataverse {
            $items = @(
                [pscustomobject]@{ ItemData = @{ name = 'First' } },
                [pscustomobject]@{ ItemData = @{ name = 'Second' } }
            )

            $request = New-PSDVBatchRequest -EntitySet 'accounts' -Operation Create -Items $items

            $request.RequestedCount | Should -Be 2
            $request.BatchBoundary | Should -Match '^batch_'
            $request.BatchBody | Should -Match 'POST accounts HTTP/1.1'
            $request.BatchBody | Should -Match 'Content-ID: 1'
            $request.BatchBody | Should -Match 'Content-ID: 2'
            $request.BatchBody | Should -Match '"name":"First"'
            $request.BatchBody | Should -Match '"name":"Second"'
        }
    }

    It 'builds PATCH operations for update batches' {
        InModuleScope Dataverse {
            $itemId = [Guid]::NewGuid()
            $items = @([pscustomobject]@{ ItemID = $itemId; ItemData = @{ name = 'Updated' } })

            $request = New-PSDVBatchRequest -EntitySet 'accounts' -Operation Update -Items $items

            $request.BatchBody | Should -Match "PATCH accounts\($itemId\) HTTP/1.1"
            $request.BatchBody | Should -Not -Match 'If-None-Match'
        }
    }

    It 'builds PATCH operations for alternate-key upsert batches' {
        InModuleScope Dataverse {
            $items = @([pscustomobject]@{ AlternateKeyValue = "O'Hare"; ItemData = @{ name = 'Upserted' } })

            $request = New-PSDVBatchRequest -EntitySet 'accounts' -Operation Upsert -AlternateKeyColumnName 'accountnumber' -Items $items

            $request.BatchBody | Should -Match "PATCH accounts\(accountnumber='O''Hare'\) HTTP/1.1"
            $request.BatchBody | Should -Not -Match 'If-None-Match'
        }
    }

    It 'builds POST operations with alternate key values for create-only upsert batches' {
        InModuleScope Dataverse {
            $items = @([pscustomobject]@{ AlternateKeyValue = 'ACC001'; ItemData = @{ name = 'Create only' } })

            $request = New-PSDVBatchRequest -EntitySet 'accounts' -Operation Upsert -AlternateKeyColumnName 'accountnumber' -Items $items -CreateOnly

            $request.BatchBody | Should -Match 'POST accounts HTTP/1.1'
            $request.BatchBody | Should -Match '"accountnumber":"ACC001"'
            $request.BatchBody | Should -Not -Match 'If-None-Match'
        }
    }
}