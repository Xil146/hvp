[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,
    [Parameter(Mandatory)][string]$RoleMapPath,
    [Parameter(Mandatory)][string]$LicenseConclusionsPath,
    [Parameter(Mandatory)][string]$SmokeEvidencePath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$TemplatePath,
    [string]$SystemDllAllowlistVersion='windows-11-x64-v1'
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($TemplatePath)){$TemplatePath=Join-Path(Split-Path -Parent $PSScriptRoot)'manifests/output-contract.json'}
$template=Get-Content -LiteralPath $TemplatePath -Raw|ConvertFrom-Json;$map=Get-Content -LiteralPath $RoleMapPath -Raw|ConvertFrom-Json;$licenses=Get-Content -LiteralPath $LicenseConclusionsPath -Raw|ConvertFrom-Json;$root=[IO.Path]::GetFullPath($BundleRoot);$smoke=Get-Content -LiteralPath $SmokeEvidencePath -Raw|ConvertFrom-Json
if($smoke.kind-cne'hvp-libmpv-smoke-evidence'-or[string]$smoke.apiVersion-cnotmatch'^2\.(?:[5-9]|[1-9][0-9]+)$'-or$smoke.fixtureLoaded-ne$true-or$smoke.fixtureUnlocked-ne$true){throw 'Runtime libmpv smoke evidence is incomplete or incompatible.'};$LibmpvApiVersion=[string]$smoke.apiVersion
$actual=@(Get-ChildItem -LiteralPath $root -Filter '*.dll' -File -Force|ForEach-Object Name);$mapped=@($template.requiredRoles|ForEach-Object{[string]$map.$_})
if($mapped.Count-ne$template.requiredRoles.Count-or@($mapped|Where-Object{[string]::IsNullOrWhiteSpace($_)}).Count-ne 0-or@($mapped|Sort-Object -Unique).Count-ne$mapped.Count-or(@($actual|Sort-Object)-join"`n")-cne(@($mapped|Sort-Object)-join"`n")){throw 'Reviewed role map is not the exact DLL bundle closure.'}
foreach($output in @($template.outputs)){$fileName=[string]$map.($output.role);$path=Join-Path $root $fileName;$metadata=&(Join-Path $PSScriptRoot 'Get-NativePeMetadata.ps1')-Path $path;$license=[string]$licenses.($output.role);if([string]::IsNullOrWhiteSpace($license)-or$license-eq'NOASSERTION'){throw "Reviewed output license conclusion is missing: $($output.role)"};$output.path=$fileName;$output.sha256=$metadata.sha256;$output.peMachine=$metadata.peMachine;$output.imports=@($metadata.imports);$output|Add-Member -NotePropertyName delayImports -NotePropertyValue @($metadata.delayImports) -Force;$output.exports=@($metadata.exports);$output|Add-Member -NotePropertyName dllCharacteristics -NotePropertyValue $metadata.dllCharacteristics -Force;$output.apiVersion=if($output.role-eq'libmpv'){$LibmpvApiVersion}else{$null};$output.licenseConclusion=$license}
$template.closureEvidence.recursiveImportsComplete=$true;$template.closureEvidence.unexpectedDlls=@();$template.closureEvidence.systemDllAllowlistVersion=$SystemDllAllowlistVersion
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(($template|ConvertTo-Json -Depth 12)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));& (Join-Path $PSScriptRoot 'Test-NativeOutputBundle.ps1')-BundleRoot $root -OutputContractPath $OutputPath
