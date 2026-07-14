<#
.SYNOPSIS
    Deploie OpenSteamTool (+ CloudRedirect en option) sur ce PC en une seule
    commande : installe les outils de build manquants si besoin, compile,
    recupere cloud_redirect.dll, configure, et connecte OneDrive.

.DESCRIPTION
    - Detecte (ou prend en parametre) le dossier d'installation Steam.
    - Si build\<Config>\OpenSteamTool.dll n'existe pas encore :
        - Verifie la presence d'un compilateur C++ (Visual Studio/Build Tools)
          et de CMake ; les installe via winget si absents (Microsoft.
          VisualStudio.2022.BuildTools + workload C++, et Kitware.CMake).
        - Lance cmake configure + build (equivalent de build.bat).
      Ceci est la seule etape qui prend du temps et un peu de bande passante
      (premiere fois seulement) : compiler du C++ necessite un vrai
      compilateur, il n'existe pas de binaire OpenSteamTool precompile
      publie pour ce repo.
    - Copie OpenSteamTool.dll, dwmapi.dll, xinput1_4.dll vers Steam.
    - Si -CloudRedirectDll n'est pas fourni : telecharge automatiquement la
      derniere release publique de CloudRedirect.exe
      (github.com/Selectively11/CloudRedirect), puis en extrait
      cloud_redirect.dll (ressource embarquee dans l'exe, cf.
      ui/Services/EmbeddedDll.cs du repo CloudRedirect) sans jamais lancer
      l'interface graphique. Sinon utilise le chemin fourni.
    - Genere opensteamtool.toml a partir d'un template + de ta liste d'AppId.
    - Copie tes scripts Lua vers <Steam>\config\lua.
    - Si -ConnectOneDrive est passe : lance le flux de connexion OneDrive
      (meme echange OAuth que le companion app CloudRedirect, reimplemente
      ici en PowerShell - voir plus bas). Ouvre ton navigateur sur la vraie
      page de connexion Microsoft, attend que tu te connectes, enregistre le
      token chiffre (DPAPI) exactement ou cloud_redirect.dll l'attend.

    CE QUI RESTE, PAR NATURE, IMPOSSIBLE A AUTOMATISER :
    - La toute premiere compilation demande de telecharger un compilateur
      (plusieurs Go) si tu n'en as pas deja un - ce n'est pas ce script qui
      choisit ça, c'est juste ce qu'il faut pour compiler du C++. Une fois
      fait, les executions suivantes sautent cette etape (le DLL existe deja).
    - La connexion OneDrive elle-meme reste un vrai login Microsoft dans le
      navigateur, avec TON compte, refait une fois par PC (le token est
      chiffre en DPAPI DataProtectionScope.CurrentUser, lie a ce compte
      Windows sur cette machine precise - le copier ailleurs echoue au
      dechiffrement, voir src/platform/win/dpapi_util.h du repo CloudRedirect).

.PARAMETER SteamPath
    Dossier racine Steam. Auto-detecte via le registre si omis.

.PARAMETER BuildConfig
    Release ou Debug.

.PARAMETER RepoRoot
    Racine des sources OpenSteamTool (contient src\, opensteamtool.example.toml).

.PARAMETER LuaSourceDir
    Dossier local contenant tes .lua a deployer (addappid, setStat, etc.).

.PARAMETER CloudRedirectDll
    Chemin vers cloud_redirect.dll deja obtenu (optionnel). Si omis et que
    -ConnectOneDrive (ou -EnableCloud) est demande, le script le telecharge
    et l'extrait lui-meme depuis la derniere release CloudRedirect.

.PARAMETER EnableCloud
    Active [cloud] et recupere cloud_redirect.dll meme sans -ConnectOneDrive
    (utile si tu veux juste deployer le DLL et te connecter plus tard).

.PARAMETER ConnectOneDrive
    Lance le flux de connexion OneDrive decrit ci-dessus (implique -EnableCloud).

.EXAMPLE
    .\deploy_local.ps1 -RepoRoot C:\dev\OpenSteamTool -LuaSourceDir C:\dev\my-lua -ConnectOneDrive
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
    [switch]$EnableCloud,
    [switch]$ConnectOneDrive
)

