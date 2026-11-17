param(
    [string]$RobloxRoot = (Join-Path $env:USERPROFILE 'AppData\Local\Roblox'),
    [switch]$AssetsOnly,
    [string]$KitDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($KitDirectory) {
    $codeWork=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $projectRoot) '99_Code_Work'))
    $KitDirectory=[IO.Path]::GetFullPath($KitDirectory)
    if (-not $KitDirectory.StartsWith($codeWork+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Expected a task directory in 99_Code_Work' }
}
function Sync-RoAsset([string]$Source,[string]$Target) {
    $hash=(Get-FileHash -LiteralPath $Source).Hash
    if ((Test-Path -LiteralPath $Target -PathType Leaf) -and (Get-FileHash -LiteralPath $Target).Hash -eq $hash) { return }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    if ((Get-FileHash -LiteralPath $Target).Hash -ne $hash) { throw ('Asset copy verification failed: '+$Target) }
}
$versionsRoot = [IO.Path]::GetFullPath((Join-Path $RobloxRoot 'Versions'))
$studios = @(Get-ChildItem -LiteralPath $versionsRoot -Filter RobloxStudioBeta.exe -Recurse)
if ($studios.Count -eq 0) { throw 'Roblox Studio installation not found' }
# Install into every existing Studio version. An updater can switch the active
# executable between finding the newest file and opening the place.
$runningStudios = @(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | ForEach-Object { $_.Path } | Where-Object { $_ })
foreach ($runningPath in $runningStudios) {
    if (-not ($studios.FullName -contains $runningPath)) { throw ('Running Studio is outside the detected installation: ' + $runningPath) }
}
$assetSource = Join-Path $projectRoot 'assets\tree\local'
$files = @('ConnectedWood.mesh', 'ConnectedBark.png', 'GinkgoCluster.png') | ForEach-Object { Get-Item -LiteralPath (Join-Path $assetSource $_) }
if (Test-Path -LiteralPath (Join-Path $assetSource 'ProceduralBark.png')) {
    $files += @('ProceduralBark.png','Procedural6.mesh','Procedural9.mesh','Procedural12.mesh') | ForEach-Object { Get-Item -LiteralPath (Join-Path $assetSource $_) }
}
$installations = @()
foreach ($studio in $studios) {
    $fullDestination = [IO.Path]::GetFullPath((Join-Path $studio.Directory.FullName 'content\BoraTreeKitV3'))
    if (-not $fullDestination.StartsWith($versionsRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not $fullDestination.EndsWith('\content\BoraTreeKitV3')) {
        throw 'Unexpected asset destination'
    }
    New-Item -ItemType Directory -Path $fullDestination -Force | Out-Null
    foreach ($file in $files) {
        $target = Join-Path $fullDestination $file.Name
        Sync-RoAsset $file.FullName $target
    }
    $installations += $fullDestination
    $roadDestination = [IO.Path]::GetFullPath((Join-Path $studio.Directory.FullName 'content\BoraRoadKit'))
    if (-not $roadDestination.StartsWith($versionsRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not $roadDestination.EndsWith('\content\BoraRoadKit')) { throw 'Unexpected road asset destination' }
    New-Item -ItemType Directory -Path $roadDestination -Force | Out-Null
    $mapImage = Join-Path $projectRoot 'assets\maps\local\MapReference.png'
    $mapTarget = Join-Path $roadDestination 'MapReference.png'
    Sync-RoAsset $mapImage $mapTarget
    foreach ($name in @('TrafficSignal.mesh','TrafficSignalExtension.mesh','TrafficSignal.png','PedestrianSignal.mesh','PedestrianSignal.png')) {
        $sourceAsset = Join-Path $projectRoot ('assets\traffic\local\' + $name)
        $targetAsset = Join-Path $roadDestination $name
        Sync-RoAsset $sourceAsset $targetAsset
    }
    $vehicleDestination = [IO.Path]::GetFullPath((Join-Path $studio.Directory.FullName 'content\BoraVehicleKit'))
    if (-not $vehicleDestination.StartsWith($versionsRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not $vehicleDestination.EndsWith('\content\BoraVehicleKit')) { throw 'Unexpected vehicle asset destination' }
    New-Item -ItemType Directory -Path $vehicleDestination -Force | Out-Null
    $vehicleManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'assets\vehicles\local\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $vehicleNames = @($vehicleManifest.Parts | ForEach-Object { $_.File; if ($_.Texture) { $_.Texture } } | Sort-Object -Unique)
    $vehicleFiles = @($vehicleNames | ForEach-Object { Get-Item -LiteralPath (Join-Path $projectRoot ('assets\vehicles\local\' + $_)) })
    foreach ($file in $vehicleFiles) {
        $targetAsset=Join-Path $vehicleDestination $file.Name
        Sync-RoAsset $file.FullName $targetAsset
    }
}
if ($AssetsOnly) {
    Write-Output ('Verified tree, road, signal and vehicle assets in '+$studios.Count+' Studio installation(s).')
    return
}
$pluginDestination = Join-Path $RobloxRoot 'Plugins'
New-Item -ItemType Directory -Path $pluginDestination -Force | Out-Null
foreach ($kitName in @('BoraTreeKit','BoraRoadKit')) {
$source = if ($KitDirectory) { Join-Path $KitDirectory ($kitName+'.rbxmx') } else { Join-Path $projectRoot ('dist\' + $kitName + '.rbxmx') }
$target = Join-Path $pluginDestination ($kitName + '.rbxmx')
if (Test-Path -LiteralPath $target) {
    $backupDir = if ($KitDirectory) { Join-Path $KitDirectory 'PluginBackup' } else { Join-Path $projectRoot 'archive\plugin-backups' }
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir ($kitName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.rbxmx')
    Copy-Item -LiteralPath $target -Destination $backup
    if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) { throw 'Plugin backup verification failed' }
}
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw 'Plugin copy verification failed' }
}
Write-Output ('Installed tree plugin and ' + $files.Count + ' verified local asset files.')
Write-Output $installations
Write-Output ('Verified Studio versions: ' + $studios.Count + '; running Studio processes: ' + $runningStudios.Count)
$reportDir=if ($KitDirectory) {$KitDirectory} else {Join-Path $projectRoot 'dist'}
@{ installedAt = (Get-Date).ToString('o'); studioExecutables = @($studios.FullName); assetFolders = $installations; runningStudios = $runningStudios } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportDir 'local-installation.json') -Encoding UTF8
Write-Output 'These rbxasset references are for this PC. Publish/import FBX assets to Roblox before online/mobile distribution.'
