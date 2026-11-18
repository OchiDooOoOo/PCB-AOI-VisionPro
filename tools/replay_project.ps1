# Run from the repository root with Windows PowerShell 5.1 and licensed VisionPro.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1: powershell.exe -NoProfile -STA -File tools/replay_project.ps1'
}

$projectRoot = (Get-Location).Path
$projectPath = Join-Path $projectRoot 'visionpro/PCB_AOI.vpp'
$libraryFolder = Join-Path ${env:ProgramFiles} 'Cognex/VisionPro/ReferencedAssemblies'

foreach ($assemblyName in @(
    'Cognex.VisionPro.Core.dll',
    'Cognex.VisionPro.dll',
    'Cognex.VisionPro.QuickBuild.Core.dll',
    'Cognex.VisionPro.ImageFile.dll'
)) {
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $libraryFolder $assemblyName))
}

$samples = @(
    @{ Path='images/reference/visa_pcb4_normal_0000.jpg'; Present=$true; Role='template_training' },
    @{ Path='images/raw/visa_pcb4_normal_0001.jpg'; Present=$true; Role='parameter_development' },
    @{ Path='images/raw/visa_pcb4_missing_046.jpg'; Present=$false; Role='parameter_development' },
    @{ Path='images/raw/visa_pcb4_missing_049.jpg'; Present=$true; Role='additional_replay' },
    @{ Path='images/raw/visa_pcb4_wrong_place_090.jpg'; Present=$true; Role='additional_replay' },
    @{ Path='images/raw/visa_pcb4_wrong_place_096.jpg'; Present=$true; Role='additional_replay' }
)

$manager = $null
$reader = $null
$measurements = @()

try {
    # Load a separate in-memory copy. The saved VPP is read only during replay.
    $manager = [Cognex.VisionPro.CogSerializer]::LoadObjectFromFile($projectPath)
    $job = $manager.Job(0)
    $group = $job.VisionTool
    $tools = @{}
    for ($index = 0; $index -lt $group.Tools.Count; $index++) {
        $tool = $group.Tools.Item($index)
        $tools[$tool.Name] = $tool
    }

    $locator = $tools['CogPMAlignTool1']
    $blob = $tools['CogBlobTool1']
    $configuration = [ordered]@{
        jobName = $job.Name
        tools = @($tools.Keys | Sort-Object)
        patternAlgorithm = $locator.Pattern.TrainAlgorithm.ToString()
        pmAcceptThreshold = $locator.RunParams.AcceptThreshold
        blobSpace = $blob.Region.SelectedSpaceName
        blobCenterX = $blob.Region.CenterX
        blobCenterY = $blob.Region.CenterY
        blobWidth = $blob.Region.SideXLength
        blobHeight = $blob.Region.SideYLength
        blobSegmentation = $blob.RunParams.SegmentationParams.Mode.ToString()
        blobPolarity = $blob.RunParams.SegmentationParams.Polarity.ToString()
        blobThreshold = $blob.RunParams.SegmentationParams.HardFixedThreshold
    }

    $reader = New-Object Cognex.VisionPro.ImageFile.CogImageFileTool
    foreach ($sample in $samples) {
        $imagePath = Join-Path $projectRoot $sample.Path
        $expected = 'Reject'
        if ($sample.Present) { $expected = 'Accept' }
        $measurement = [ordered]@{
            image = $sample.Path
            target = 'bottom_122_resistor'
            targetPresent = $sample.Present
            role = $sample.Role
            expected = $expected
            imageSha256 = $null
            pmCount = $null
            pmScore = $null
            pmAccepted = $null
            blobCount = $null
            blobAreas = @()
            result = 'Error'
            matchesExpected = $false
            error = $null
        }

        try {
            $measurement.imageSha256 = (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $reader.Operator.Open($imagePath, [Cognex.VisionPro.ImageFile.CogImageFileModeConstants]::Read)
            $reader.Run()
            if ($reader.RunStatus.Result.ToString() -eq 'Error') {
                throw $reader.RunStatus.Message
            }
            $tools['Image Source'].InputImage = $reader.OutputImage
            $group.Run()

            $measurement.result = $group.RunStatus.Result.ToString()
            if ($measurement.result -eq 'Error') {
                throw $group.RunStatus.Message
            }
            $measurement.pmCount = $locator.Results.Count
            if ($locator.Results.Count -gt 0) {
                $match = $locator.Results.Item(0)
                $measurement.pmScore = $match.Score
                $measurement.pmAccepted = $match.Accepted
            }
            $blobs = $blob.Results.GetBlobs()
            $measurement.blobCount = $blobs.Count
            for ($blobIndex = 0; $blobIndex -lt $blobs.Count; $blobIndex++) {
                $measurement.blobAreas += $blobs.Item($blobIndex).Area
            }
            $measurement.matchesExpected = $measurement.result -eq $expected
        }
        catch {
            $measurement.result = 'Error'
            $measurement.error = $_.Exception.Message
        }
        finally {
            $reader.Operator.Close()
        }
        $measurements += [pscustomobject]$measurement
    }

    $report = [ordered]@{
        generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        method = 'Saved VPP tool group replay using CogImageFileTool and existing data bindings'
        scope = 'Development samples and additional replay of one PCB layout, checking the bottom 122 resistor'
        project = 'visionpro/PCB_AOI.vpp'
        projectSha256 = (Get-FileHash -LiteralPath $projectPath -Algorithm SHA256).Hash.ToLowerInvariant()
        visionProAssemblyVersion = [Cognex.VisionPro.CogSerializer].Assembly.GetName().Version.ToString()
        configuration = $configuration
        samples = $measurements
    }

    $reportDirectory = Join-Path $projectRoot 'results'
    [void](New-Item -ItemType Directory -Path $reportDirectory -Force)
    $reportPath = Join-Path $reportDirectory 'development_replay.json'
    $temporaryPath = Join-Path $reportDirectory ([guid]::NewGuid().ToString('N') + '.tmp')
    $json = $report | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $reportPath -Force
    $measurements | Select-Object image, pmScore, blobCount, result, matchesExpected | Format-Table -AutoSize
}
finally {
    if ($reader -is [System.IDisposable]) { $reader.Dispose() }
    if ($manager -is [System.IDisposable]) { $manager.Dispose() }
}
