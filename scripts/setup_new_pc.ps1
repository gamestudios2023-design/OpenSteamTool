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
    throw "Steam introuvable automatiquement. Modifie la ligne 'Get-SteamInstallPath' en haut du script pour mettre ton chemin Steam directement."
}
$SteamPath = $SteamPath.TrimEnd('\')
Write-Host "[INFO] Steam: $SteamPath"

# ---------------------------------------------------------------------------
# 0. OpenSteamTool
# ---------------------------------------------------------------------------
Write-Host "[INFO] Telechargement d'OpenSteamTool..."
$browserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$ostUrl = 'https://dl-29vb9178.swisstransfer.com/api/download/d58cba7f-7fb2-41f6-9ab4-a911897cdd6b/93804f8d-c72b-4634-8793-277bd86b0060'
$tmpZip = Join-Path $env:TEMP 'OpenSteamTool.zip'
Invoke-WebRequest -Uri $ostUrl -OutFile $tmpZip -UserAgent $browserUA -Headers @{ 'Referer' = 'https://www.swisstransfer.com/' }
Write-Host "[OK] Telecharge."

$tmpExtract = Join-Path $env:TEMP ("OpenSteamTool-extract-" + [guid]::NewGuid().ToString('N'))
Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

foreach ($dll in @('OpenSteamTool.dll', 'dwmapi.dll', 'xinput1_4.dll')) {
    $found = Get-ChildItem -Path $tmpExtract -Filter $dll -Recurse | Select-Object -First 1
    if (-not $found) { throw "$dll introuvable dans le zip apres extraction." }
    Copy-Item -Path $found.FullName -Destination (Join-Path $SteamPath $dll) -Force
    Write-Host "[OK] $dll -> $SteamPath"
}
Remove-Item -Path $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 1. cloud_redirect.dll (version personnalisee avec support Backblaze S3)
# ---------------------------------------------------------------------------
Write-Host "[INFO] Telechargement de cloud_redirect.dll (version S3)..."
$crUrl = 'https://dl-bkgz5xt6.swisstransfer.com/api/download/4c6d172a-1a8e-4cae-80aa-87be3b138cb9/f6bfa8cc-3604-4291-bf2d-3828e213dcdf'
$destDll = Join-Path $SteamPath 'cloud_redirect.dll'
Invoke-WebRequest -Uri $crUrl -OutFile $destDll -UserAgent $browserUA -Headers @{ 'Referer' = 'https://www.swisstransfer.com/' }
Write-Host "[OK] cloud_redirect.dll -> $destDll"

# ---------------------------------------------------------------------------
# 1b. Lua config (jeux a debloquer)
# ---------------------------------------------------------------------------
Write-Host "[INFO] Telechargement du lua Red Dead Redemption 2..."
$luaUrl = 'https://dl-s3cy4u5n.swisstransfer.com/api/download/9592dc9a-603e-48b2-8f4b-9d9e8b5a62aa/81191ea2-08f9-4deb-a466-307cf4dde59a'
$luaDir = Join-Path $SteamPath 'config\lua'
New-Item -ItemType Directory -Path $luaDir -Force | Out-Null
$luaPath = Join-Path $luaDir 'rdr2.lua'
Invoke-WebRequest -Uri $luaUrl -OutFile $luaPath -UserAgent $browserUA -Headers @{ 'Referer' = 'https://www.swisstransfer.com/' }
Write-Host "[OK] rdr2.lua -> $luaDir"

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
# 3. config.json CloudRedirect : provider S3 / Backblaze, cles en dur.
# ---------------------------------------------------------------------------
$configDir = Join-Path $env:APPDATA 'CloudRedirect'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$configPath = Join-Path $configDir 'config.json'

$config = [ordered]@{
    provider       = 's3'
    s3_endpoint    = 's3.eu-central-003.backblazeb2.com'
    s3_bucket      = 'Hmmggg'
    s3_region      = 'eu-central-003'
    s3_key_id      = 'REDACTED_BACKBLAZE_KEY_ID'
    s3_secret_key  = 'REDACTED_BACKBLAZE_APP_KEY'
} | ConvertTo-Json

Set-Content -Path $configPath -Value $config -Encoding UTF8
Write-Host "[OK] Config CloudRedirect (Backblaze S3) -> $configPath"

Write-Host "[DONE] Termine. Lance Steam."
