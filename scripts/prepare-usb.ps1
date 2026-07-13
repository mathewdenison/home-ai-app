# scripts/prepare-usb.ps1
# This script prepares the offline USB payload for deploying your Sovereign Enclave.
# It runs on your Windows developer machine.

# 1. Setup paths
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$StagingFolder = "$ProjectRoot\usb-payload"

Write-Host "[*] Starting Sovereign Enclave offline USB preparation script..." -ForegroundColor Cyan

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

# 4. Download Linux Zarf CLI Binary
Write-Host "`n[*] Step 3: Downloading matching Linux amd64 Zarf binary..." -ForegroundColor Yellow
$LinuxZarfUrl = "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf_${ZarfVersion}_Linux_amd64"
$LinuxZarfPath = "$ProjectRoot\zarf-linux-amd64"

if (Test-Path $LinuxZarfPath) {
    Write-Host "Local Linux Zarf binary already exists at $LinuxZarfPath. Skipping download." -ForegroundColor Green
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

# 5. Clean / Create Staging Folder
Write-Host "`n[*] Step 4: Creating clean staging directory at $StagingFolder..." -ForegroundColor Yellow
if (Test-Path $StagingFolder) {
    Remove-Item -Path $StagingFolder -Recurse -Force
}
New-Item -Path $StagingFolder -ItemType Directory -Force | Out-Null

# 6. Build Beelink Package
Write-Host "`n[*] Step 5: Compiling Beelink Gateway Zarf package (amd64)..." -ForegroundColor Yellow
& $ZarfBin package create "$ProjectRoot\bootstrap\zarf-beelink.yaml" --architecture amd64 --confirm
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to compile Beelink package."
    exit $LASTEXITCODE
}

# Move Beelink Package to Staging
$BeelinkPkg = Get-ChildItem -Path $ProjectRoot -Filter "zarf-package-sovereign-ai-enclave-beelink-amd64-*.tar.zst" | Select-Object -First 1
if ($BeelinkPkg) {
    Move-Item -Path $BeelinkPkg.FullName -Destination $StagingFolder -Force
    Write-Host "Moved Beelink package to staging folder." -ForegroundColor Green
} else {
    Write-Warning "Could not find compiled Beelink package tarball!"
}

# 7. Build 4090 Package
Write-Host "`n[*] Step 6: Compiling 4090 Workstation Zarf package (amd64)..." -ForegroundColor Yellow
& $ZarfBin package create "$ProjectRoot\bootstrap\zarf-4090.yaml" --architecture amd64 --confirm
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to compile 4090 Workstation package."
    exit $LASTEXITCODE
}

# Move 4090 Package to Staging
$WorkstationPkg = Get-ChildItem -Path $ProjectRoot -Filter "zarf-package-sovereign-ai-enclave-4090-amd64-*.tar.zst" | Select-Object -First 1
if ($WorkstationPkg) {
    Move-Item -Path $WorkstationPkg.FullName -Destination $StagingFolder -Force
    Write-Host "Moved 4090 Workstation package to staging folder." -ForegroundColor Green
} else {
    Write-Warning "Could not find compiled 4090 Workstation package tarball!"
}

# 8. Copy Scripts and Files to Staging
Write-Host "`n[*] Step 7: Staging deployment scripts and binaries..." -ForegroundColor Yellow

# Copy Scripts folder
Copy-Item -Path "$ProjectRoot\scripts" -Destination "$StagingFolder\scripts" -Recurse -Force

# Copy Linux Zarf binary to root of staging AND to scripts/ as zarf
Copy-Item -Path $LinuxZarfPath -Destination "$StagingFolder\zarf" -Force
Copy-Item -Path $LinuxZarfPath -Destination "$StagingFolder\scripts\zarf" -Force

# Copy configurations for reference
Copy-Item -Path "$ProjectRoot\versions.yaml" -Destination $StagingFolder -Force

Write-Host "Staging payload populated successfully." -ForegroundColor Green

# 9. Finished
Write-Host "`n[+] Offline USB Payload Preparation Complete! [+]" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "1. Format your USB flash drive." -ForegroundColor White
Write-Host "2. Copy ALL contents of the [$StagingFolder] directory directly to the root of your USB drive." -ForegroundColor White
Write-Host "3. Plug the USB drive into your target server." -ForegroundColor White
Write-Host "4. On your server terminal, manually unblock USB storage and allow the USB device (e.g. via USBGuard if active):" -ForegroundColor White
Write-Host "   sudo usbguard list-devices" -ForegroundColor Gray
Write-Host "   sudo usbguard allow-device <ID>" -ForegroundColor Gray
Write-Host "5. Mount your USB drive and run the enclave setup script:" -ForegroundColor White
Write-Host "   sudo mkdir -p /mnt/usb" -ForegroundColor Gray
Write-Host "   sudo mount /dev/sdX1 /mnt/usb" -ForegroundColor Gray
Write-Host "   cd /mnt/usb && sudo ./scripts/setup-enclave.sh" -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Cyan
