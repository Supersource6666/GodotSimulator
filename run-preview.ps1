param(
    [string]$GodotPath = 'E:\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [switch]$SmokeTest,
    # Accepted for compatibility; all previews now use local scene modules.
    [switch]$Local,
    [string]$LocalScene,
    [string]$ExternalProject = 'E:\game_project',
    [switch]$Loop,
    [switch]$Cab,
    # 调度台相关参数。
    [switch]$SkipDispatch,
    [string]$PlanFile,
    [string]$TrainNumber,
    [string]$Departure,
    [switch]$DispatchTest
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable not found. Supply -GodotPath.'
}

# Import missing or changed resources before loading scenes. Source files and
# .import metadata alone are not enough after copying or cloning the project.
# Piping output also makes PowerShell wait for the Windows GUI executable.
Write-Host 'Checking Godot resource imports...'
& $GodotPath --headless --path $PSScriptRoot --editor --import | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Godot resource import failed (exit code $LASTEXITCODE). Preview was not started."
}

# 调度台冒烟测试：直接运行调度台入口，验证方案与时刻表生成。
$mainScene = 'res://app/local.tscn'
if ($DispatchTest) {
    $mainScene = 'res://app/dispatch/dispatch_console.tscn'
}

$previewArgs = @('--path', $PSScriptRoot, $mainScene)
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
