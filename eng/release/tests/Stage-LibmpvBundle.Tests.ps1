[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$releaseDirectory = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $releaseDirectory)
$stageScript = Join-Path $releaseDirectory 'Stage-LibmpvBundle.ps1'
$bundleManifestPath = Join-Path $repositoryRoot 'eng/native/libmpv-bundle.json'
$payloadDirectory = Join-Path $repositoryRoot 'artifacts/libmpv/payload'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hvp-stage-libmpv-test-" + [guid]::NewGuid())

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
        throw 'Staging accepted an invalid native payload.'
    }
}

try {
    $publishDirectory = Join-Path $testRoot 'publish'
    New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null

    & $stageScript -PublishDirectory $publishDirectory -ManifestPath $bundleManifestPath -PayloadDirectory $payloadDirectory

    $manifest = Get-Content -LiteralPath $bundleManifestPath -Raw | ConvertFrom-Json
    $pinnedFile = @($manifest.files)[0]
    $stagedPath = Join-Path $publishDirectory $pinnedFile.destinationPath
    if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) {
        throw 'Publish payload did not contain the pinned libmpv DLL.'
    }

    $stagedHash = (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stagedHash -cne $pinnedFile.sha256.ToLowerInvariant()) {
        throw 'Published libmpv DLL did not match the pinned SHA-256.'
    }

    Assert-Rejected {
        & $stageScript -PublishDirectory $publishDirectory -ManifestPath $bundleManifestPath -PayloadDirectory (Join-Path $testRoot 'missing-payload')
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
