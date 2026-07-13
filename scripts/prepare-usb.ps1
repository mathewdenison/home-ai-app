# scripts/prepare-usb.ps1
# This script prepares the offline USB payload for deploying your Sovereign Enclave.
# It runs on your Windows developer machine.

# 1. Setup paths
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$StagingFolder = "$ProjectRoot\usb-payload"
$CacheFolder = "$ProjectRoot\.cache"

Write-Host "[*] Starting Sovereign Enclave offline USB preparation script..." -ForegroundColor Cyan

# Ask user for execution mode (Interactive Toggle)
echo ""
Write-Host "Select the USB Preparation Mode:" -ForegroundColor Cyan
Write-Host "  [1] Full Payload (Sync versions, download Zarf binaries, compile packages, and stage scripts - Takes a few minutes)" -ForegroundColor Gray
Write-Host "  [2] Scripts Only (Sync versions and stage scripts ONLY, preserving existing packages - Super Fast!)" -ForegroundColor Gray
$Choice = Read-Host "Select an option [1-2, Default: 1]"

$ScriptsOnly = $false
if ($Choice -eq "2") {
    $ScriptsOnly = $true
    Write-Host "`n[*] Running in SCRIPTS-ONLY mode..." -ForegroundColor Yellow
} else {
    Write-Host "`n[*] Running in FULL PAYLOAD mode..." -ForegroundColor Yellow
}

# Ensure local cache folder exists
if (-not (Test-Path $CacheFolder)) {
    New-Item -Path $CacheFolder -ItemType Directory -Force | Out-Null
}

# 2. Run sync-versions.py
Write-Host "`n[*] Step 1: Synchronizing configuration files with versions.yaml..." -ForegroundColor Yellow
$SyncScript = "$ProjectRoot\scripts\sync-versions.py"
if (Test-Path $SyncScript) {
    python $SyncScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to run version synchronization script."
        exit $LASTEXITCODE
    }
} else {
    Write-Warning "Could not find sync-versions.py at $SyncScript"
}

# 3. Determine Zarf Version
Write-Host "`n[*] Step 2: Determining active Zarf CLI version..." -ForegroundColor Yellow
$ZarfBin = "zarf"
$ZarfVersion = ""

# Try local binary first
if (Test-Path "$ProjectRoot\zarf.exe") {
    $ZarfBin = "$ProjectRoot\zarf.exe"
}

try {
    $ZarfVersion = & $ZarfBin version
    $ZarfVersion = $ZarfVersion.Trim()
} catch {
    Write-Warning "Could not run local Zarf binary or find Zarf in PATH. Defaulting to v0.33.0"
    $ZarfVersion = "v0.33.0"
}

Write-Host "Detected Zarf Version: $ZarfVersion" -ForegroundColor Green

# 4. Download Linux Zarf CLI Binary to Local Cache (Skip if scripts-only)
$LinuxZarfPath = "$CacheFolder\zarf-linux-amd64"
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 3: Skipping Linux Zarf binary download (Scripts-Only Mode)." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 3: Downloading matching Linux amd64 Zarf binary..." -ForegroundColor Yellow
    $LinuxZarfUrl = "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf_${ZarfVersion}_Linux_amd64"

    if (Test-Path $LinuxZarfPath) {
        Write-Host "Cached Linux Zarf binary exists at $LinuxZarfPath. Skipping download." -ForegroundColor Green
    } else {
        Write-Host "Downloading from: $LinuxZarfUrl" -ForegroundColor Gray
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $LinuxZarfUrl -OutFile $LinuxZarfPath -UseBasicParsing
            Write-Host "Download complete: $LinuxZarfPath" -ForegroundColor Green
        } catch {
            Write-Error "Failed to download Linux Zarf binary from $LinuxZarfUrl. Error: $_"
            exit 1
        }
    }
}

# 5. Download matching Zarf Init Package to Local Cache (Skip if scripts-only)
$ZarfInitPkgPath = "$CacheFolder\zarf-init-amd64-${ZarfVersion}.tar.zst"
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 3b: Skipping Zarf Init Package download (Scripts-Only Mode)." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 3b: Downloading matching Zarf Init Package (amd64)..." -ForegroundColor Yellow
    $ZarfInitPkgUrl = "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf-init-amd64-${ZarfVersion}.tar.zst"

    if (Test-Path $ZarfInitPkgPath) {
        Write-Host "Cached Zarf Init Package exists at $ZarfInitPkgPath. Skipping download." -ForegroundColor Green
    } else {
        Write-Host "Downloading from: $ZarfInitPkgUrl" -ForegroundColor Gray
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $ZarfInitPkgUrl -OutFile $ZarfInitPkgPath -UseBasicParsing
            Write-Host "Download complete: $ZarfInitPkgPath" -ForegroundColor Green
        } catch {
            Write-Error "Failed to download Zarf Init Package from $ZarfInitPkgUrl. Error: $_"
            exit 1
        }
    }
}

# 6. Clean / Create Staging Folder
Write-Host "`n[*] Step 4: Preparing staging directory at $StagingFolder..." -ForegroundColor Yellow
if (-not (Test-Path $StagingFolder)) {
    New-Item -Path $StagingFolder -ItemType Directory -Force | Out-Null
}

