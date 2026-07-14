<#
.SYNOPSIS
    Un seul fichier, aucun repo/zip a extraire, aucun build : active
    CloudRedirect (sauvegardes OneDrive) sur une installation OpenSteamTool
    deja en place.

.DESCRIPTION
    Suppose que OpenSteamTool tourne deja dans Steam (DLL deja en place).
    Ce script fait seulement 3 choses :
      1. Telecharge la derniere release publique de CloudRedirect.exe et en
         extrait cloud_redirect.dll (ressource embarquee dans l'exe), sans
         jamais lancer son interface graphique. Le copie dans Steam.
      2. Active "[cloud] enabled = true" dans ton opensteamtool.toml existant
         (le modifie sans l'ecraser ; en cree un minimal s'il n'existe pas).
      3. Si -ConnectOneDrive est passe : ouvre ton navigateur sur la vraie
         page de connexion Microsoft (login reel, une fois), recupere le
         token et l'enregistre chiffre (DPAPI) exactement ou cloud_redirect.dll
         l'attend.

.PARAMETER SteamPath
    Dossier racine Steam. Auto-detecte via le registre si omis.

.PARAMETER ConnectOneDrive
    Lance la connexion OneDrive decrite ci-dessus.

.EXAMPLE
    .\setup_cloud.ps1 -ConnectOneDrive
#>

[CmdletBinding()]
param(
    [string]$SteamPath,
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

if (-not $SteamPath) {
    $SteamPath = Get-SteamInstallPath
    if (-not $SteamPath) {
        throw "Steam introuvable automatiquement. Relance avec -SteamPath 'C:\...\Steam'."
    }
}
$SteamPath = $SteamPath.TrimEnd('\')
Write-Host "[INFO] Steam: $SteamPath"
if (-not (Test-Path $SteamPath)) { throw "'$SteamPath' n'existe pas." }

# ---------------------------------------------------------------------------
# 1. cloud_redirect.dll : telecharge la derniere release CloudRedirect et
# extrait la ressource embarquee "cloud_redirect.dll" (voir
# ui/Services/EmbeddedDll.cs dans le repo CloudRedirect), sans lancer le GUI.
# ---------------------------------------------------------------------------
Write-Host "[INFO] Recuperation de cloud_redirect.dll..."
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest' `
    -Headers @{ 'User-Agent' = 'OpenSteamTool-setup-script' }
$asset = $release.assets | Where-Object { $_.name -like '*.exe' } | Select-Object -First 1
if (-not $asset) { throw "Aucun .exe trouve dans la derniere release CloudRedirect." }

$tmpExe = Join-Path $env:TEMP $asset.name
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpExe
Write-Host "[OK] Telecharge: $($asset.name)"

$destDll = Join-Path $SteamPath 'cloud_redirect.dll'
try {
    $asm = [System.Reflection.Assembly]::LoadFrom($tmpExe)
    $stream = $asm.GetManifestResourceStream('cloud_redirect.dll')
    if (-not $stream) { throw "Ressource 'cloud_redirect.dll' introuvable dans $($asset.name)." }
    $ms = New-Object System.IO.MemoryStream
    $stream.CopyTo($ms)
    [System.IO.File]::WriteAllBytes($destDll, $ms.ToArray())
    Write-Host "[OK] cloud_redirect.dll -> $destDll"
} catch {
    throw "Extraction de cloud_redirect.dll echouee ($_). Telecharge $($asset.browser_download_url) toi-meme et lance-le une fois (Setup -> Run All Patches) a la place."
} finally {
    if ($stream) { $stream.Dispose() }
}

# ---------------------------------------------------------------------------
# 2. opensteamtool.toml : active [cloud] enabled = true sans ecraser le reste.
# ---------------------------------------------------------------------------
$tomlPath = Join-Path $SteamPath 'opensteamtool.toml'
if (Test-Path $tomlPath) {
    $toml = Get-Content -Path $tomlPath -Raw
    if ($toml -match '(?ms)\[cloud\].*?^\s*enabled\s*=\s*false') {
        $toml = [regex]::Replace($toml, '(?ms)(\[cloud\].*?^\s*enabled\s*=\s*)false', '${1}true')
        Write-Host "[OK] [cloud] enabled = false -> true dans $tomlPath"
    } elseif ($toml -notmatch '(?m)^\[cloud\]') {
        $toml += "`r`n[cloud]`r`nenabled = true`r`n"
        Write-Host "[OK] Section [cloud] ajoutee dans $tomlPath"
    } else {
        Write-Host "[INFO] [cloud] deja active dans $tomlPath, rien a changer."
    }
    Set-Content -Path $tomlPath -Value $toml -Encoding UTF8
} else {
    Set-Content -Path $tomlPath -Value "[cloud]`r`nenabled = true`r`n" -Encoding UTF8
    Write-Host "[OK] $tomlPath cree (le reste utilise les valeurs par defaut d'OpenSteamTool)"
}

# ---------------------------------------------------------------------------
# 3. Connexion OneDrive (optionnel) - meme flux OAuth que le companion app
# CloudRedirect (ui/Services/OAuthService.cs) : vrai login Microsoft,
# chiffrement DPAPI CurrentUser identique, memes emplacements de fichiers.
# ---------------------------------------------------------------------------
if ($ConnectOneDrive) {
    Add-Type -AssemblyName System.Security

    $clientId     = 'b15665d9-eda6-4092-8539-0eec376afd59'   # rclone's public installed-app client id (same one CloudRedirect ships)
    $clientSecret = 'qtyfaBBYA403=unZUP40~_#'                 # public "installed app" value shipped in CloudRedirect's own open-source repo
    $scope        = 'Files.ReadWrite offline_access'
    $authUrl      = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize'
    $tokenUrl     = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
    $port         = 53682
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
    try { $listener.Start() } catch { throw "Port 53682 deja utilise par une autre appli ? $_" }

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
            $recvCode  = $q['code']; $recvState = $q['state']; $recvError = $q['error']
            if (-not $recvCode -and -not $recvError -and -not $recvState) {
                $ctx.Response.StatusCode = 204; $ctx.Response.Close(); continue
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
        $listener.Stop(); $listener.Close()
    }
    if (-not $code) { throw "Pas de code recu (annule ou timeout)." }

    Write-Host "[OK] Code recu, echange contre les tokens..."
    $tokenBody = @{
        code = $code; client_id = $clientId; client_secret = $clientSecret
        redirect_uri = $redirectUri; grant_type = 'authorization_code'
        scope = $scope; code_verifier = $codeVerifier
    }
    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    if (-not $tokenResp.refresh_token) { throw "Pas de refresh_token recu - reessaie." }

    $expiresAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + [int64]$tokenResp.expires_in
    $tokenJson = [ordered]@{
        access_token = $tokenResp.access_token; refresh_token = $tokenResp.refresh_token; expires_at = $expiresAt
    } | ConvertTo-Json

    $configDir = Join-Path $env:APPDATA 'CloudRedirect'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $tokenPath = Join-Path $configDir 'onedrive_tokens.json'

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($tokenJson)
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $plainBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    [System.IO.File]::WriteAllBytes($tokenPath, $protectedBytes)
    Write-Host "[OK] Token chiffre -> $tokenPath"

    $configPath = Join-Path $configDir 'config.json'
    $config = [ordered]@{ provider = 'onedrive'; token_path = $tokenPath } | ConvertTo-Json
    Set-Content -Path $configPath -Value $config -Encoding UTF8
    Write-Host "[OK] Config CloudRedirect -> $configPath"
}

Write-Host "[DONE] Termine. Relance Steam."
if (-not $ConnectOneDrive) {
    Write-Host "[NEXT] Relance ce script avec -ConnectOneDrive pour te connecter a OneDrive."
}
