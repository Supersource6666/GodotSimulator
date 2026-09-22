param(
    [string]$GodotPath = 'E:\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [ValidateSet('gl_compatibility', 'mobile', 'forward_plus')]
    [string]$Renderer = 'gl_compatibility',
    [switch]$SmokeTest,
    # Accepted for compatibility; all previews now use local scene modules.
    [switch]$Local,
    [string]$LocalScene,
    [string]$ExternalProject = 'E:\game_project',
    [switch]$Loop,
    [switch]$Cab,
    # Dispatch console options.
    [switch]$SkipDispatch,
    [string]$PlanFile,
    [string]$TrainNumber,
    [string]$Departure,
    [switch]$DispatchTest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/godot-progress.ps1')
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable not found. Supply -GodotPath.'
}

# Import missing or changed resources before loading scenes. Source files and
# .import metadata alone are not enough after copying or cloning the project.
# Piping output also makes PowerShell wait for the Windows GUI executable.
Write-Host 'Checking Godot resource imports...'
& $GodotPath --headless --rendering-method $Renderer --path $PSScriptRoot --editor --import | Convert-GodotProgressToEnglish | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Godot resource import failed (exit code $LASTEXITCODE). Preview was not started."
}

# Run the dispatch console directly to smoke-test plan and timetable generation.
$mainScene = 'res://app/local.tscn'
if ($DispatchTest) {
    $mainScene = 'res://app/dispatch/dispatch_console.tscn'
}

Write-Host ("Starting preview with renderer: {0}" -f $Renderer)
$previewArgs = @('--rendering-method', $Renderer, '--path', $PSScriptRoot, $mainScene)
if ($SmokeTest -or $DispatchTest) { $previewArgs += '--headless' }
$previewArgs += '--'
$previewArgs += '--external-project=' + $ExternalProject.Replace('\', '/')
if ($LocalScene) {
    $previewArgs += '--local-scene=' + $LocalScene
}
if ($SmokeTest) { $previewArgs += '--demo-smoke-test' }
if ($DispatchTest) { $previewArgs += '--dispatch-smoke-test' }
if ($SkipDispatch) { $previewArgs += '--skip-dispatch' }
if ($PlanFile) { $previewArgs += '--dispatch-plan-file=' + $PlanFile }
if ($TrainNumber) { $previewArgs += '--train-number=' + $TrainNumber }
if ($Departure) { $previewArgs += '--departure=' + $Departure }
if ($Loop) { $previewArgs += '--offline-loop' }
if ($Cab) { $previewArgs += '--cab-view' }

& $GodotPath @previewArgs
exit $LASTEXITCODE
