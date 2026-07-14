<#
.SYNOPSIS
    Deploie OpenSteamTool (+ CloudRedirect en option) sur ce PC, pour un usage
    personnel.

.DESCRIPTION
    - Detecte (ou prend en parametre) le dossier d'installation Steam.
    - Copie OpenSteamTool.dll, dwmapi.dll, xinput1_4.dll depuis build/<Config>.
    - Copie cloud_redirect.dll si -CloudRedirectDll est fourni.
    - Genere opensteamtool.toml a partir d'un template + de ta liste d'AppId.
    - Copie tes scripts Lua vers <Steam>\config\lua.
    - Si -ConnectOneDrive est passe : lance directement le flux de connexion
      OneDrive (meme echange OAuth que le companion app CloudRedirect, code
      reimplemente ici en PowerShell a partir de
      ui/Services/OAuthService.cs du repo CloudRedirect - pas besoin de
      builder/telecharger CloudRedirect.exe, et aucun appel reseau vers
      GitHub n'est fait par ce script). Ca ouvre ton navigateur sur la vraie
      page de connexion Microsoft, attend que tu te connectes, recupere le
      token et l'enregistre chiffre (DPAPI) exactement au meme endroit et
      dans le meme format que l'appli officielle, pour que cloud_redirect.dll
      le lise sans rien reconfigurer.

    NOTE IMPORTANTE : cette connexion reste, par construction, une action
    manuelle A FAIRE UNE FOIS PAR PC (vrai login Microsoft dans le
    navigateur, avec TON compte). Le script te l'ouvre et automatise tout le
    reste autour, mais ne peut pas "la faire a ta place" ni la transferer
    vers un autre PC : le token est ensuite chiffre avec la DPAPI Windows en
    DataProtectionScope.CurrentUser, liee a ton compte Windows sur CETTE
    machine precise (voir src/platform/win/dpapi_util.h dans le repo
    CloudRedirect) - le copier ailleurs echouerait au dechiffrement. Sur un
    autre PC, relance ce script avec -ConnectOneDrive pour refaire la
    connexion la-bas aussi (30 secondes, un login).

.PARAMETER SteamPath
    Dossier racine Steam. Auto-detecte via le registre si omis.

.PARAMETER BuildConfig
    Release ou Debug (doit correspondre a ce que build.bat a compile).

.PARAMETER RepoRoot
    Racine du repo OpenSteamTool (contient build\, opensteamtool.example.toml).

.PARAMETER LuaSourceDir
    Dossier local contenant tes .lua a deployer (addappid, setStat, etc.).

.PARAMETER CloudRedirectDll
    Chemin vers cloud_redirect.dll deja telecharge (optionnel). Place le DLL
    et active [cloud] dans le toml.

.PARAMETER ConnectOneDrive
    Lance le flux de connexion OneDrive decrit ci-dessus.

.EXAMPLE
    .\deploy_local.ps1 -RepoRoot C:\dev\OpenSteamTool -LuaSourceDir C:\dev\my-lua `
        -CloudRedirectDll C:\Downloads\cloud_redirect.dll -ConnectOneDrive
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
    [switch]$ConnectOneDrive
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
    if (-not $cloudEnabled) {
        Write-Warning "-ConnectOneDrive demande mais -CloudRedirectDll n'a pas ete fourni: cloud_redirect.dll ne sera pas charge par OpenSteamTool tant qu'il n'est pas en place."
    }
    Connect-OneDriveCloudRedirect
}

Write-Host "[DONE] Deploiement termine sur ce PC."
if ($cloudEnabled -and -not $ConnectOneDrive) {
    Write-Host "[NEXT] Relance avec -ConnectOneDrive pour te connecter a OneDrive (login Microsoft reel, une fois)."
}