$ErrorActionPreference = 'Stop'
if ($ConnectOneDrive) { $EnableCloud = $true }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
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

function Test-BuildToolsPresent {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { return $false }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return [bool]$vsInstall
}

function Install-BuildTools {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget introuvable. Installe manuellement CMake et 'Desktop development with C++' (Visual Studio Build Tools 2022), puis relance."
    }
    Write-Host "[INFO] Compilateur/CMake absents - installation via winget (peut prendre plusieurs minutes, plusieurs Go)..."
    winget install --id Kitware.CMake -e --silent --accept-package-agreements --accept-source-agreements
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent --accept-package-agreements --accept-source-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    # Refresh PATH for this session (winget/VS installers update the machine PATH, not this process's).
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    if (-not (Test-BuildToolsPresent)) {
        throw "L'installation des outils de build a echoue ou necessite un redemarrage du terminal/PC. Relance ce script dans un nouveau terminal apres l'installation."
    }
    Write-Host "[OK] Outils de build installes."
}

function Build-OpenSteamTool([string]$RepoRoot, [string]$Config) {
    if (-not (Test-BuildToolsPresent)) {
        Install-BuildTools
    }
    Write-Host "[INFO] Configuration CMake..."
    cmake -S (Join-Path $RepoRoot 'src') -B (Join-Path $RepoRoot 'build') -G "Visual Studio 17 2022" -A x64
    if ($LASTEXITCODE -ne 0) { throw "cmake (configure) a echoue." }
    Write-Host "[INFO] Compilation ($Config)..."
    cmake --build (Join-Path $RepoRoot 'build') --config $Config
    if ($LASTEXITCODE -ne 0) { throw "cmake --build a echoue." }
    Write-Host "[OK] Build termine."
}

