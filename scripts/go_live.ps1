# Go LIVE with ZERO credit card.
# Cloudflare quick tunnel (free) + Godot dedicated server + Solana wager gateway.
#
#   powershell -ExecutionPolicy Bypass -File scripts/go_live.ps1 -Push
#
# Leave this window open while people play. Ctrl+C stops everything.

param(
  [switch]$Push,
  [int]$GodotPort = 9080,
  [int]$GatewayPort = 9081
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$godot = Join-Path $root "tools\Godot_v4.3-stable_win64_console.exe"
if (-not (Test-Path $godot)) { Write-Host "Missing Godot at $godot"; exit 1 }

$cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cfCmd) {
  $cloudflared = $cfCmd.Source
} else {
  $cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
}
if (-not (Test-Path $cloudflared)) { Write-Host "Install cloudflared (free, no CC)."; exit 1 }

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) { Write-Host "Node.js required for wager gateway."; exit 1 }
$node = $nodeCmd.Source

$gwDir = Join-Path $root "services\live-gateway"
if (-not (Test-Path (Join-Path $gwDir "node_modules"))) {
  Write-Host "==> npm install live-gateway..."
  Push-Location $gwDir
  npm install --omit=dev
  Pop-Location
}

$env:TRENCHWAR_DEDICATED = "1"
$env:TRENCHWAR_PORT = "$GodotPort"
if (-not $env:WAGER_SETTLE_SECRET) { $env:WAGER_SETTLE_SECRET = "trenchwar-dev-settle" }
if (-not $env:SOLANA_CLUSTER) { $env:SOLANA_CLUSTER = "devnet" }

Write-Host "==> Godot dedicated :$GodotPort"
$godotProc = Start-Process -FilePath $godot -ArgumentList @(
  "--headless", "--path", $root, "res://server/ServerMain.tscn"
) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
if ($godotProc.HasExited) {
  Write-Host "Godot failed to start - port in use?"
  exit 1
}

Write-Host "==> Wager gateway :$GatewayPort"
$env:PORT = "$GatewayPort"
$env:GODOT_WS = "http://127.0.0.1:$GodotPort"
$gwProc = Start-Process -FilePath $node -ArgumentList @("server.js") -WorkingDirectory $gwDir -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
if ($gwProc.HasExited) {
  Write-Host "Gateway failed to start"
  Stop-Process -Id $godotProc.Id -Force -ErrorAction SilentlyContinue
  exit 1
}

$tunnelOut = Join-Path $env:TEMP "trenchwar_cf_tunnel.out.log"
$tunnelErr = Join-Path $env:TEMP "trenchwar_cf_tunnel.err.log"
foreach ($f in @($tunnelOut, $tunnelErr)) {
  if (Test-Path $f) { Remove-Item $f -Force }
}
Write-Host "==> Cloudflare quick tunnel (free, no credit card)..."
$cfProc = Start-Process -FilePath $cloudflared -ArgumentList @(
  "tunnel", "--url", "http://127.0.0.1:$GatewayPort", "--no-autoupdate"
) -PassThru -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr -WindowStyle Hidden

$publicHttps = $null
for ($i = 0; $i -lt 45; $i++) {
  Start-Sleep -Seconds 1
  $txt = ""
  foreach ($f in @($tunnelOut, $tunnelErr)) {
    if (Test-Path $f) {
      $txt += (Get-Content $f -Raw -ErrorAction SilentlyContinue)
    }
  }
  if ($txt -match "https://[a-z0-9-]+\.trycloudflare\.com") {
    $publicHttps = $Matches[0]
    break
  }
  if ($cfProc.HasExited) { break }
}

if (-not $publicHttps) {
  Write-Host "Tunnel failed. Log tail:"
  foreach ($f in @($tunnelOut, $tunnelErr)) {
    if (Test-Path $f) { Get-Content $f | Select-Object -Last 40 }
  }
  Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue
  Stop-Process -Id $gwProc.Id -Force -ErrorAction SilentlyContinue
  Stop-Process -Id $godotProc.Id -Force -ErrorAction SilentlyContinue
  exit 1
}

$wss = $publicHttps -replace "^https://", "wss://"
$configObj = [ordered]@{
  wss            = $wss
  wager_api      = $publicHttps
  solana_cluster = $env:SOLANA_CLUSTER
  updated        = (Get-Date).ToUniversalTime().ToString("o")
}
$config = ($configObj | ConvertTo-Json -Compress)
# UTF-8 without BOM — Godot JSON.parse_string rejects EF BB BF
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $root "web\net_config.json"), $config, $utf8NoBom)

Write-Host ""
Write-Host "=============================================="
Write-Host " LIVE (no CC)"
Write-Host "  WSS:       $wss"
Write-Host "  WAGER API: $publicHttps"
Write-Host "  Cluster:   $($env:SOLANA_CLUSTER)"
Write-Host "=============================================="
Write-Host "Keep this window OPEN. Players -> ONLINE -> QUICK PLAY"
Write-Host ""

if ($Push) {
  git add web/net_config.json
  $msg = "Update live Cloudflare WSS + wager endpoint."
  git commit -m $msg 2>$null
  git push origin HEAD
  Write-Host "Pushed net_config - Vercel will refresh in ~30s."
} else {
  Write-Host "Re-run with -Push to publish URL to Vercel."
}

try {
  while (-not $godotProc.HasExited -and -not $gwProc.HasExited -and -not $cfProc.HasExited) {
    Start-Sleep -Seconds 5
  }
} finally {
  Write-Host "Shutting down live stack..."
  foreach ($p in @($cfProc, $gwProc, $godotProc)) {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  }
}
