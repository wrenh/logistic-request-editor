param(
    [Parameter(Mandatory = $true)]
    [string]$FactorioPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $FactorioPath -PathType Leaf)) {
    throw "Factorio executable not found: $FactorioPath"
}

$repository = Split-Path -Parent $PSScriptRoot
$dataPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $FactorioPath) '..\..\data'))
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('first-factorio-mod-tests-' + [Guid]::NewGuid().ToString('N'))))
$modDirectory = Join-Path $testRoot 'mods'
$packagedMod = Join-Path $modDirectory 'first-factorio-mod'
$userData = Join-Path $testRoot 'user-data'
$scenario = Join-Path $userData 'scenarios\bulk-import-tests'
New-Item -ItemType Directory -Path $packagedMod, $scenario -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $repository 'info.json') -Destination $packagedMod
Copy-Item -LiteralPath (Join-Path $repository 'control.lua') -Destination (Join-Path $packagedMod 'editor.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scenario\mod-control.lua') -Destination (Join-Path $packagedMod 'control.lua')
$settingsFile = Join-Path $repository 'settings.lua'
if (Test-Path -LiteralPath $settingsFile -PathType Leaf) {
    Copy-Item -LiteralPath $settingsFile -Destination $packagedMod
}
$dataFile = Join-Path $repository 'data.lua'
if (Test-Path -LiteralPath $dataFile -PathType Leaf) {
    Copy-Item -LiteralPath $dataFile -Destination $packagedMod
}
Copy-Item -LiteralPath (Join-Path $repository 'graphics') -Destination $packagedMod -Recurse
Copy-Item -LiteralPath (Join-Path $repository 'locale') -Destination $packagedMod -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scenario\data-final-fixes.lua') -Destination $packagedMod
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scenario\control.lua') -Destination $scenario

@('[path]', ('read-data=' + $dataPath), ('write-data=' + $userData)) |
    Set-Content -LiteralPath (Join-Path $testRoot 'config.ini') -Encoding ASCII
$mods = foreach ($name in @('base', 'elevated-rails', 'quality', 'recycler', 'space-age', 'first-factorio-mod')) {
    @{ name = $name; enabled = $true }
}
@{ mods = @($mods) } | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $modDirectory 'mod-list.json') -Encoding ASCII

$arguments = @(
    '--config', ('"' + (Join-Path $testRoot 'config.ini') + '"'),
    '--mod-directory', ('"' + $modDirectory + '"'),
    '--test-scenario', 'bulk-import-tests',
    '--disable-audio'
)
$process = Start-Process -FilePath $FactorioPath -ArgumentList $arguments -Wait -PassThru `
    -RedirectStandardOutput (Join-Path $testRoot 'stdout.txt') `
    -RedirectStandardError (Join-Path $testRoot 'stderr.txt')
$logPath = Join-Path $userData 'factorio-current.log'
if ($process.ExitCode -ne 0 -or -not (Select-String -LiteralPath $logPath -SimpleMatch 'BULK_IMPORT_TESTS_PASSED' -Quiet)) {
    Get-Content -LiteralPath $logPath -Tail 40
    throw "Factorio integration tests failed. Test files retained at: $testRoot"
}

Select-String -LiteralPath $logPath -SimpleMatch 'BULK_IMPORT_TEST:' | ForEach-Object { $_.Line }
Write-Output 'Factorio integration tests passed.'
Remove-Item -LiteralPath $testRoot -Recurse -Force
