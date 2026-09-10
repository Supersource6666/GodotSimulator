param(
    [string]$GodotPath = 'E:\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [switch]$SmokeTest,
    [switch]$Terrain,
    [switch]$Local,
    [switch]$Loop
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable not found. Supply -GodotPath.'
}
# libcurl does not inherit Windows Internet Options. Forward the existing
# proxy only to this launch and restore the calling process environment.
$previewOldHttp = $env:HTTP_PROXY
$previewOldHttps = $env:HTTPS_PROXY
try {
    $previewTarget = [uri]'https://tile.googleapis.com/'
    $previewProxy = [Net.WebRequest]::DefaultWebProxy.GetProxy($previewTarget)
    if (-not $Local -and -not $env:HTTPS_PROXY -and $previewProxy -and $previewProxy.Authority -ne $previewTarget.Authority) {
        $env:HTTPS_PROXY = $previewProxy.AbsoluteUri
        if (-not $env:HTTP_PROXY) { $env:HTTP_PROXY = $previewProxy.AbsoluteUri }
        Write-Host 'Using the configured Windows proxy for Cesium downloads.'
    }
    $previewArgs = @('--path', $PSScriptRoot)
    if ($Local) { $previewArgs += 'res://offline.tscn' }
    if ($SmokeTest) { $previewArgs += '--headless' }
    $previewArgs += '--'
    if ($SmokeTest) { $previewArgs += '--demo-smoke-test' }
    if ($Terrain) { $previewArgs += '--terrain-preview' }
    if ($Loop) { $previewArgs += '--offline-loop' }
    # Native plugin errors may contain signed URLs. Redact query strings.
    $ErrorActionPreference = 'Continue'
    & $GodotPath @previewArgs 2>&1 | ForEach-Object {
        $_.ToString() -replace '(?i)((?:https?://|/v1/)[^\s?]+)\?[^\s]+', '$1?[redacted]'
    }
    $previewExit = $LASTEXITCODE
} finally {
    $env:HTTP_PROXY = $previewOldHttp
    $env:HTTPS_PROXY = $previewOldHttps
}
exit $previewExit
