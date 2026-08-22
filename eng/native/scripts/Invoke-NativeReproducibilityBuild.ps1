[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Msys2Root,
    [Parameter(Mandatory)][string]$ToolchainEvidencePath,
    [Parameter(Mandatory)][string]$SourceArchiveDirectory,
    [Parameter(Mandatory)][string]$TarPath,
    [Parameter(Mandatory)][string]$RoleMapPath,
    [Parameter(Mandatory)][string]$WorkingRoot,
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$ManifestRoot,
    [string]$DifferenceEvidencePath
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ManifestRoot)){$ManifestRoot=Join-Path(Split-Path -Parent $PSScriptRoot)'manifests'}
$ManifestRoot=[IO.Path]::GetFullPath($ManifestRoot)
$roleMap=Get-Content -LiteralPath $RoleMapPath -Raw|ConvertFrom-Json;$roles=@((Get-Content -LiteralPath(Join-Path $ManifestRoot 'output-contract.json')-Raw|ConvertFrom-Json).requiredRoles)
if(@($roles|Where-Object{[string]::IsNullOrWhiteSpace([string]$roleMap.$_)}).Count-ne 0){throw 'Reviewed output role map is incomplete.'}
$root=[IO.Path]::GetFullPath($WorkingRoot)
if(Test-Path -LiteralPath $root){throw 'Reproducibility working root must be a new clean directory.'}
New-Item -ItemType Directory -Path $root|Out-Null
try{
    $buildRecords=@();$buildLocations=@()
    for($iteration=1;$iteration-le 2;$iteration++){
        $iterationRoot=Join-Path $root "build-$iteration";New-Item -ItemType Directory -Path $iterationRoot|Out-Null
        $sources=Join-Path $iterationRoot 'sources';$sourceEvidence=Join-Path $iterationRoot 'source-evidence.json'
        &(Join-Path $PSScriptRoot 'Expand-NativeSourceArchives.ps1')-ArchiveDirectory $SourceArchiveDirectory -SourceDirectory $sources -TarPath $TarPath -ManifestPath(Join-Path $ManifestRoot 'native-inputs.json')-ToolchainLockPath(Join-Path $ManifestRoot 'toolchain.lock.json')-EvidencePath $sourceEvidence|Out-Null
        $build=Join-Path $iterationRoot 'build';$prefix=Join-Path $iterationRoot 'prefix';$evidence=Join-Path $iterationRoot 'evidence'
        &(Join-Path $PSScriptRoot 'Invoke-NativeBuild.ps1')-Msys2Root $Msys2Root -SourceRoot $sources -BuildRoot $build -Prefix $prefix -EvidenceRoot $evidence -ToolchainEvidencePath $ToolchainEvidencePath -SourceEvidencePath $sourceEvidence -ManifestRoot $ManifestRoot|Out-Null
        $dllRoot=Join-Path $prefix 'bin';$dlls=@(Get-ChildItem -LiteralPath $dllRoot -Filter '*.dll' -File -Force)
        if($dlls.Count-eq 0){throw "Clean build $iteration produced no DLLs."}
        $actualNames=@($dlls|ForEach-Object Name);$mappedNames=@($roles|ForEach-Object{[string]$roleMap.$_});if((@($actualNames|Sort-Object)-join"`n")-cne(@($mappedNames|Sort-Object)-join"`n")){throw "Clean build $iteration DLL closure differs from the reviewed role map."}
        $hashes=[ordered]@{};foreach($role in $roles){$hashes[$role]=(Get-FileHash -LiteralPath(Join-Path $dllRoot([string]$roleMap.$role))-Algorithm SHA256).Hash.ToLowerInvariant()}
        $buildRecords+=[ordered]@{id="clean-$iteration";outputHashes=$hashes};$buildLocations+=[ordered]@{id="clean-$iteration";prefix=$prefix;evidenceDirectory=$evidence}
    }
    $first=$buildRecords[0].outputHashes|ConvertTo-Json -Compress;$second=$buildRecords[1].outputHashes|ConvertTo-Json -Compress
    $status=if($first-ceq$second){'identical'}else{'difference-explained'}
    if($status-ceq'difference-explained'){
        if([string]::IsNullOrWhiteSpace($DifferenceEvidencePath)-or-not(Test-Path -LiteralPath $DifferenceEvidencePath -PathType Leaf)){throw 'Clean native builds differ; reviewed difference evidence is required.'}
    }
    $record=[ordered]@{schemaVersion=1;kind='hvp-native-reproducibility-evidence';status=$status;cleanBuilds=$buildRecords;buildLocations=$buildLocations;differenceEvidencePath=$DifferenceEvidencePath;normalizedInputs=@('SOURCE_DATE_EPOCH','TZ=UTC','LC_ALL=C','file-prefix-map','debug-prefix-map','deterministic-archives')}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath),(($record|ConvertTo-Json -Depth 10)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));[pscustomobject]$record
}catch{throw}
