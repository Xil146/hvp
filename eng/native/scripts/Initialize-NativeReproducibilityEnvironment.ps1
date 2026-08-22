[CmdletBinding()]
param([long]$SourceDateEpoch = 0)

$ErrorActionPreference = 'Stop'
if ($SourceDateEpoch -lt 0) { throw 'SOURCE_DATE_EPOCH must be non-negative.' }
$env:SOURCE_DATE_EPOCH = [string]$SourceDateEpoch
$env:TZ = 'UTC'
$env:LC_ALL = 'C'
$env:LANG = 'C'
$env:PYTHONHASHSEED = '0'
$env:MSYS2_PATH_TYPE = 'strict'
Write-Output ([pscustomobject]@{ SOURCE_DATE_EPOCH = $env:SOURCE_DATE_EPOCH; TZ = $env:TZ; LC_ALL = $env:LC_ALL; PYTHONHASHSEED = $env:PYTHONHASHSEED; MSYS2_PATH_TYPE = $env:MSYS2_PATH_TYPE })
