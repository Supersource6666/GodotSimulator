param(
    [string]$PythonPath = 'E:\cv4EngineAdjust\ANACONDA\python.exe',
    [string]$GodotPath = 'E:\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [switch]$VerifyOnly,
    [switch]$Replan
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools/godot-progress.ps1')
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$offlineOldProxy = $env:HTTPS_PROXY
$offlineOldImport = $env:GODOT_OFFLINE_IMPORT
function Invoke-OfflineImport {
    # Godot 4.7 may report get_multiple_md5/f.is_null while replacing a texture
    # cache with a different compression format. Require a clean second pass;
    # persistent failures must still stop the build.
    & $GodotPath --headless --path $PSScriptRoot --editor --import | Convert-GodotProgressToEnglish | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Rechecking import after generated texture cache updates...'
        & $GodotPath --headless --path $PSScriptRoot --editor --import | Convert-GodotProgressToEnglish | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Godot resource import failed twice.' }
    }
}
Push-Location $PSScriptRoot
try {
    if ($VerifyOnly) {
        & $PythonPath tools/offline_pack.py verify
        if ($LASTEXITCODE -ne 0) { throw 'Offline package verification failed.' }
        exit 0
    }
    if (-not $env:HTTPS_PROXY) {
        $offlineTarget = [uri]'https://cyberjapandata.gsi.go.jp/'
        $offlineProxy = [Net.WebRequest]::DefaultWebProxy.GetProxy($offlineTarget)
        if ($offlineProxy -and $offlineProxy.Authority -ne $offlineTarget.Authority) {
            $env:HTTPS_PROXY = $offlineProxy.AbsoluteUri
        }
    }
    if ($Replan -or -not (Test-Path -LiteralPath 'offline_data/plan.json')) {
        & $PythonPath -u tools/offline_pack.py plan
        if ($LASTEXITCODE -ne 0) { throw 'Offline plan failed.' }
    }
    & $PythonPath -u tools/offline_pack.py build
    if ($LASTEXITCODE -ne 0) { throw 'Offline build incomplete. Re-run to reuse downloaded files.' }
    $env:GODOT_OFFLINE_IMPORT = '1'
    & $PythonPath tools/configure_offline_import.py
    if ($LASTEXITCODE -ne 0) { throw 'Offline texture configuration failed.' }
    Invoke-OfflineImport
    & $PythonPath tools/configure_offline_import.py
    if ($LASTEXITCODE -ne 0) { throw 'Offline texture configuration failed.' }
    Invoke-OfflineImport
    Write-Host 'Local package is ready: .\run-preview.ps1 -Local'
} finally {
    Pop-Location
    $env:HTTPS_PROXY = $offlineOldProxy
    $env:GODOT_OFFLINE_IMPORT = $offlineOldImport
}
