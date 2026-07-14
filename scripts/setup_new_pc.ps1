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
$ostUrl = 'https://release-assets.githubusercontent.com/github-production-release-asset/1219526865/a9b329ca-f260-497e-a12c-75025624d60c?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-07-14T14%3A10%3A28Z&rscd=attachment%3B+filename%3DOpenSteamTool-1.4.8-Debug.zip&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-07-14T13%3A10%3A25Z&ske=2026-07-14T14%3A10%3A28Z&sks=b&skv=2018-11-09&sig=ZGc7%2FaUN8cMp9aChsaYStwCiZwvsE07cMBMkjs4iTjI%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4NDAzNjczNCwibmJmIjoxNzg0MDM0OTM0LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.XJkj0e6JP6e81zqKCTEa5zmhjsZa-Pznuu9o_rSEOA4&response-content-disposition=attachment%3B%20filename%3DOpenSteamTool-1.4.8-Debug.zip&response-content-type=application%2Foctet-stream'
$tmpZip = Join-Path $env:TEMP 'OpenSteamTool-1.4.8-Debug.zip'
Invoke-WebRequest -Uri $ostUrl -OutFile $tmpZip
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
$crUrl = 'https://claude.ai/api/organizations/f226b83a-4059-45e6-a322-b4701d0270d5/files/85749eee-e896-4ae0-9586-6b6cc6f77d3b/contents'
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