if ($ScriptsOnly) {
    # Scripts-Only: Clean only the scripts folder and reference files to preserve compiled Zarf packages!
    $ScriptsStaging = Join-Path $StagingFolder "scripts"
    if (Test-Path $ScriptsStaging) {
        Remove-Item -Path $ScriptsStaging -Recurse -Force
    }
    $ReferenceConfig = Join-Path $StagingFolder "versions.yaml"
    if (Test-Path $ReferenceConfig) {
        Remove-Item -Path $ReferenceConfig -Force
    }
} else {
    # Full Payload: Wipe the entire staging folder to ensure a 100% clean rebuild
    Remove-Item -Path $StagingFolder -Recurse -Force
    New-Item -Path $StagingFolder -ItemType Directory -Force | Out-Null
}

# 7. Build Beelink Package Directly to Staging (Skip if scripts-only)
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 5: Skipping Beelink Gateway package compilation (Scripts-Only Mode)." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 5: Compiling Beelink Gateway Zarf package directly to staging..." -ForegroundColor Yellow
    & $ZarfBin package create "$ProjectRoot\bootstrap\zarf-beelink.yaml" --output "$StagingFolder" --architecture amd64 --confirm
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to compile Beelink package."
        exit $LASTEXITCODE
    }
    Write-Host "Beelink Gateway package compiled successfully inside $StagingFolder." -ForegroundColor Green
}

# 8. Build 4090 Package Directly to Staging (Skip if scripts-only)
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 6: Skipping 4090 Workstation package compilation (Scripts-Only Mode)." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 6: Compiling 4090 Workstation Zarf package directly to staging..." -ForegroundColor Yellow
    & $ZarfBin package create "$ProjectRoot\bootstrap\zarf-4090.yaml" --output "$StagingFolder" --architecture amd64 --confirm
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to compile 4090 Workstation package."
        exit $LASTEXITCODE
    }
    Write-Host "4090 Workstation package compiled successfully inside $StagingFolder." -ForegroundColor Green
}

# 9. Copy Scripts and Files to Staging
Write-Host "`n[*] Step 7: Staging deployment scripts and binaries..." -ForegroundColor Yellow

# Copy Scripts folder and ensure all Linux scripts have Unix (LF) line endings and NO UTF-8 BOM!
New-Item -ItemType Directory -Path "$StagingFolder\scripts" -Force | Out-Null
$Utf8NoBom = New-Object System.Text.Encoding+UTF8Encoding($false)

Get-ChildItem -Path "$ProjectRoot\scripts" | ForEach-Object {
    $TargetFile = "$StagingFolder\scripts\$($_.Name)"
    if ($_.Extension -eq ".sh" -or $_.Name -eq "gcert") {
        # Convert CRLF to LF and save using custom UTF8 (No BOM) for absolute Linux/Bash compatibility
        $Content = [System.IO.File]::ReadAllText($_.FullName)
        $Content = $Content -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($TargetFile, $Content, $Utf8NoBom)
    } else {
        Copy-Item -Path $_.FullName -Destination $TargetFile -Force
    }
}

# Copy Linux Zarf binary from Cache to root of staging AND to scripts/ as zarf (if they exist in cache)
if (Test-Path $LinuxZarfPath) {
    Copy-Item -Path $LinuxZarfPath -Destination "$StagingFolder\zarf" -Force | Out-Null
    Copy-Item -Path $LinuxZarfPath -Destination "$StagingFolder\scripts\zarf" -Force | Out-Null
}

# Copy matching offline Zarf Init Package from Cache to root of staging so that "zarf init" works completely offline! (if exists)
if (Test-Path $ZarfInitPkgPath) {
    Copy-Item -Path $ZarfInitPkgPath -Destination "$StagingFolder\zarf-init-amd64-${ZarfVersion}.tar.zst" -Force | Out-Null
}

# Copy configurations for reference
Copy-Item -Path "$ProjectRoot\versions.yaml" -Destination $StagingFolder -Force | Out-Null

Write-Host "Staging payload populated successfully." -ForegroundColor Green

# 10. Finished
Write-Host "`n[+] Offline USB Payload Preparation Complete! [+]" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "1. Format your USB flash drive (if first-time setup)." -ForegroundColor White
if ($ScriptsOnly) {
    Write-Host "2. Copy the updated contents of [$StagingFolder] directly to the root of your USB drive." -ForegroundColor White
    Write-Host "   (This will overwrite only the /scripts folder and leave your massive Zarf packages intact!)" -ForegroundColor Gray
} else {
    Write-Host "2. Copy ALL contents of the [$StagingFolder] directory directly to the root of your USB drive." -ForegroundColor White
}
Write-Host "3. Plug the USB drive into your target server." -ForegroundColor White
Write-Host "4. On your server terminal, manually unblock USB storage and allow the USB device (e.g. via USBGuard if active):" -ForegroundColor White
Write-Host "   sudo usbguard list-devices" -ForegroundColor Gray
Write-Host "   sudo usbguard allow-device <ID>" -ForegroundColor Gray
Write-Host "5. Mount your USB drive and run the enclave setup script:" -ForegroundColor White
Write-Host "   sudo mkdir -p /mnt/usb" -ForegroundColor Gray
Write-Host "   sudo mount /dev/sdX1 /mnt/usb" -ForegroundColor Gray
Write-Host "   cd /mnt/usb && sudo ./scripts/setup-enclave.sh" -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Cyan
