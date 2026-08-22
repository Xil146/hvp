[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceId,
    [Parameter(Mandatory)][string]$DownloadDirectory,
    [string]$ManifestPath,
    [Parameter(Mandatory)][switch]$AllowQuarantineForHashDiscovery,
    [scriptblock]$DownloadScript
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-inputs.json'
}
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
if ([IO.Path]::GetFileName($manifestFullPath) -cne 'native-inputs.json') {
    throw 'Source download requires a complete reviewed manifest root containing native-inputs.json.'
}
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot (Split-Path -Parent $manifestFullPath) -AllowIncomplete | Out-Null

function Assert-NotReparsePoint([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in native acquisition paths: $Path"
        }
    }
}
function Assert-NoReparseAncestor([string]$Path) {
    $current = Get-Item -LiteralPath $Path -Force
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in native acquisition ancestors: $($current.FullName)"
        }
        $current = $current.Parent
    }
}

$inputs = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($inputs.schemaVersion -ne 2 -or $inputs.kind -ne 'hvp-native-source-lock') {
    throw 'Unsupported source lock schema.'
}
$matches = @($inputs.sources | Where-Object { $_.id -ceq $SourceId })
if ($matches.Count -ne 1) { throw "Source id is undeclared or duplicated: $SourceId" }
$source = $matches[0]
$uri = $null
if ($source.commit -notmatch '^[0-9a-f]{40}$' -or
    -not [Uri]::TryCreate([string]$source.archive.url, [UriKind]::Absolute, [ref]$uri) -or
    $uri.Scheme -ne 'https' -or $uri.Query.Length -ne 0 -or
    @($source.archive.allowedRedirectHosts) -notcontains $uri.Host -or
    $source.archive.url -match '(^|/)(main|master|latest)(/|\.|$)') {
    throw "Source URL/ref is not locked: $SourceId"
}
if ($SourceId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
    [IO.Path]::GetFileName([string]$source.archive.name) -cne [string]$source.archive.name -or
    [string]$source.archive.name -match '[:\\/]' -or
    [string]::IsNullOrWhiteSpace($source.archive.name) -or
    [string]$source.archive.name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$' -or
    [string]$source.archive.name -match '[\. ]$') {
    throw "Source id or archive name is unsafe: $SourceId"
}

if (-not $AllowQuarantineForHashDiscovery) {
    throw 'Locked source publication is not enabled until signature and pin verification tooling is locked.'
}

$downloadRoot = [IO.Path]::GetFullPath($DownloadDirectory)
if (-not (Test-Path -LiteralPath $downloadRoot)) {
    New-Item -ItemType Directory -Path $downloadRoot | Out-Null
}
Assert-NotReparsePoint $downloadRoot
Assert-NoReparseAncestor $downloadRoot

$workRoot = Join-Path $downloadRoot ('.incomplete-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot | Out-Null
$tempPath = Join-Path $workRoot ([string]$source.archive.name)
try {
    if ($null -ne $DownloadScript) {
        $finalUriText = & $DownloadScript $source.archive.url $tempPath
        $finalUri = [Uri][string]$finalUriText
    }
    else {
        $response = Invoke-WebRequest -Uri $source.archive.url -OutFile $tempPath -PassThru -UseBasicParsing
        $finalUri = $response.BaseResponse.ResponseUri
    }

    if ($null -eq $finalUri -or $finalUri.Scheme -ne 'https' -or
        @($source.archive.allowedRedirectHosts) -notcontains $finalUri.Host) {
        throw "Source download redirected to an unapproved host: $finalUri"
    }
    if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) { throw 'Source download did not produce a regular file.' }
    Assert-NotReparsePoint $tempPath

    $actual = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $quarantineRoot = Join-Path $downloadRoot 'quarantine'
    if (-not (Test-Path -LiteralPath $quarantineRoot)) {
        New-Item -ItemType Directory -Path $quarantineRoot | Out-Null
    }
    Assert-NotReparsePoint $quarantineRoot
    $targetName = '{0}-{1}-{2}' -f $SourceId, $actual, $source.archive.name
    $target = Join-Path $quarantineRoot $targetName
    if (Test-Path -LiteralPath $target) { throw "Quarantine target already exists: $target" }
    Move-Item -LiteralPath $tempPath -Destination $target
    Write-Output ([pscustomobject]@{
        status = 'quarantined'
        source = $SourceId
        sha256 = $actual
        finalUri = $finalUri.AbsoluteUri
        path = $target
        buildReady = $false
    })
}
finally {
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
}
