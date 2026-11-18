# Run from the repository root in Windows PowerShell 5.1 with VisionPro licensed.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell 5.1 required.' }
$root = (Get-Location).Path
$folder = Join-Path $env:ProgramFiles 'Cognex/VisionPro/ReferencedAssemblies'
foreach ($name in @('Cognex.VisionPro.Core.dll', 'Cognex.VisionPro.dll',
    'Cognex.VisionPro.QuickBuild.Core.dll', 'Cognex.VisionPro.ImageFile.dll')) {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $folder $name))
}
$sourcePath = Join-Path $root 'visionpro/PCB_AOI.vpp'
$outputPath = Join-Path $root 'visionpro/PCB_AOI_position.vpp'
$manager = [Cognex.VisionPro.CogSerializer]::LoadObjectFromFile($sourcePath)
$group = $manager.Job(0).VisionTool
if ($null -eq $group.Tools['CogPMAlignTool2']) { throw 'Second PMAlign tool is missing.' }
if ($null -ne $group.Script) { throw 'Source already contains a script; review it before replacing.' }
$group.CreateNewScript([Cognex.VisionPro.Implementation.Internal.CogScriptLanguageConstants]::ScriptCSharp)
$script = $group.Script
foreach ($name in @('CogPMAlignTool1', 'CogBlobTool1')) {
    $reference = New-Object Cognex.VisionPro.Implementation.Internal.CogReferencedAssembly($group.Tools[$name].GetType().Assembly)
    [void]$script.References.Add($reference)
}
$script.Source = [IO.File]::ReadAllText((Join-Path $root 'visionpro/InspectionScript.cs'))
if (!$script.TempCompile()) {
    $details = ($script.Results.Errors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "Compilation failed: $details"
}
$group.Script = $script
# Freeze the training image's coordinate tree. Running Fixture on an image shared
# with TrainImage can otherwise invalidate this trained pattern.
$pattern = $group.Tools['CogPMAlignTool2'].Pattern
$pattern.TrainImage = $pattern.TrainImage.CopyBase([Cognex.VisionPro.CogImageCopyModeConstants]::CopyPixels)
$pattern.Train()
$reader = New-Object Cognex.VisionPro.ImageFile.CogImageFileTool
try {
    $reader.Operator.Open((Join-Path $root 'images/raw/visa_pcb4_normal_0001.jpg'),
        [Cognex.VisionPro.ImageFile.CogImageFileModeConstants]::Read)
    $reader.Run()
    $group.Tools['Image Source'].InputImage = $reader.OutputImage
    $group.Run()
}
finally { $reader.Operator.Close() }
if ($group.RunStatus.Result.ToString() -eq 'Error') {
    throw "Script error: $($group.ScriptError) $($group.RunStatus.Message)"
}
if ($group.ScriptData['Reason'] -ne 'PASS') {
    throw "Normal image failed: $($group.ScriptData['Reason']) $($group.ScriptData['ErrorDetail'])"
}
# Post the guarded per-frame values. Reading Blob.Results directly after a board
# failure could otherwise publish a stale count from the previous frame.
$job = $manager.Job(0)
$postedKeys = @('BlobCount','Decision','Reason','FinalOK','BoardFound','TargetFound',
    'TargetX','TargetY','DeltaX','DeltaY','BoardScore','TargetScore','ErrorDetail')
$existingLinks = @()
for ($i=0; $i -lt $job.VisionToolLinkCount; $i++) { $existingLinks += $job.VisionToolLink($i).LinkName }
foreach ($key in $postedKeys) {
    if ($existingLinks -contains $key) { $job.VisionToolLinkRemove($key) }
    $path = '(Cognex.VisionPro.ToolGroup.CogToolGroup).ScriptData.Item["' + $key + '"]'
    $link = New-Object Cognex.VisionPro.QuickBuild.Implementation.CogVTLink(
        [Cognex.VisionPro.QuickBuild.Implementation.CogLinkTypeConstants]::OutputResult,
        $key, $group, $null, $null, $path, '',
        [Cognex.VisionPro.QuickBuild.CogDestinationQueueConstants]::User)
    $job.VisionToolLinkAdd($link)
}
[Cognex.VisionPro.CogSerializer]::SaveObjectToFile($manager, $outputPath)
[pscustomobject]@{project='visionpro/PCB_AOI_position.vpp';
    sourceSha256=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant();
    projectSha256=(Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant();
    result=$group.RunStatus.Result.ToString(); reason=$group.ScriptData['Reason'];
    errorDetail=$group.ScriptData['ErrorDetail']} | ConvertTo-Json
