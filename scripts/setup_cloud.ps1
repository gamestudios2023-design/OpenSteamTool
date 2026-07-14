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
# 3. Connexion OneDrive via rclone (rclone.org) - meme client OAuth par
# defaut que celui que CloudRedirect emprunte, mais avec l'implementation
# reelle et eprouvee de rclone plutot qu'un flux maison. Beaucoup plus
# fiable si le navigateur bloque des redirections localhost faites main.
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Security

$rcloneDir = Join-Path $env:TEMP 'rclone-tool'
$rcloneExe = Join-Path $rcloneDir 'rclone.exe'

if (-not (Test-Path $rcloneExe)) {
    Write-Host "[INFO] Telechargement de rclone..."
    $rcloneZipUrl = 'https://github.com/rclone/rclone/releases/download/v1.74.4/rclone-v1.74.4-windows-amd64.zip'
    $tmpRcloneZip = Join-Path $env:TEMP 'rclone.zip'
    Invoke-WebRequest -Uri $rcloneZipUrl -OutFile $tmpRcloneZip

    $tmpRcloneExtract = Join-Path $env:TEMP ("rclone-extract-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $tmpRcloneZip -DestinationPath $tmpRcloneExtract -Force
    $foundExe = Get-ChildItem -Path $tmpRcloneExtract -Filter 'rclone.exe' -Recurse | Select-Object -First 1
    if (-not $foundExe) { throw "rclone.exe introuvable dans le zip telecharge." }
    New-Item -ItemType Directory -Path $rcloneDir -Force | Out-Null
    Copy-Item -Path $foundExe.FullName -Destination $rcloneExe -Force
    Remove-Item -Path $tmpRcloneExtract, $tmpRcloneZip -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] rclone pret."
} else {
    Write-Host "[INFO] rclone deja present."
}

Write-Host "[INFO] Lancement de 'rclone authorize onedrive' - ton navigateur va s'ouvrir, connecte-toi et clique Accepter."
$rcloneOutput = & $rcloneExe authorize "onedrive" 2>&1 | Out-String

$jsonMatch = [regex]::Match($rcloneOutput, '\{[^{}]*"access_token"[^{}]*\}')
if (-not $jsonMatch.Success) {
    Write-Host $rcloneOutput
    throw "rclone n'a pas renvoye de token (sortie complete affichee ci-dessus). Annule ou echec de connexion."
}
$rcloneToken = $jsonMatch.Value | ConvertFrom-Json
if (-not $rcloneToken.refresh_token) { throw "Pas de refresh_token dans la sortie rclone." }

$expiresAt = [long][DateTimeOffset]::Parse($rcloneToken.expiry).ToUnixTimeSeconds()
$tokenJson = [ordered]@{
    access_token = $rcloneToken.access_token; refresh_token = $rcloneToken.refresh_token; expires_at = $expiresAt
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
