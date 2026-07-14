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

$SteamPath = Get-SteamInstallPath
if (-not $SteamPath) {
    throw "Steam introuvable automatiquement. Modifie la ligne '`$SteamPath = Get-SteamInstallPath' en '`$SteamPath = \"C:\...\Steam\"' en haut du script."
}
$SteamPath = $SteamPath.TrimEnd('\')
Write-Host "[INFO] Steam: $SteamPath"

# ---------------------------------------------------------------------------
# 0. OpenSteamTool : lien direct fourni, telecharge le zip precompile.
# ---------------------------------------------------------------------------
$ostDlls = @('OpenSteamTool.dll', 'dwmapi.dll', 'xinput1_4.dll')
$ostMissing = $ostDlls | Where-Object { -not (Test-Path (Join-Path $SteamPath $_)) }

if ($ostMissing) {
    Write-Host "[INFO] Telechargement d'OpenSteamTool..."
    $ostUrl = 'https://release-assets.githubusercontent.com/github-production-release-asset/1219526865/a9b329ca-f260-497e-a12c-75025624d60c?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-07-14T14%3A10%3A28Z&rscd=attachment%3B+filename%3DOpenSteamTool-1.4.8-Debug.zip&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-07-14T13%3A10%3A25Z&ske=2026-07-14T14%3A10%3A28Z&sks=b&skv=2018-11-09&sig=ZGc7%2FaUN8cMp9aChsaYStwCiZwvsE07cMBMkjs4iTjI%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4NDAzNjczNCwibmJmIjoxNzg0MDM0OTM0LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.XJkj0e6JP6e81zqKCTEa5zmhjsZa-Pznuu9o_rSEOA4&response-content-disposition=attachment%3B%20filename%3DOpenSteamTool-1.4.8-Debug.zip&response-content-type=application%2Foctet-stream'
    $tmpZip = Join-Path $env:TEMP 'OpenSteamTool-1.4.8-Debug.zip'
    Invoke-WebRequest -Uri $ostUrl -OutFile $tmpZip
    Write-Host "[OK] Telecharge."

    $tmpExtract = Join-Path $env:TEMP ("OpenSteamTool-extract-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

    foreach ($dll in $ostDlls) {
        $found = Get-ChildItem -Path $tmpExtract -Filter $dll -Recurse | Select-Object -First 1
        if (-not $found) { throw "$dll introuvable dans le zip apres extraction." }
        Copy-Item -Path $found.FullName -Destination (Join-Path $SteamPath $dll) -Force
        Write-Host "[OK] $dll -> $SteamPath"
    }
    Remove-Item -Path $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[INFO] OpenSteamTool deja present, rien a telecharger."
}

# ---------------------------------------------------------------------------
# 1. cloud_redirect.dll (attache directement en piece jointe de release,
# pas besoin d'exe/extraction).
# ---------------------------------------------------------------------------
Write-Host "[INFO] Telechargement de cloud_redirect.dll..."
$crUrl = 'https://release-assets.githubusercontent.com/github-production-release-asset/1198768370/910e58fa-9ae9-4288-8f80-cef68ff89c8b?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-07-14T16%3A56%3A46Z&rscd=attachment%3B+filename%3Dcloud_redirect.dll&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-07-14T15%3A56%3A46Z&ske=2026-07-14T16%3A56%3A46Z&sks=b&skv=2018-11-09&sig=xWEpeKDZsWxwXskbQ3YQUeYeKDYB0xxaurl2dm2cYNI%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4NDA0NjQzNCwibmJmIjoxNzg0MDQ2MTM0LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.L1-M4k5IX01pwJOcdzbs5MbscjHcm2kp1hkvDpGrqBw&response-content-disposition=attachment%3B%20filename%3Dcloud_redirect.dll&response-content-type=application%2Foctet-stream'
$destDll = Join-Path $SteamPath 'cloud_redirect.dll'
Invoke-WebRequest -Uri $crUrl -OutFile $destDll
Write-Host "[OK] cloud_redirect.dll -> $destDll"

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
# 3. Connexion OneDrive - meme flux OAuth que le companion app CloudRedirect
# (ui/Services/OAuthService.cs) : vrai login Microsoft, chiffrement DPAPI
# CurrentUser identique, memes emplacements de fichiers.
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Security

$clientId     = 'b15665d9-eda6-4092-8539-0eec376afd59'
$clientSecret = 'qtyfaBBYA403=unZUP40~_#'
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

Write-Host "[DONE] Termine. Relance Steam."
