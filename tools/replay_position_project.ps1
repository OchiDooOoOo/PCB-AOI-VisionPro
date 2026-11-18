# Native VisionPro replay. Requires Windows PowerShell 5.1; run at repository root.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell 5.1 required.' }
$root = (Get-Location).Path
$folder = Join-Path $env:ProgramFiles 'Cognex/VisionPro/ReferencedAssemblies'
foreach ($name in @('Cognex.VisionPro.Core.dll','Cognex.VisionPro.dll',
    'Cognex.VisionPro.QuickBuild.Core.dll','Cognex.VisionPro.ImageFile.dll')) {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $folder $name))
}
$projectPath = Join-Path $root 'visionpro/PCB_AOI_position.vpp'
$manager = [Cognex.VisionPro.CogSerializer]::LoadObjectFromFile($projectPath)
$group = $manager.Job(0).VisionTool
$reader = New-Object Cognex.VisionPro.ImageFile.CogImageFileTool

function Measure-Image([string]$path, [string]$expectedReason, [string]$role) {
    $fullPath = Join-Path $root $path
    try {
        $reader.Operator.Open($fullPath, [Cognex.VisionPro.ImageFile.CogImageFileModeConstants]::Read)
        $reader.Run()
        if ($reader.RunStatus.Result.ToString() -eq 'Error') { throw $reader.RunStatus.Message }
        $group.Tools['Image Source'].InputImage = $reader.OutputImage
        $group.Run()
        $values = [ordered]@{}
        foreach ($key in @('Decision','Reason','FinalOK','BoardFound','TargetFound',
            'BoardScore','TargetScore','TargetX','TargetY','DeltaX','DeltaY','BlobCount','ErrorDetail')) {
            $value = $group.ScriptData[$key]
            if ($value -is [double] -and ([double]::IsNaN($value) -or [double]::IsInfinity($value))) {
                $value = $null
            }
            $values[$key] = $value
        }
        $expectedResult = 'Reject'
        if ($expectedReason -eq 'PASS') { $expectedResult = 'Accept' }
        return [pscustomobject][ordered]@{
            image=$path; imageSha256=(Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant();
            role=$role; expectedReason=$expectedReason; expectedResult=$expectedResult;
            result=$group.RunStatus.Result.ToString(); message=$group.RunStatus.Message;
            values=$values;
            matchesExpected=($group.RunStatus.Result.ToString() -eq $expectedResult -and $values['Reason'] -eq $expectedReason)
        }
    }
    finally { $reader.Operator.Close() }
}

$samples = @(
    Measure-Image 'images/reference/visa_pcb4_normal_0000.jpg' 'PASS' 'template_training'
    Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'PASS' 'parameter_development'
    Measure-Image 'images/raw/visa_pcb4_missing_046.jpg' 'TARGET_MISSING' 'parameter_development'
    Measure-Image 'images/raw/visa_pcb4_missing_049.jpg' 'PASS' 'additional_replay'
    Measure-Image 'images/raw/visa_pcb4_wrong_place_090.jpg' 'PASS' 'additional_replay'
    Measure-Image 'images/raw/visa_pcb4_wrong_place_096.jpg' 'PASS' 'additional_replay'
)
$checks = @()
# These exercise control logic by changing parameters on the in-memory copy.
# They are not shifted images, physical defects, or accuracy-test samples.
$savedTX = $group.ScriptData['ToleranceX']
try {
    $group.ScriptData['ToleranceX'] = [double]0.1
    $row = Measure-Image 'images/reference/visa_pcb4_normal_0000.jpg' 'TARGET_OUT_OF_POSITION' 'logic_check_only'
    $checks += [pscustomobject]@{override=@{ToleranceX=0.1}; measurement=$row}
}
finally { $group.ScriptData['ToleranceX'] = $savedTX }
$checks += [pscustomobject]@{override=@{}; measurement=(Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'PASS' 'recovery_check')}

$savedThreshold = $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold
try {
    $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold = 1.0
    $row = Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'BOARD_NOT_FOUND' 'logic_check_only'
    # Some SDK versions return an unaccepted candidate, others an empty collection.
    if ($row.values['Reason'] -eq 'BOARD_LOW_SCORE') {
        $row.expectedReason = 'BOARD_LOW_SCORE'
        $row.matchesExpected = $row.result -eq 'Reject'
    }
    $checks += [pscustomobject]@{override=@{BoardAcceptThreshold=1.0}; measurement=$row}
}
finally { $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold = $savedThreshold }
$checks += [pscustomobject]@{override=@{}; measurement=(Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'PASS' 'recovery_check')}

try {
    $group.ScriptData['ToleranceX'] = [double]0
    $checks += [pscustomobject]@{override=@{ToleranceX=0}; measurement=(Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'INVALID_TOLERANCE' 'logic_check_only')}
}
finally { $group.ScriptData['ToleranceX'] = $savedTX }
$checks += [pscustomobject]@{override=@{}; measurement=(Measure-Image 'images/raw/visa_pcb4_missing_046.jpg' 'TARGET_MISSING' 'recovery_check')}
$checks += [pscustomobject]@{override=@{}; measurement=(Measure-Image 'images/raw/visa_pcb4_normal_0001.jpg' 'PASS' 'recovery_check')}

$report = [ordered]@{
    generatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');
    method='Native CogImageFileTool and saved QuickBuild application tool-group replay';
    scope='Development replay for bottom 122 resistor only; no independent accuracy claim';
    project='visionpro/PCB_AOI_position.vpp';
    projectSha256=(Get-FileHash -LiteralPath $projectPath -Algorithm SHA256).Hash.ToLowerInvariant();
    scriptSha256=(Get-FileHash -LiteralPath (Join-Path $root 'visionpro/InspectionScript.cs') -Algorithm SHA256).Hash.ToLowerInvariant();
    configuration=@{ReferenceX=$group.ScriptData['ReferenceX']; ReferenceY=$group.ScriptData['ReferenceY'];
        ToleranceX=$savedTX; ToleranceY=$group.ScriptData['ToleranceY'];
        unit='Uncalibrated PCB coordinate units at nominal scale 1; pixel-scale, not millimetres'};
    samples=$samples; logicChecks=$checks;
    limitations=@('Position limits are coarse development settings',
        'No confirmed bottom-122 displaced defect sample has been evaluated',
        'Parameter overrides test logic only and are excluded from image-test counts')
}
$path = Join-Path $root 'results/position_replay.json'
[IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
$samples | Select-Object image,result,@{N='Reason';E={$_.values['Reason']}},@{N='X';E={$_.values['TargetX']}},@{N='Y';E={$_.values['TargetY']}},matchesExpected | Format-Table -AutoSize
$checks | ForEach-Object {$_.measurement} | Select-Object role,result,message,matchesExpected | Format-Table -AutoSize
$failed = @($samples | Where-Object {!$_.matchesExpected}) + @($checks | Where-Object {!$_.measurement.matchesExpected})
if ($failed.Count -gt 0) { throw "Replay failed for $($failed.Count) cases. See results/position_replay.json" }
