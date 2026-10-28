$integrationEnabled = $env:PSDV_RUN_INTEGRATION_TESTS -eq '1'

Describe 'Dataverse live optimistic concurrency' -Tag 'Integration' -Skip:(-not $integrationEnabled) {
    BeforeAll {
        foreach ($name in @(
            'PSDV_INTEGRATION_ORG_URL', 'PSDV_INTEGRATION_ACCESS_TOKEN',
            'PSDV_INTEGRATION_ENTITY_SET', 'PSDV_INTEGRATION_TEXT_COLUMN'
        )) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
                throw "Live concurrency tests require $name. Use only a disposable test environment."
            }
        }

        $modulePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Dataverse.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        $orgUrl = $env:PSDV_INTEGRATION_ORG_URL
        $token = ConvertTo-SecureString $env:PSDV_INTEGRATION_ACCESS_TOKEN -AsPlainText -Force
        $entitySet = $env:PSDV_INTEGRATION_ENTITY_SET
        $textColumn = $env:PSDV_INTEGRATION_TEXT_COLUMN
        Connect-PSDVOrg -DataverseOrgURL $orgUrl -AccessToken $token -ErrorAction Stop

        $entitySetLiteral = $entitySet.Replace("'", "''")
        $metadata = Invoke-PSDVWebRequest -WebUri 'EntityDefinitions' `
            -Filter "EntitySetName eq '$entitySetLiteral'" `
            -Select 'PrimaryIdAttribute,IsOptimisticConcurrencyEnabled' -ErrorAction Stop
        if ($metadata.IsOptimisticConcurrencyEnabled -ne $true -or
            [string]::IsNullOrWhiteSpace($metadata.PrimaryIdAttribute)) {
            throw 'The integration entity set must identify one test table with optimistic concurrency enabled.'
        }
        $primaryIdAttribute = $metadata.PrimaryIdAttribute
    }

    AfterAll {
        if (Get-Command Disconnect-PSDVOrg -ErrorAction SilentlyContinue) {
            Disconnect-PSDVOrg
        }
    }

    It 'persists exactly one competing update and enforces wildcard existence semantics' {
        $itemId = [Guid]::NewGuid()
        $missingItemId = [Guid]::NewGuid()
        $ownedIds = [System.Collections.Generic.List[Guid]]::new()
        $workers = [System.Collections.Generic.List[object]]::new()
        $ready = [System.Threading.CountdownEvent]::new(2)
        $start = [System.Threading.ManualResetEventSlim]::new($false)
        $workerScript = {
            param($ModulePath, $OrgUrl, $Token, $EntitySet, $ItemId, $TextColumn, $ETag, $Value, $Ready, $Start)
            $ErrorActionPreference = 'Stop'
            $signaled = $false
            try {
                Import-Module $ModulePath -Force -ErrorAction Stop
                Connect-PSDVOrg -DataverseOrgURL $OrgUrl -AccessToken $Token -ErrorAction Stop
                $null = $Ready.Signal()
                $signaled = $true
                if (-not $Start.Wait([TimeSpan]::FromSeconds(60))) {
                    throw 'Timed out waiting to start the competing update.'
                }
                $updated = Update-PSDVTableItem -EntitySet $EntitySet -ItemID $ItemId `
                    -ItemData @{ $TextColumn = $Value } -IfMatch $ETag -ReturnItem -ErrorAction Stop
                [PSCustomObject]@{ Succeeded = $true; Value = $Value; UpdatedItem = $updated; Error = $null }
            }
            catch {
                if (-not $signaled) {
                    $null = $Ready.Signal()
                }
                [PSCustomObject]@{ Succeeded = $false; Value = $Value; UpdatedItem = $null; Error = $_ }
            }
            finally {
                if (Get-Command Disconnect-PSDVOrg -ErrorAction SilentlyContinue) {
                    Disconnect-PSDVOrg
                }
            }
        }

        try {
            $ownedIds.Add($itemId)
            $createData = @{ $primaryIdAttribute = $itemId; $textColumn = "PSDV concurrency test $itemId" }
            $null = New-PSDVTableItem -EntitySet $entitySet -ItemData $createData -ReturnItem -ErrorAction Stop
            $originalRow = Get-PSDVTableItem -EntitySet $entitySet -ItemID $itemId -ErrorAction Stop
            $etag = $originalRow.'@odata.etag'
            $etag | Should -Not -BeNullOrEmpty

            foreach ($value in @("worker-a-$itemId", "worker-b-$itemId")) {
                $powerShell = [PowerShell]::Create()
                $worker = [PSCustomObject]@{ PowerShell = $powerShell; Handle = $null }
                $workers.Add($worker)
                $null = $powerShell.AddScript($workerScript.ToString()).AddArgument($modulePath).
                    AddArgument($orgUrl).AddArgument($token).AddArgument($entitySet).AddArgument($itemId).
                    AddArgument($textColumn).AddArgument($etag).AddArgument($value).AddArgument($ready).AddArgument($start)
                $worker.Handle = $powerShell.BeginInvoke()
            }
            if (-not $ready.Wait([TimeSpan]::FromSeconds(60))) {
                $workerErrors = @($workers | ForEach-Object { $_.PowerShell.Streams.Error })
                throw "Competing workers did not become ready. Worker errors: $($workerErrors -join '; ')"
            }
            $start.Set()
            $outcomes = @(
                foreach ($worker in $workers) {
                    if (-not $worker.Handle.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(120))) {
                        throw 'Timed out waiting for a competing update response; the write outcome is unknown.'
                    }
                    $worker.PowerShell.EndInvoke($worker.Handle)
                }
            )
            $outcomes.Count | Should -Be 2
            $winner = @($outcomes | Where-Object Succeeded)
            $loser = @($outcomes | Where-Object { -not $_.Succeeded })
            $winner.Count | Should -Be 1
            $loser.Count | Should -Be 1
            $loser[0].Error.FullyQualifiedErrorId | Should -BeLike 'PSDVPreconditionFailed*'
            $loser[0].Error.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be 412
            $winner[0].UpdatedItem.$textColumn | Should -BeExactly $winner[0].Value
            $winner[0].UpdatedItem.'@odata.etag' | Should -Not -BeNullOrEmpty

            $persisted = Get-PSDVTableItem -EntitySet $entitySet -ItemID $itemId -ErrorAction Stop
            $persisted.$textColumn | Should -BeExactly $winner[0].Value
            $persisted.$textColumn | Should -Not -BeExactly $loser[0].Value
            $persisted.'@odata.etag' | Should -BeExactly $winner[0].UpdatedItem.'@odata.etag'
            $originalRow.'@odata.etag' | Should -BeExactly $etag

            $wildcardRow = Update-PSDVTableItem -EntitySet $entitySet -ItemID $itemId `
                -ItemData @{ $textColumn = "wildcard-$itemId" } -IfMatch '*' -ReturnItem -ErrorAction Stop
            $wildcardRow.$textColumn | Should -BeExactly "wildcard-$itemId"

            $ownedIds.Add($missingItemId)
            $missingError = $null
            try {
                Update-PSDVTableItem -EntitySet $entitySet -ItemID $missingItemId `
                    -ItemData @{ $textColumn = "must-not-create-$missingItemId" } -IfMatch '*' -ErrorAction Stop
            }
            catch { $missingError = $_ }
            $missingError.FullyQualifiedErrorId | Should -BeLike 'PSDVHttpError*'
            $missingError.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be 404
            $probe = Invoke-PSDVWebRequest -WebUri "$entitySet($missingItemId)" `
                -SkipHttpErrorCheck -ReturnRawResponse -ErrorAction Stop
            $probe.StatusCode | Should -Be 404
        }
        finally {
            $cleanupErrors = [System.Collections.Generic.List[System.Exception]]::new()
            $start.Set()
            foreach ($worker in $workers) {
                try {
                    if ($null -ne $worker.Handle -and -not $worker.Handle.IsCompleted) {
                        $worker.PowerShell.Stop()
                    }
                }
                catch {
                    $cleanupErrors.Add($_.Exception)
                }
                finally {
                    $worker.PowerShell.Dispose()
                }
            }
            $ready.Dispose()
            $start.Dispose()
            foreach ($ownedId in $ownedIds) {
                try {
                    $null = Remove-PSDVTableItem -EntitySet $entitySet -ItemID $ownedId -Confirm:$false -ErrorAction Stop
                }
                catch {
                    # A failed create or the missing-row test can legitimately leave no owned record.
                    if ($_.Exception.Data['PSDVHttpError'].HttpStatusCode -ne 404) {
                        $cleanupErrors.Add($_.Exception)
                    }
                }
            }
            if ($cleanupErrors.Count -gt 0) {
                throw [System.AggregateException]::new('Live concurrency test cleanup failed.', $cleanupErrors)
            }
        }
    }
}
