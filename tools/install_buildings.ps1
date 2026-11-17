param([string]$RobloxRoot=(Join-Path $env:USERPROFILE 'AppData\Local\Roblox'),[string]$KitPath,[string]$WorkDirectory)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if ($WorkDirectory) {
    $codeWork=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $projectRoot) '99_Code_Work'))
    $WorkDirectory=[IO.Path]::GetFullPath($WorkDirectory)
    if (-not $WorkDirectory.StartsWith($codeWork+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Expected a task directory in 99_Code_Work'}
    if (-not $KitPath) {throw 'Provide the staged kit path'}
}
$versionsRoot=[IO.Path]::GetFullPath((Join-Path $RobloxRoot 'Versions'))
$studios=@(Get-ChildItem -LiteralPath $versionsRoot -Filter RobloxStudioBeta.exe -Recurse)
if ($studios.Count -eq 0) {throw 'Roblox Studio installation not found'}
$manifest=Get-Content -LiteralPath (Join-Path $projectRoot 'assets\buildings\local\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$targets=@()
foreach ($studio in $studios) {
    $destination=[IO.Path]::GetFullPath((Join-Path $studio.Directory.FullName 'content\BoraBuildingKit'))
    if (-not $destination.StartsWith($versionsRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $destination.EndsWith('\content\BoraBuildingKit')) {throw 'Unexpected destination'}
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($part in $manifest.Parts) {
        $source=Join-Path $projectRoot ('assets\buildings\local\'+$part.File)
        $target=Join-Path $destination $part.File
        Copy-Item -LiteralPath $source -Destination $target -Force
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {throw 'Asset hash mismatch'}
        $targets+=$target
    }
}
$plugins=Join-Path $RobloxRoot 'Plugins';New-Item -ItemType Directory -Path $plugins -Force | Out-Null
$source=if ($KitPath) {$KitPath} else {Join-Path $projectRoot 'dist\BoraBuildingKit.rbxmx'};$target=Join-Path $plugins 'BoraBuildingKit.rbxmx'
if (Test-Path -LiteralPath $target) {
    $backupDir=if ($WorkDirectory) {Join-Path $WorkDirectory 'PluginBackup'} else {Join-Path $projectRoot 'archive\plugin-backups'}
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir ('BoraBuildingKit-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'.rbxmx'))
}
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {throw 'Plugin hash mismatch'}
$reportDir=if ($WorkDirectory) {$WorkDirectory} else {Join-Path $projectRoot 'dist'}
@{plugin=$target;assets=$targets;verified=$true;studioOpened=$false} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportDir 'building-local-installation.json') -Encoding UTF8
Write-Output ('Installed building editor and '+$manifest.Parts.Count+' cleaned lamp mesh files; no Studio activation.')
