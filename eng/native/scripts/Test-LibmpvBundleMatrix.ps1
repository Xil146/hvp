[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,
    [Parameter(Mandatory)][string]$FixturePath,
    [Parameter(Mandatory)][string]$ValidReplacementLibmpvPath,
    [Parameter(Mandatory)][string]$WrongArchitectureLibmpvPath,
    [Parameter(Mandatory)][string]$MissingExportLibmpvPath,
    [Parameter(Mandatory)][string]$IncompatibleApiLibmpvPath,
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$OutputContractPath
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($OutputContractPath)){$OutputContractPath=Join-Path(Split-Path -Parent $PSScriptRoot)'manifests/output-contract.json'}
$root=[IO.Path]::GetFullPath($BundleRoot);$contract=Get-Content -LiteralPath $OutputContractPath -Raw|ConvertFrom-Json;$libmpv=@($contract.outputs|Where-Object role -eq 'libmpv')[0];$private=Join-Path $root $libmpv.path
function Expect-Failure([scriptblock]$Action,[string]$Name){try{&$Action|Out-Null}catch{return[ordered]@{passed=$true;failure=$_.Exception.Message}};throw "Negative native matrix scenario unexpectedly succeeded: $Name"}
$scenarios=[ordered]@{}
&(Join-Path $PSScriptRoot 'Test-NativeOutputBundle.ps1')-BundleRoot $root -OutputContractPath $OutputContractPath|Out-Null
$bundled=&(Join-Path $PSScriptRoot 'Invoke-LibmpvSmokeTest.ps1')-LibmpvPath $private -FixturePath $FixturePath
$scenarios.bundled=[ordered]@{passed=($bundled.fixtureLoaded-and$bundled.fixtureUnlocked);apiVersion=$bundled.apiVersion}
$directCompanion=@($libmpv.imports|Where-Object{[IO.Path]::GetExtension($_)-ieq'.dll'-and@( $contract.outputs.path)-icontains$_}|Select-Object -First 1)
if($directCompanion.Count-ne 1){throw 'Output contract does not identify one direct libmpv companion for negative smoke testing.'}
$matrixRoot=Join-Path([IO.Path]::GetTempPath())('hvp-libmpv-matrix-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $matrixRoot|Out-Null
try{
    $missing=Join-Path $matrixRoot 'missing';Copy-Item -LiteralPath $root -Destination $missing -Recurse;Remove-Item -LiteralPath(Join-Path $missing $directCompanion[0])-Force
    $scenarios.missingCompanion=Expect-Failure {&(Join-Path $PSScriptRoot 'Invoke-LibmpvSmokeTest.ps1')-LibmpvPath(Join-Path $missing $libmpv.path)-FixturePath $FixturePath} 'missing companion'
    $tampered=Join-Path $matrixRoot 'tampered';Copy-Item -LiteralPath $root -Destination $tampered -Recurse;[IO.File]::AppendAllText((Join-Path $tampered $directCompanion[0]),'tamper')
    $scenarios.tamperedCompanion=Expect-Failure {&(Join-Path $PSScriptRoot 'Test-NativeOutputBundle.ps1')-BundleRoot $tampered -OutputContractPath $OutputContractPath} 'tampered companion'
    $previous=[Environment]::GetEnvironmentVariable('HVP_LIBMPV_PATH','Process')
    try{
        $env:HVP_LIBMPV_PATH=[IO.Path]::GetFullPath($ValidReplacementLibmpvPath);$replacement=&(Join-Path $PSScriptRoot 'Invoke-LibmpvSmokeTest.ps1')-LibmpvPath $private -FixturePath $FixturePath;$scenarios.validOverride=[ordered]@{passed=($replacement.librarySource-ceq'override'-and$replacement.fixtureLoaded-and$replacement.fixtureUnlocked);apiVersion=$replacement.apiVersion}
        $env:HVP_LIBMPV_PATH=Join-Path $matrixRoot 'missing-libmpv-2.dll';$scenarios.missingOverride=Expect-Failure {&(Join-Path $PSScriptRoot 'Invoke-LibmpvSmokeTest.ps1')-LibmpvPath $private -FixturePath $FixturePath} 'missing override'
        foreach($case in @(@{name='wrongArchitecture';path=$WrongArchitectureLibmpvPath},@{name='missingExport';path=$MissingExportLibmpvPath},@{name='incompatibleApi';path=$IncompatibleApiLibmpvPath})){$env:HVP_LIBMPV_PATH=[IO.Path]::GetFullPath($case.path);$scenarios[$case.name]=Expect-Failure {&(Join-Path $PSScriptRoot 'Invoke-LibmpvSmokeTest.ps1')-LibmpvPath $private -FixturePath $FixturePath} $case.name}
    }finally{[Environment]::SetEnvironmentVariable('HVP_LIBMPV_PATH',$previous,'Process')}
}finally{if(Test-Path -LiteralPath $matrixRoot){Remove-Item -LiteralPath $matrixRoot -Recurse -Force}}
foreach($entry in $scenarios.GetEnumerator()){if($entry.Value.passed-ne$true){throw "Native matrix scenario did not pass: $($entry.Key)"}}
$record=[ordered]@{schemaVersion=1;kind='hvp-libmpv-bundle-matrix';generatedUtc=[DateTime]::UtcNow.ToString('o');searchPolicy='LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32';fixtureLoaded=$true;fixtureUnlocked=$true;scenarios=$scenarios}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath),(($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));[pscustomobject]$record
