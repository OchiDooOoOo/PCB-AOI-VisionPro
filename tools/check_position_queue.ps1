# Verify acquisition and posted results after a fresh load of the saved application.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell 5.1 required.' }
$root = (Get-Location).Path
$folder = Join-Path $env:ProgramFiles 'Cognex/VisionPro/ReferencedAssemblies'
foreach ($name in @('Cognex.VisionPro.Core.dll','Cognex.VisionPro.dll',
    'Cognex.VisionPro.QuickBuild.Core.dll','Cognex.VisionPro.ImageFile.dll')) {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $folder $name))
}
$path = Join-Path $root 'visionpro/PCB_AOI_position.vpp'
$manager = [Cognex.VisionPro.CogSerializer]::LoadObjectFromFile($path)
$job = $manager.Job(0)
$group = $job.VisionTool
$cases = @(
    @{Image='images/raw/visa_pcb4_normal_0001.jpg'; Reason='PASS'; Override=$false},
    @{Image='images/raw/visa_pcb4_missing_046.jpg'; Reason='TARGET_MISSING'; Override=$false},
    @{Image='images/raw/visa_pcb4_normal_0001.jpg'; Reason='BOARD_NOT_FOUND'; Override=$true},
    @{Image='images/raw/visa_pcb4_normal_0001.jpg'; Reason='PASS'; Override=$false}
)
$savedThreshold = $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold
$measurements = @()
foreach ($case in $cases) {
    $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold = $savedThreshold
    if ($case.Override) { $group.Tools['CogPMAlignTool1'].RunParams.AcceptThreshold = 1.0 }
    $job.AcqFifo.Filename = Join-Path $root $case.Image
    $manager.Run()
    $packet = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ($null -eq $packet -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $packet = $manager.UserResult()
    }
    if ($null -eq $packet) { throw 'No result packet received.' }
    $stopDeadline = [DateTime]::UtcNow.AddSeconds(8)
    while ($manager.JobsRunningState -ne [Cognex.VisionPro.QuickBuild.CogJobsRunningStateConstants]::None -and [DateTime]::UtcNow -lt $stopDeadline) {
        Start-Sleep -Milliseconds 50
    }
    if ($manager.JobsRunningState -ne [Cognex.VisionPro.QuickBuild.CogJobsRunningStateConstants]::None) {
        throw 'Job did not stop after producing a result.'
    }
    $fields = [ordered]@{}
    for ($i=0; $i -lt $packet.SubRecords.Count; $i++) {
        $record = $packet.SubRecords.Item($i)
        if ($record.RecordKey -eq 'ShowLastRunRecordForUserQueue') { continue }
        if ($record.RecordKey -eq 'RunStatus') {
            $fields['RunStatus'] = $record.Content.Result.ToString()
            $fields['Message'] = $record.Content.Message
        }
        else {
            $value = $record.Content
            if ($value -is [double] -and ([double]::IsNaN($value) -or [double]::IsInfinity($value))) { $value = $null }
            $fields[$record.RecordKey] = $value
        }
    }
    $expectedResult = 'Reject'
    if ($case.Reason -eq 'PASS') { $expectedResult = 'Accept' }
    $valid = $fields['Reason'] -eq $case.Reason -and $fields['RunStatus'] -eq $expectedResult
    if ($case.Override -and $fields['BlobCount'] -ne 0) { $valid = $false }
    $measurements += [pscustomobject]@{image=$case.Image; imageSha256=(Get-FileHash -LiteralPath (Join-Path $root $case.Image) -Algorithm SHA256).Hash.ToLowerInvariant();
        boardThresholdOverride=if($case.Override){1.0}else{$null}; expectedReason=$case.Reason; fields=$fields; matchesExpected=$valid}
}
$report = [ordered]@{generatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');
    project='visionpro/PCB_AOI_position.vpp'; projectSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();
    method='Freshly deserialized CogJobManager: change synthetic acquisition Filename, Run, read UserResult packet';
    note='Threshold override exercises the failure guard only; the image remains unmodified';
    cases=$measurements}
[IO.File]::WriteAllText((Join-Path $root 'results/position_queue_check.json'),($report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$measurements|Select-Object image,expectedReason,@{N='Actual';E={$_.fields['Reason']}},@{N='BlobCount';E={$_.fields['BlobCount']}},matchesExpected|Format-Table -AutoSize
if (@($measurements|Where-Object {!$_.matchesExpected}).Count -gt 0) { throw 'Queue check failed.' }