# ---------------------------------------------------------------------------
# Recupere cloud_redirect.dll depuis la derniere release publique de
# CloudRedirect, en l'extrayant de l'exe (ressource embarquee), sans lancer
# l'interface graphique. Cf. ui/Services/EmbeddedDll.cs dans ce repo :
# la ressource s'appelle "cloud_redirect.dll".
# ---------------------------------------------------------------------------
function Get-CloudRedirectDllFromRelease([string]$DestPath) {
    Write-Host "[INFO] Recuperation de cloud_redirect.dll depuis la derniere release CloudRedirect..."
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest' `
        -Headers @{ 'User-Agent' = 'OpenSteamTool-deploy-script' }
    $asset = $release.assets | Where-Object { $_.name -like '*.exe' } | Select-Object -First 1
    if (-not $asset) { throw "Aucun .exe trouve dans la derniere release CloudRedirect." }

    $tmpExe = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpExe
    Write-Host "[OK] Telecharge: $($asset.name)"

    try {
        $asm = [System.Reflection.Assembly]::LoadFrom($tmpExe)
        $stream = $asm.GetManifestResourceStream('cloud_redirect.dll')
        if (-not $stream) {
            throw "Ressource 'cloud_redirect.dll' introuvable dans $($asset.name) (nom de ressource peut avoir change en amont)."
        }
        $ms = New-Object System.IO.MemoryStream
        $stream.CopyTo($ms)
        [System.IO.File]::WriteAllBytes($DestPath, $ms.ToArray())
        Write-Host "[OK] cloud_redirect.dll extrait -> $DestPath"
    } catch {
        throw "Extraction automatique de cloud_redirect.dll echouee ($_). Solution de secours: telecharge $($asset.browser_download_url) toi-meme, lance-le, fais Setup -> Run All Patches, puis relance ce script avec -CloudRedirectDll pointant vers le fichier qu'il a deploye."
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# OneDrive OAuth flow (authorization code + PKCE), matching
# CloudRedirect/ui/Services/OAuthService.cs exactly: same client id, same
# scope, same fixed loopback port/redirect URI, same token JSON shape, same
# DPAPI-CurrentUser encryption at rest, same file locations. This performs a
# REAL sign-in against login.microsoftonline.com with YOUR account; nothing
# here bypasses or weakens that.
# ---------------------------------------------------------------------------
function Connect-OneDriveCloudRedirect {
    Add-Type -AssemblyName System.Security

    $clientId     = 'b15665d9-eda6-4092-8539-0eec376afd59'   # rclone's public installed-app client id (same one CloudRedirect ships)
    $clientSecret = 'qtyfaBBYA403=unZUP40~_#'                 # public "installed app" value shipped in CloudRedirect's own open-source repo
    $scope        = 'Files.ReadWrite offline_access'
    $authUrl      = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize'
    $tokenUrl     = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
    $port         = 53682   # fixed: this is the only redirect port registered for this client id
    $redirectUri  = "http://localhost:$port/"

    function New-RandomUrlSafeString([int]$Length) {
        $bytes = New-Object byte[] $Length
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').Replace('=','').Substring(0, $Length)
    }

    function Get-CodeChallenge([string]$Verifier) {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Verifier))
        [Convert]::ToBase64String($hash).Replace('+','-').Replace('/','_').Replace('=','')
    }

    $state         = New-RandomUrlSafeString 32
    $codeVerifier  = New-RandomUrlSafeString 64
    $codeChallenge = Get-CodeChallenge $codeVerifier

    $authQuery = @(
        "client_id=$([uri]::EscapeDataString($clientId))"
        "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
        "response_type=code"
        "scope=$([uri]::EscapeDataString($scope))"
        "prompt=consent"
        "state=$([uri]::EscapeDataString($state))"
        "code_challenge=$([uri]::EscapeDataString($codeChallenge))"
        "code_challenge_method=S256"
    ) -join '&'
    $fullAuthUrl = "$authUrl`?$authQuery"

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($redirectUri)
    try {
        $listener.Start()
    } catch {
        throw "Impossible d'ecouter sur $redirectUri (port 53682 deja utilise par une autre appli ?) : $_"
    }

    Write-Host "[INFO] Ouverture du navigateur pour la connexion OneDrive..."
    Start-Process $fullAuthUrl | Out-Null
    Write-Host "[INFO] Connecte-toi dans la fenetre qui vient de s'ouvrir (5 minutes max)."

    $code = $null
    $deadline = (Get-Date).AddMinutes(5)
    try {
        while ((Get-Date) -lt $deadline) {
            $asyncResult = $listener.BeginGetContext($null, $null)
            if (-not $asyncResult.AsyncWaitHandle.WaitOne(1000)) { continue }
            $ctx = $listener.EndGetContext($asyncResult)
            $q = $ctx.Request.QueryString
            $recvCode  = $q['code']
            $recvState = $q['state']
            $recvError = $q['error']

            if (-not $recvCode -and -not $recvError -and -not $recvState) {
                $ctx.Response.StatusCode = 204
                $ctx.Response.Close()
                continue
            }

            if ($recvState -ne $state) { $recvError = 'state_mismatch'; $recvCode = $null }

            $html = if ($recvCode) {
                '<html><body style="font-family:Segoe UI,sans-serif;text-align:center;padding:60px;background:#1e1e1e;color:#fff"><h1>Connecte !</h1><p>Tu peux fermer cette fenetre.</p></body></html>'
            } else {
                "<html><body style='font-family:Segoe UI,sans-serif;text-align:center;padding:60px;background:#1e1e1e;color:#fff'><h1>Echec</h1><p>Erreur: $recvError</p></body></html>"
            }
            $buf = [System.Text.Encoding]::UTF8.GetBytes($html)
            $ctx.Response.ContentType = 'text/html; charset=utf-8'
            $ctx.Response.ContentLength64 = $buf.Length
            $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
            $ctx.Response.Close()

            $code = $recvCode
            break
        }
    } finally {
        $listener.Stop()
        $listener.Close()
    }

    if (-not $code) {
        throw "Pas de code d'autorisation recu (annule ou timeout de 5 minutes)."
    }

    Write-Host "[OK] Code d'autorisation recu, echange contre les tokens..."

    $tokenBody = @{
        code          = $code
        client_id     = $clientId
        client_secret = $clientSecret
        redirect_uri  = $redirectUri
        grant_type    = 'authorization_code'
        scope         = $scope
        code_verifier = $codeVerifier
    }
    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'

    if (-not $tokenResp.refresh_token) {
        throw "Pas de refresh_token dans la reponse - reessaie (ou revoque l'acces existant sur account.microsoft.com et reessaie)."
    }

    $expiresAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + [int64]$tokenResp.expires_in
    $tokenJson = [ordered]@{
        access_token  = $tokenResp.access_token
        refresh_token = $tokenResp.refresh_token
        expires_at    = $expiresAt
    } | ConvertTo-Json

    $configDir = Join-Path $env:APPDATA 'CloudRedirect'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $tokenPath = Join-Path $configDir 'onedrive_tokens.json'

    # DPAPI-encrypt, CurrentUser scope - same as TokenFile.WriteJson in
    # OAuthService.cs, and same as DpapiUtil::Encrypt in dpapi_util.h.
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($tokenJson)
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $plainBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    [System.IO.File]::WriteAllBytes($tokenPath, $protectedBytes)
    Write-Host "[OK] Token chiffre enregistre -> $tokenPath"

    $configPath = Join-Path $configDir 'config.json'
    $config = [ordered]@{
        provider   = 'onedrive'
        token_path = $tokenPath
    } | ConvertTo-Json
    Set-Content -Path $configPath -Value $config -Encoding UTF8
    Write-Host "[OK] Config CloudRedirect enregistree -> $configPath"
}

