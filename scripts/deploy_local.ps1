<#
.SYNOPSIS
    Deploie OpenSteamTool (+ CloudRedirect en option) sur ce PC, pour un usage
    personnel sur plusieurs de tes machines.

.DESCRIPTION
    - Detecte (ou prend en parametre) le dossier d'installation Steam.
    - Copie OpenSteamTool.dll, dwmapi.dll, xinput1_4.dll depuis build/<Config>.
    - Copie cloud_redirect.dll si -CloudRedirectDll est fourni.
    - Copie ton token/config CloudRedirect deja authentifie si -CloudRedirectTokenSrc
      est fourni (evite de te reconnecter a OneDrive sur chaque PC).
    - Genere opensteamtool.toml a partir d'un template + de ta liste d'AppId.
    - Copie tes scripts Lua vers <Steam>\config\lua.

.PARAMETER SteamPath
    Dossier racine Steam. Auto-detecte via le registre si omis.

.PARAMETER BuildConfig
    Release ou Debug (doit correspondre a ce que build.bat a compile).

.PARAMETER RepoRoot
    Racine du repo OpenSteamTool (contient build\, opensteamtool.example.toml).

.PARAMETER LuaSourceDir
    Dossier local contenant tes .lua a deployer (addappid, setStat, etc.).

.PARAMETER CloudRedirectDll
    Chemin vers cloud_redirect.dll deja telecharge (optionnel).

.PARAMETER CloudRedirectTokenSrc
    Dossier contenant le token/config CloudRedirect deja authentifie sur ce
    PC, a copier tel quel sur un nouveau PC (optionnel). VOIR NOTE plus bas :
    le chemin exact depend de CloudRedirect (projet externe, pas verifie ici).

.EXAMPLE
    .\deploy_local.ps1 -RepoRoot C:\dev\OpenSteamTool -LuaSourceDir C:\dev\my-lua `
        -CloudRedirectDll C:\Downloads\cloud_redirect.dll
#>

[CmdletBinding()]
param(
    [string]$SteamPath,
    [ValidateSet('Release','Debug')]
    [string]$BuildConfig = 'Release',
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    [string]$LuaSourceDir,
    [string]$CloudRedirectDll,
    [string]$CloudRedirectTokenSrc
)

$ErrorActionPreference = 'Stop'

function Get-SteamInstallPath {
    $regPaths = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )
    foreach ($p in $regPaths) {
        if (Test-Path $p) {
            $val = (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue).SteamPath
            if (-not $val) { $val = (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue).InstallPath }
            if ($val) { return $val }
        }
    }
    return $null
}

if (-not $SteamPath) {
    $SteamPath = Get-SteamInstallPath
    if (-not $SteamPath) {
        throw "Impossible de detecter le dossier Steam automatiquement. Relance avec -SteamPath 'C:\...\Steam'."
    }
}
$SteamPath = $SteamPath.TrimEnd('\')
Write-Host "[INFO] Steam install path: $SteamPath"

if (-not (Test-Path $SteamPath)) {
    throw "Le dossier Steam '$SteamPath' n'existe pas."
}

# ---------------------------------------------------------------------------
# 1. Copier les DLL compilees
# ---------------------------------------------------------------------------
$buildDir = Join-Path $RepoRoot "build\$BuildConfig"
$dlls = @('OpenSteamTool.dll', 'dwmapi.dll', 'xinput1_4.dll')

foreach ($dll in $dlls) {
    $src = Join-Path $buildDir $dll
    if (-not (Test-Path $src)) {
        throw "Introuvable: $src (as-tu bien lance build.bat avec CONFIGS incluant '$BuildConfig' ?)"
    }
    Copy-Item -Path $src -Destination (Join-Path $SteamPath $dll) -Force
    Write-Host "[OK] Copie $dll -> $SteamPath"
}

# ---------------------------------------------------------------------------
# 2. CloudRedirect (optionnel)
# ---------------------------------------------------------------------------
$cloudEnabled = $false
if ($CloudRedirectDll) {
    if (-not (Test-Path $CloudRedirectDll)) {
        throw "cloud_redirect.dll introuvable: $CloudRedirectDll"
    }
    Copy-Item -Path $CloudRedirectDll -Destination (Join-Path $SteamPath 'cloud_redirect.dll') -Force
    Write-Host "[OK] Copie cloud_redirect.dll -> $SteamPath"
    $cloudEnabled = $true
}

if ($CloudRedirectTokenSrc) {
    # NOTE: chemin de destination a adapter une fois que tu as verifie ou
    # CloudRedirect (projet externe) stocke reellement son token/config sur
    # une machine deja connectee (ex: %APPDATA%\CloudRedirect ou
    # %LOCALAPPDATA%\CloudRedirect). Ceci copie tel quel sans le deviner.
    if (-not (Test-Path $CloudRedirectTokenSrc)) {
        throw "Dossier token CloudRedirect introuvable: $CloudRedirectTokenSrc"
    }
    $tokenDest = Join-Path $env:APPDATA 'CloudRedirect'
    Write-Warning "Destination token CloudRedirect non verifiee (placeholder: $tokenDest). Adapte cette ligne apres avoir confirme le vrai chemin."
    Copy-Item -Path $CloudRedirectTokenSrc -Destination $tokenDest -Recurse -Force
    Write-Host "[OK] Token CloudRedirect copie -> $tokenDest"
}

# ---------------------------------------------------------------------------
# 3. opensteamtool.toml
# ---------------------------------------------------------------------------
$tomlPath = Join-Path $SteamPath 'opensteamtool.toml'
$examplePath = Join-Path $RepoRoot 'opensteamtool.example.toml'

if (-not (Test-Path $examplePath)) {
    throw "Template introuvable: $examplePath"
}

$toml = Get-Content -Path $examplePath -Raw
if ($cloudEnabled) {
    $toml = $toml -replace '(?m)^\s*enabled\s*=\s*false(\s*#.*cloud.*)?$', 'enabled = true'
}
Set-Content -Path $tomlPath -Value $toml -Encoding UTF8
Write-Host "[OK] Genere $tomlPath (cloud enabled: $cloudEnabled)"

# ---------------------------------------------------------------------------
# 4. Scripts Lua
# ---------------------------------------------------------------------------
if ($LuaSourceDir) {
    if (-not (Test-Path $LuaSourceDir)) {
        throw "Dossier Lua source introuvable: $LuaSourceDir"
    }
    $luaDest = Join-Path $SteamPath 'config\lua'
    New-Item -ItemType Directory -Path $luaDest -Force | Out-Null
    Copy-Item -Path (Join-Path $LuaSourceDir '*.lua') -Destination $luaDest -Force
    Write-Host "[OK] Scripts Lua copies -> $luaDest"
}

Write-Host "[DONE] Deploiement termine sur ce PC."
if ($CloudRedirectDll -and -not $CloudRedirectTokenSrc) {
    Write-Host "[NEXT] Lance CloudRedirect.exe (companion app) et connecte-toi a ton compte cloud sur ce PC."
}
