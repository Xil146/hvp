[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$releaseDirectory = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hvp-payload-manifest-test-" + [guid]::NewGuid())
$payloadRoot = Join-Path $testRoot 'payload'
$manifestPath = Join-Path $testRoot 'manifest.json'
$checksumsPath = Join-Path $testRoot 'SHA256SUMS.txt'
$contractPath = Join-Path $testRoot 'managed-contract.json'

function Assert-Rejected {
    param([Parameter(Mandatory)][scriptblock]$Action)

    $rejected = $false
    try {
        & $Action
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw 'Validator accepted an invalid payload manifest.'
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'runtime') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $payloadRoot 'HVP-win-x64.exe') -Value 'application' -NoNewline
    Set-Content -LiteralPath (Join-Path $payloadRoot 'Hvp.Core.dll') -Value 'core' -NoNewline
    Set-Content -LiteralPath (Join-Path $payloadRoot 'runtime/runtime.dll') -Value 'runtime' -NoNewline

    $contract = [ordered]@{
        schemaVersion = 1
        payloadKind = 'managed-scaffold'
        firstPartyManagedFiles = @('HVP-win-x64.exe', 'Hvp.Core.dll')
        allowedFiles = @('HVP-win-x64.exe', 'Hvp.Core.dll', 'runtime/runtime.dll')
    }
    $contract | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $contractPath -Encoding utf8
    & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $payloadRoot -ContractPath $contractPath

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath

    Assert-Rejected {
        & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot ($payloadRoot + [System.IO.Path]::DirectorySeparatorChar) -ManifestPath (Join-Path $payloadRoot 'payload-manifest.json') -ContractPath $contractPath
    }

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadChecksums.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ChecksumsPath $checksumsPath
    Assert-Rejected {
        & (Join-Path $releaseDirectory 'New-ApplicationPayloadChecksums.ps1') -PayloadRoot ($payloadRoot + [System.IO.Path]::DirectorySeparatorChar) -ManifestPath $manifestPath -ChecksumsPath (Join-Path $payloadRoot 'SHA256SUMS.txt')
    }

    $firstManifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $firstChecksumBytes = [System.IO.File]::ReadAllBytes($checksumsPath)
    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    & (Join-Path $releaseDirectory 'New-ApplicationPayloadChecksums.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ChecksumsPath $checksumsPath
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$firstManifestBytes, [byte[]][System.IO.File]::ReadAllBytes($manifestPath))) {
        throw 'Payload manifest output is not byte-deterministic.'
    }
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$firstChecksumBytes, [byte[]][System.IO.File]::ReadAllBytes($checksumsPath))) {
        throw 'Payload checksum output is not byte-deterministic.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestPaths = @($manifest.files | ForEach-Object { [string]$_.path })
    $ordinalPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $manifestPaths) {
        if ([System.IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or $path.Contains('..')) {
            throw "Manifest emitted a non-normalized path: $path"
        }
        $ordinalPaths.Add($path)
    }
    $ordinalPaths.Sort([System.StringComparer]::Ordinal)
    if (-not [System.Linq.Enumerable]::SequenceEqual([string[]]$manifestPaths, [string[]]$ordinalPaths.ToArray())) {
        throw 'Payload manifest paths are not in explicit ordinal order.'
    }
    $checksumLines = @(Get-Content -LiteralPath $checksumsPath)
    if ($checksumLines.Count -ne $manifest.files.Count) {
        throw 'Payload checksum line count does not match the manifest file count.'
    }
    for ($index = 0; $index -lt $checksumLines.Count; $index++) {
        if ($checksumLines[$index] -notmatch '^(?<sha256>[0-9a-f]{64}) \*(?<path>.+)$') {
            throw "Payload checksum line is malformed: $($checksumLines[$index])"
        }
        $path = $Matches.path
        if ($path -cne $manifestPaths[$index]) {
            throw "Payload checksum path is not in ordinal manifest order: $path"
        }
        $entry = $manifest.files[$index]
        if ($Matches.sha256 -cne $entry.sha256 -or $Matches.sha256 -cne (Get-FileHash -LiteralPath (Join-Path $payloadRoot $path) -Algorithm SHA256).Hash.ToLowerInvariant()) {
            throw "Payload checksum hash does not match file content: $path"
        }
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.files += [pscustomobject]@{ path = '../escape.dll'; sha256 = ('0' * 64) }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    Set-Content -LiteralPath (Join-Path $payloadRoot 'unexpected.dll') -Value 'unexpected' -NoNewline
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $payloadRoot -ContractPath $contractPath }
    Remove-Item -LiteralPath (Join-Path $payloadRoot 'unexpected.dll') -Force

    New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'native') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $payloadRoot 'native/native-candidate.json') -Value '{}' -NoNewline
    & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ExcludedTopLevelDirectory 'native'
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }
    Remove-Item -LiteralPath (Join-Path $payloadRoot 'native') -Recurse -Force

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.files += [pscustomobject]@{ path = 'hvp-WIN-x64.exe'; sha256 = $manifest.files[0].sha256 }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.files[0].sha256 = 'not-a-sha256'
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    Set-Content -LiteralPath (Join-Path $payloadRoot 'Hvp.Core.dll') -Value 'tampered' -NoNewline
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }
    Set-Content -LiteralPath (Join-Path $payloadRoot 'Hvp.Core.dll') -Value 'core' -NoNewline

    & (Join-Path $releaseDirectory 'New-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath -ContractPath $contractPath
    Remove-Item -LiteralPath (Join-Path $payloadRoot 'runtime/runtime.dll') -Force
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }
    Set-Content -LiteralPath (Join-Path $payloadRoot 'runtime/runtime.dll') -Value 'runtime' -NoNewline

    Remove-Item -LiteralPath (Join-Path $payloadRoot 'HVP-win-x64.exe') -Force
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $payloadRoot -ContractPath $contractPath }
    Set-Content -LiteralPath (Join-Path $payloadRoot 'HVP-win-x64.exe') -Value 'application' -NoNewline

    Remove-Item -LiteralPath (Join-Path $payloadRoot 'Hvp.Core.dll') -Force
    Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $payloadRoot -ContractPath $contractPath }
    Set-Content -LiteralPath (Join-Path $payloadRoot 'Hvp.Core.dll') -Value 'core' -NoNewline

    $reparseTarget = Join-Path $testRoot 'reparse-target'
    New-Item -ItemType Directory -Path $reparseTarget -Force | Out-Null
    $reparsePath = Join-Path $payloadRoot 'linked-runtime'
    try {
        New-Item -ItemType Junction -Path $reparsePath -Target $reparseTarget | Out-Null
        Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $payloadRoot -ManifestPath $manifestPath }
        Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $payloadRoot -ContractPath $contractPath }
        Remove-Item -LiteralPath $reparsePath -Force

        $reparseRoot = Join-Path $testRoot 'payload-link'
        New-Item -ItemType Junction -Path $reparseRoot -Target $payloadRoot | Out-Null
        Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $reparseRoot -ManifestPath $manifestPath }
        Assert-Rejected { & (Join-Path $releaseDirectory 'Test-ManagedPayloadContract.ps1') -PayloadRoot $reparseRoot -ContractPath $contractPath }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Host 'Skipping reparse-point tests because the platform did not permit junction creation.'
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
