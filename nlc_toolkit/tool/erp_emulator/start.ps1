# Banc d'essai de la liaison ERP : émulateurs Firebase (Auth, Firestore, Functions) lancés avec les
# vraies règles de sécurité de l'ERP et ses fonctions de double authentification.
#
# Tout tourne en local sous le projet fictif « demo-nlc » : rien ne lit ni n'écrit la production.
#
#   powershell -ExecutionPolicy Bypass -File tool/erp_emulator/start.ps1 -ErpRepo C:\chemin\vers\depot-erp
#
# Puis, dans un autre terminal :
#   $env:NLC_ERP_EMULATOR = '1'; flutter test test/emulator
#
# Ctrl+C arrête les émulateurs. Le dossier de travail peut ensuite être supprimé avec -Clean.
param(
    [string]$ErpRepo,
    [string]$WorkDir = (Join-Path $env:TEMP 'nlc-erp-emulator'),
    [switch]$PrepareOnly,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$functionsDir = Join-Path $WorkDir 'functions'
$modulesLink = Join-Path $functionsDir 'node_modules'

function Remove-ModulesLink {
    # node_modules est une jonction vers celui de l'ERP : la retirer sans jamais suivre le lien.
    if (Test-Path -LiteralPath $modulesLink) { cmd /c rmdir "$modulesLink" | Out-Null }
}

if ($Clean) {
    Remove-ModulesLink
    if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
    Write-Output "Banc d'essai supprimé : $WorkDir"
    return
}

if (-not $ErpRepo) { throw "Indiquez le dépôt de l'ERP : -ErpRepo C:\chemin\vers\depot-erp" }
$erpFunctions = Join-Path $ErpRepo 'functions'
foreach ($required in @('firestore.rules', 'storage.rules', 'functions\lib\index.js', 'functions\node_modules', 'functions\package.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ErpRepo $required))) {
        throw "Introuvable dans le dépôt de l'ERP : $required"
    }
}

Remove-ModulesLink
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $functionsDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $ErpRepo 'firestore.rules') -Destination (Join-Path $WorkDir 'firestore.rules')
Copy-Item -LiteralPath (Join-Path $ErpRepo 'storage.rules') -Destination (Join-Path $WorkDir 'storage.rules')
Copy-Item -LiteralPath (Join-Path $erpFunctions 'lib') -Destination (Join-Path $functionsDir 'erp-lib') -Recurse
cmd /c mklink /J "$modulesLink" "$(Join-Path $erpFunctions 'node_modules')" | Out-Null

# Seules les fonctions de la double authentification sont exposées : aucun déclencheur ni tâche
# planifiée de l'ERP ne peut s'exécuter ici.
@'
const erp = require('./erp-lib/index.js');

for (const name of [
  'sendAdmin2FACode',
  'verifyAdmin2FACode',
  'checkTrustedDevice',
  'listTrustedDevices',
  'revokeTrustedDevices',
]) {
  exports[name] = erp[name];
}
'@ | Set-Content -LiteralPath (Join-Path $functionsDir 'index.js') -Encoding UTF8

$package = Get-Content -LiteralPath (Join-Path $erpFunctions 'package.json') -Raw | ConvertFrom-Json
$package.main = 'index.js'
$package | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $functionsDir 'package.json') -Encoding UTF8

@'
{
  "firestore": { "rules": "firestore.rules" },
  "storage": { "rules": "storage.rules" },
  "functions": [{ "source": "functions", "codebase": "default" }],
  "emulators": {
    "auth": { "port": 19099 },
    "firestore": { "port": 18080 },
    "functions": { "port": 15001 },
    "storage": { "port": 19199 },
    "hub": { "port": 14400 },
    "logging": { "port": 14500 },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
'@ | Set-Content -LiteralPath (Join-Path $WorkDir 'firebase.json') -Encoding UTF8

Write-Output "Banc d'essai prêt : $WorkDir"
if ($PrepareOnly) { return }

Push-Location $WorkDir
try {
    firebase emulators:start --project demo-nlc --only auth,firestore,functions,storage
} finally {
    Pop-Location
}
