# Patch Godot web export HTML: Solana bridge + loading-screen wager ad.
# Run after every Web export (export overwrites index.html).

param(
  [string]$HtmlPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
if ($HtmlPath -eq "") {
  $HtmlPath = Join-Path $root "web\index.html"
}
if (-not (Test-Path $HtmlPath)) {
  Write-Host "Missing $HtmlPath"
  exit 1
}

$html = [System.IO.File]::ReadAllText($HtmlPath)

if ($html -notmatch "solana_bridge\.js") {
  $html = $html -replace "</head>", "`t<script src=`"solana_bridge.js`"></script>`r`n`t</head>"
}

$bootCss = @"
#tw-boot-ad {
	position: absolute;
	left: 0;
	right: 0;
	bottom: 14%;
	z-index: 2;
	text-align: center;
	pointer-events: none;
	font-family: Georgia, 'Times New Roman', serif;
	text-shadow: 0 2px 10px rgba(0,0,0,0.85);
}
#tw-boot-ad .tw-line {
	color: #f2c85a;
	font-size: clamp(14px, 2.6vw, 22px);
	letter-spacing: 0.12em;
	font-weight: 700;
	margin: 0 1rem 0.35rem;
}
#tw-boot-ad .tw-sub {
	color: #d8e0c8;
	font-size: clamp(12px, 2vw, 16px);
	letter-spacing: 0.04em;
	margin: 0 1.25rem;
	font-family: 'Segoe UI', Tahoma, sans-serif;
}
"@

if ($html -notmatch "#tw-boot-ad") {
  $html = $html -replace "</style>", "$bootCss`r`n`t`t</style>"
}

$bootHtml = @"
			<div id="tw-boot-ad">
				<div class="tw-line">ONLINE PVP  |  WAGER SOL</div>
				<div class="tw-sub">Stake on Solana - winner takes the pot</div>
			</div>
"@

if ($html -notmatch 'id="tw-boot-ad"') {
  $html = $html -replace '(<div id="status-notice"></div>)', "`$1`r`n$bootHtml"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($HtmlPath, $html, $utf8)
Write-Host "Patched web HTML boot ad + solana bridge."
