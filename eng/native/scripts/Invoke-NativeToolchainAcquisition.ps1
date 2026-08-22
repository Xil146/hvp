[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DownloadDirectory,
    [string]$ManifestPath,
    [scriptblock]$DownloadScript
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/toolchain.lock.json' }
$lockPath = [IO.Path]::GetFullPath($ManifestPath)
if ([IO.Path]::GetFileName($lockPath) -cne 'toolchain.lock.json') { throw 'Toolchain acquisition requires toolchain.lock.json.' }
$manifestRoot = Split-Path -Parent $lockPath
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot $manifestRoot -BuildInputsOnly | Out-Null
$root = [IO.Path]::GetFullPath($DownloadDirectory)
if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root | Out-Null }
$rootItem = Get-Item -LiteralPath $root -Force
if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Toolchain download directory cannot be a reparse point.' }
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$records = @([pscustomobject]@{ id = 'msys2-base'; archive = $lock.baseArchive.archive; signature = $lock.baseArchive.signature }) + @($lock.packages | ForEach-Object { [pscustomobject]@{ id = $_.id; archive = $_.archive; signature = $_.signature } })
foreach ($record in $records) {
    foreach ($artifact in @($record.archive, $record.signature)) {
        $destination = Join-Path $root ([string]$artifact.name)
        if (Test-Path -LiteralPath $destination) { continue }
        $uri = [Uri][string]$artifact.url
        if ($uri.Scheme -cne 'https' -or $uri.Query.Length -ne 0 -or @($artifact.allowedRedirectHosts) -cnotcontains $uri.Host) { throw "Toolchain URI is not approved: $($artifact.url)" }
        $temporary = Join-Path $root ('.incomplete-' + [guid]::NewGuid().ToString('N'))
        try {
            if ($null -ne $DownloadScript) { $finalText = & $DownloadScript $uri.AbsoluteUri $temporary; $final = [Uri][string]$finalText }
            else { $response = Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $temporary -PassThru -UseBasicParsing; $final = $response.BaseResponse.ResponseUri }
            if ($final.Scheme -cne 'https' -or @($artifact.allowedRedirectHosts) -cnotcontains $final.Host) { throw "Toolchain download redirected to an unapproved host: $final" }
            if (-not (Test-Path -LiteralPath $temporary -PathType Leaf)) { throw 'Toolchain download did not produce a file.' }
            $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -cne [string]$artifact.sha256) { throw "Toolchain download checksum mismatch: $($artifact.name)" }
            Move-Item -LiteralPath $temporary -Destination $destination
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    }
}
& (Join-Path $PSScriptRoot 'Test-NativeToolchainArchiveSet.ps1') -ArchiveDirectory $root -ManifestPath $lockPath
