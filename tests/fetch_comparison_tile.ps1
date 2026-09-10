param([double]$MaxError = 15, [string]$OutputDirectory = 'tile_diagnostic')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$diagRoot = Split-Path $PSScriptRoot -Parent
$diagOut = Join-Path $diagRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $diagOut | Out-Null
$diagToken = [IO.File]::ReadAllText((Join-Path $diagRoot 'cesium_token.txt')).Trim()
$endpoint = Invoke-RestMethod 'https://api.cesium.com/v1/assets/2275207/endpoint' -Headers @{Authorization=('Bearer '+$diagToken)} -TimeoutSec 30
$rootUrl = $endpoint.options.url
if (-not $rootUrl) { $rootUrl = $endpoint.url }
Add-Type -AssemblyName System.Web
$authQuery = [Web.HttpUtility]::ParseQueryString(([uri]$rootUrl).Query)
$rootDoc = Invoke-RestMethod $rootUrl -TimeoutSec 30
$lat = 35.6713 * [Math]::PI / 180
$lon = 139.7618 * [Math]::PI / 180
$n = 6378137 / [Math]::Sqrt(1-.00669437999014*[Math]::Pow([Math]::Sin($lat),2))
$point = @(($n*[Math]::Cos($lat)*[Math]::Cos($lon)),($n*[Math]::Cos($lat)*[Math]::Sin($lon)),($n*(1-.00669437999014)*[Math]::Sin($lat)))
function Tile-Score($tile) {
    $b = $tile.boundingVolume.box
    if (-not $b) { return 1e30 }
    $total = 0.0
    foreach ($j in @(3,6,9)) {
        $dot = 0.0; $sq = 0.0
        for ($i=0; $i -lt 3; $i++) { $dot += $b[$j+$i]*($point[$i]-$b[$i]); $sq += $b[$j+$i]*$b[$j+$i] }
        if ($sq -gt 0) { $total += [Math]::Pow([Math]::Max(0,[Math]::Abs($dot)/[Math]::Sqrt($sq)-[Math]::Sqrt($sq)),2) }
    }
    return $total
}
$queue = @(@{tile=$rootDoc.root;url=$rootUrl;depth=0;score=(Tile-Score $rootDoc.root)})
for ($step=0; $step -lt 160; $step++) {
    $queue = @($queue | Sort-Object @{Expression={[double]$_.score}},@{Expression={[int]$_.depth};Descending=$true})
    $entry=$queue[0]
    $queue=@($queue | Select-Object -Skip 1)
    $tile=$entry.tile
    Write-Output ('Traversal depth='+$entry.depth+' error='+$tile.geometricError+' score='+$entry.score)
    $relative=$tile.content.uri
    if (-not $relative) { $relative=$tile.content.url }
    if ($relative) {
        $builder=[UriBuilder]::new([uri]::new([uri]$entry.url,[string]$relative))
        $query=[Web.HttpUtility]::ParseQueryString($builder.Query)
        $parentQuery=[Web.HttpUtility]::ParseQueryString(([uri]$entry.url).Query)
        foreach ($key in $parentQuery.AllKeys) { if (-not $query[$key]) { $query[$key]=$parentQuery[$key] } }
        foreach ($key in $authQuery.AllKeys) { if (-not $query[$key]) { $query[$key]=$authQuery[$key] } }
        $builder.Query=$query.ToString()
        $url=$builder.Uri.AbsoluteUri
        if ($builder.Path.EndsWith('.glb')) {
            if ($tile.geometricError -gt $MaxError) {
                foreach ($child in $tile.children) { $queue+=@{tile=$child;url=$entry.url;depth=($entry.depth+1);score=(Tile-Score $child)} }
                continue
            }
            Invoke-WebRequest -UseBasicParsing $url -OutFile (Join-Path $diagOut 'original.glb') -TimeoutSec 40
            $clean=@{boundingVolume=$tile.boundingVolume;geometricError=$tile.geometricError;content=@{uri='original.glb'}}
            if ($tile.transform) { $clean.transform=$tile.transform }
            @{asset=@{version='1.1'};geometricError=1000;root=$clean} | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $diagOut 'tileset.json')
            Write-Output ('Selected GLB depth='+$entry.depth+' error='+$tile.geometricError+' bytes='+(Get-Item (Join-Path $diagOut 'original.glb')).Length)
            exit 0
        }
        $doc=Invoke-RestMethod $url -TimeoutSec 30
        $queue+=@{tile=$doc.root;url=$url;depth=($entry.depth+1);score=(Tile-Score $doc.root)}
    }
    foreach ($child in $tile.children) { $queue+=@{tile=$child;url=$entry.url;depth=($entry.depth+1);score=(Tile-Score $child)} }
}
throw 'No GLB found within diagnostic traversal budget'