# ---------------------------------------------------------------------------
# 0. Steam path
# ---------------------------------------------------------------------------
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
if (-not (Test-Path (Join-Path $RepoRoot 'src'))) {
    throw "'$RepoRoot' ne ressemble pas aux sources OpenSteamTool (pas de dossier 'src'). Extrais d'abord le zip des sources ici."
}

# ---------------------------------------------------------------------------
# 1. Build si necessaire, puis copier les DLL compilees
# ---------------------------------------------------------------------------
$buildDir = Join-Path $RepoRoot "build\$BuildConfig"
$dlls = @('OpenSteamTool.dll', 'dwmapi.dll', 'xinput1_4.dll')
$needsBuild = $dlls | ForEach-Object { -not (Test-Path (Join-Path $buildDir $_)) } | Where-Object { $_ } | Select-Object -First 1

if ($needsBuild) {
    Build-OpenSteamTool -RepoRoot $RepoRoot -Config $BuildConfig
}

foreach ($dll in $dlls) {
    $src = Join-Path $buildDir $dll
    if (-not (Test-Path $src)) {
        throw "Introuvable meme apres build: $src"
    }
    Copy-Item -Path $src -Destination (Join-Path $SteamPath $dll) -Force
    Write-Host "[OK] Copie $dll -> $SteamPath"
}

# ---------------------------------------------------------------------------
# 2. CloudRedirect (optionnel)
# ---------------------------------------------------------------------------
$cloudEnabled = $false
if ($EnableCloud) {
    $destDll = Join-Path $SteamPath 'cloud_redirect.dll'
    if ($CloudRedirectDll) {
        if (-not (Test-Path $CloudRedirectDll)) { throw "cloud_redirect.dll introuvable: $CloudRedirectDll" }
        Copy-Item -Path $CloudRedirectDll -Destination $destDll -Force
        Write-Host "[OK] Copie cloud_redirect.dll -> $SteamPath"
    } else {
        Get-CloudRedirectDllFromRelease -DestPath $destDll
    }
    $cloudEnabled = $true
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

# ---------------------------------------------------------------------------
# 5. Connexion OneDrive (optionnel)
# ---------------------------------------------------------------------------
if ($ConnectOneDrive) {
    Connect-OneDriveCloudRedirect
}

Write-Host "[DONE] Deploiement termine sur ce PC."
if ($cloudEnabled -and -not $ConnectOneDrive) {
    Write-Host "[NEXT] Relance avec -ConnectOneDrive pour te connecter a OneDrive (login Microsoft reel, une fois)."
}
