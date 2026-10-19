# AppFactoryWorker — bootstrap noveho Windows stroje.
#
# Spusteni v PowerShellu (bez admina; UAC vyskoci jen u instalatoru):
#   irm https://raw.githubusercontent.com/janindra/appfactoryworker-releases/main/setup.ps1 | iex
#
# Zdroj pravdy je setup-windows.ps1 v repu appfactoryworker; kopii v release
# repu synchronizuje CI pri kazdem tagu. Skript je idempotentni — co uz na
# stroji je, preskoci; da se poustet opakovane.
#
# Zamerne bez diakritiky: text tece pres irm | iex a spatne urcene kodovani
# by rozbilo retezce.

$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }

# winget/instalator meni Machine+User PATH — do bezici session se to samo nepropise
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Ensure-UserPath($dir) {
  $user = [string][Environment]::GetEnvironmentVariable('Path', 'User')
  if (($user -split ';') -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', ($user.TrimEnd(';') + ';' + $dir), 'User')
  }
  if (($env:Path -split ';') -notcontains $dir) { $env:Path += ";$dir" }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw 'winget neni k dispozici — nainstaluj "App Installer" z Microsoft Store a spust skript znovu.'
}

Step 'Zakladni nastroje: git, Node.js LTS, GitHub CLI'
foreach ($t in @(
  @{ cmd = 'git';  id = 'Git.Git' },
  @{ cmd = 'node'; id = 'OpenJS.NodeJS.LTS' },
  @{ cmd = 'gh';   id = 'GitHub.cli' }
)) {
  if (Get-Command $t.cmd -ErrorAction SilentlyContinue) { Ok "$($t.cmd): uz je"; continue }
  winget install -e --id $t.id --accept-source-agreements --accept-package-agreements
  Refresh-Path
  if (-not (Get-Command $t.cmd -ErrorAction SilentlyContinue)) {
    throw "$($t.cmd) po instalaci nejde spustit — otevri nove okno PowerShellu a spust skript znovu"
  }
  Ok "$($t.cmd): nainstalovano"
}

Step 'Execution policy — npm/npx/claude z npm maji .ps1 obalku'
if ((Get-ExecutionPolicy -Scope CurrentUser) -in @('Undefined', 'Restricted')) {
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  Ok 'nastaveno RemoteSigned (CurrentUser)'
} else {
  Ok 'skripty uz jsou povolene'
}

Step 'yarn'
if (Get-Command yarn -ErrorAction SilentlyContinue) { Ok 'uz je' }
else {
  # corepack enable zapisuje do Program Files a chtel by admina — npm ne
  npm install -g yarn
  Refresh-Path
  Ok 'nainstalovan pres npm'
}

Step 'Railway CLI'
if (Get-Command railway -ErrorAction SilentlyContinue) { Ok 'uz je' }
else {
  npm install -g '@railway/cli'
  Refresh-Path
  if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
    throw 'railway po instalaci nejde spustit — otevri nove okno PowerShellu a spust skript znovu'
  }
  Ok 'nainstalovano pres npm'
}

Step 'Claude Code CLI'
$claudeBinDir = Join-Path $env:USERPROFILE '.local\bin'
if (-not (Test-Path (Join-Path $claudeBinDir 'claude.exe'))) {
  irm https://claude.ai/install.ps1 | iex
}
# instalator PATH nastavuje, ale ne vzdy se ujme — pojistka pro session i trvale
Ensure-UserPath $claudeBinDir
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  throw 'claude po instalaci nejde spustit — otevri nove okno PowerShellu a spust skript znovu'
}
Ok "claude $(claude --version)"

Step 'Prihlaseni (interaktivni — jedina cast, kterou skript neudela sam)'
$prevEap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
gh auth status *> $null
$ghOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
if ($ghOk) { Ok 'GitHub: prihlaseno' } else { gh auth login }

$prevEap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
railway whoami *> $null
$rwOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
if ($rwOk) { Ok 'Railway: prihlaseno' }
else {
  Write-Host '   Railway: prihlas se uctem ownera (workspace "Jan Indra''s Projects").'
  railway login
}

Write-Host '   Claude: otevre se claude — prihlas se prikazem /login a potom ukonci pres /exit.'
Read-Host '   Enter pro pokracovani'
claude

Step 'Playwright browsery (vetsi stahovani, chvili to trva)'
npx playwright install

Step 'Integrace Claude Code — Playwright MCP a Railway plugin'
# opakovane spusteni muze hlasit "already exists" — to neni chyba
claude mcp add playwright -s user -- npx '@playwright/mcp@latest' --browser chrome --viewport-size '1440,900'
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install 'railway@claude-plugins-official'
# Zeabur skoncil — stary plugin pryc, at ho worker nenabizi
# (stderr presmerovany pri EAP=Stop by v PS 5.1 shodil skript, kdyz plugin neni)
$prevEap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
claude plugin uninstall 'zeabur@zeabur' *> $null
$ErrorActionPreference = $prevEap

Step 'AppFactoryWorker — stazeni a spusteni instalatoru'
$rel = irm https://api.github.com/repos/janindra/appfactoryworker-releases/releases/latest
$asset = $rel.assets | Where-Object { $_.name -match 'Setup.*\.exe$' } | Select-Object -First 1
if (-not $asset) { throw "v release $($rel.tag_name) neni zadny Setup exe" }
$dst = Join-Path $env:TEMP $asset.name
Write-Host "   stahuji $($asset.name) ($([math]::Round($asset.size / 1MB)) MB)"
iwr $asset.browser_download_url -OutFile $dst
Start-Process $dst

Write-Host @'

== Hotovo. Rucne zbyva:
   1. dokoncit instalator AppFactoryWorker (SmartScreen: Dalsi informace -> Presto spustit)
   2. ve Factory (https://appfactory.indracorp.cz) Workers -> + PRIPOJIT WORKER
      a vydany token vlozit do appky (zobrazi se jen jednou)
'@
