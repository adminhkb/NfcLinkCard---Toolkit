param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releasePath = Join-Path $projectRoot 'build\windows\x64\runner\Release'

if (-not $SkipBuild) {
    $flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
    if (-not $flutter) {
        $flutter = Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
    }
    if (-not (Test-Path -LiteralPath $flutter)) {
        throw 'Flutter introuvable. Ajoutez flutter au PATH ou installez-le dans ~/develop/flutter.'
    }
    # La liaison ERP est fournie à la compilation : sans ce fichier, l'application ne peut pas se connecter.
    $erpConfig = Join-Path $projectRoot 'config\erp.json'
    if (-not (Test-Path -LiteralPath $erpConfig)) {
        throw "Configuration ERP introuvable : $erpConfig. Créez-la à partir de config\erp.example.json."
    }
    Push-Location $projectRoot
    try {
        & $flutter build windows --release --dart-define-from-file=config/erp.json
        if ($LASTEXITCODE -ne 0) {
            throw "La compilation Windows a échoué (code $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }
}

$exePath = Join-Path $releasePath 'nlc_toolkit.exe'
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Application Windows introuvable : $exePath"
}
if (-not (Test-Path -LiteralPath (Join-Path $releasePath 'data'))) {
    throw 'Le dossier de données Flutter est absent du paquet Windows.'
}

$distPath = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
$bundleName = 'NLC-Toolkit-Windows-x64-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$bundlePath = Join-Path $distPath $bundleName
New-Item -ItemType Directory -Path $bundlePath | Out-Null
Copy-Item -Path (Join-Path $releasePath '*') -Destination $bundlePath -Recurse -Force
$licensePath = Join-Path $projectRoot 'LICENSE'
if (Test-Path -LiteralPath $licensePath) {
    Copy-Item -LiteralPath $licensePath -Destination (Join-Path $bundlePath 'LICENSE')
}

# Flutter requires these Visual C++ runtime files beside the executable on
# machines that do not already have the redistributable installed.
foreach ($runtimeDll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $destination = Join-Path $bundlePath $runtimeDll
    if (-not (Test-Path -LiteralPath $destination)) {
        $source = Join-Path $env:WINDIR "System32\$runtimeDll"
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Runtime Visual C++ introuvable : $source"
        }
        Copy-Item -LiteralPath $source -Destination $destination
    }
}

@'
NLC Toolkit pour Windows (64 bits)

1. Décompressez le dossier entier.
2. Lancez nlc_toolkit.exe dans ce dossier.
3. Connectez-vous avec votre compte ERP (un code de sécurité arrive par e-mail).
4. Branchez le ChameleonUltra en USB et choisissez-le dans Connexion.
   Si la détection automatique ne le trouve pas, utilisez Connexion manuelle
   et sélectionnez son port COM.

Bluetooth : activez-le dans Réglages > Connexion, après avoir appairé le
ChameleonUltra dans les réglages Bluetooth de Windows (un seul mode à la fois).

Gardez les DLL et le dossier data à côté de l'exécutable.
'@ | Set-Content -LiteralPath (Join-Path $bundlePath 'LISEZ-MOI-Windows.txt') -Encoding UTF8

$archivePath = Join-Path $distPath "$bundleName.zip"
Compress-Archive -LiteralPath $bundlePath -DestinationPath $archivePath
Write-Output $archivePath
