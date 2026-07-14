# scripts/prepare-usb.ps1
# This script prepares the offline USB payload for deploying your Sovereign Enclave.
# It runs on your Windows developer machine.

# 1. Setup paths
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$StagingFolder = "$ProjectRoot\usb-payload"
$CacheFolder = "$ProjectRoot\.cache"
$ModelCache = "$CacheFolder\models"

Write-Host "[*] Starting Sovereign Enclave offline USB preparation script..." -ForegroundColor Cyan

# Helper Function: Safely remove files/folders with retries to handle Windows file locks
function Safe-RemoveItem {
    param([string]$Path, [switch]$Recurse)
    if (Test-Path $Path) {
        for ($i=0; $i -lt 5; $i++) {
            try {
                if ($Recurse) { Remove-Item $Path -Recurse -Force -ErrorAction Stop }
                else { Remove-Item $Path -Force -ErrorAction Stop }
                return
            } catch {
                Start-Sleep -Seconds 1
            }
        }
        Write-Warning "Could not remove $Path after 5 attempts. It may still be locked."
    }
}

# Ask user for execution mode (Interactive Toggle)
echo ""
Write-Host "Select the USB Preparation Mode:" -ForegroundColor Cyan
Write-Host "  [1] Full Payload (Sync versions, Zarf binaries, Software + ALL Models - Takes ~45 mins)" -ForegroundColor Gray
Write-Host "  [2] Software Only (Compile app packages only, skipping heavy models - Faster!)" -ForegroundColor Gray
Write-Host "  [3] Scripts Only (Sync versions and stage scripts ONLY, preserving existing packages - Super Fast!)" -ForegroundColor Gray
$Choice = Read-Host "Select an option [1-3, Default: 1]"

$ScriptsOnly = $false
$SoftwareOnly = $false
if ($Choice -eq "3") {
    $ScriptsOnly = $true
    Write-Host "`n[*] Running in SCRIPTS-ONLY mode..." -ForegroundColor Yellow
} elseif ($Choice -eq "2") {
    $SoftwareOnly = $true
    Write-Host "`n[*] Running in SOFTWARE-ONLY mode..." -ForegroundColor Yellow
} else {
    Write-Host "`n[*] Running in FULL PAYLOAD mode..." -ForegroundColor Yellow
}

# 1b. USB Drive Auto-Discovery (Unified Selection Interface)
$TargetUSBDrive = $null
Write-Host "`n[*] Scanning for connected external drives..." -ForegroundColor Yellow
# Find drives that are Removable OR Fixed (External SSDs) but NOT the C: drive
$RemovableVolumes = Get-Volume | Where-Object { 
    ($_.DriveType -eq 'Removable' -or ($_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne 'C')) -and 
    $_.DriveLetter 
}

if ($RemovableVolumes) {
    Write-Host "Available External Drives:" -ForegroundColor Cyan
    $volList = @()
    # Handle both single objects and arrays from Get-Volume
    if ($RemovableVolumes -is [Array]) { $volList = $RemovableVolumes } else { $volList = @($RemovableVolumes) }

    for ($i = 0; $i -lt $volList.Count; $i++) {
        $Vol = $volList[$i]
        $HealthStr = if ($Vol.HealthStatus -ne 'Healthy') { " ($($Vol.HealthStatus))" } else { "" }
        Write-Host "  [$($i + 1)] $($Vol.DriveLetter): ($($Vol.FileSystemLabel))$HealthStr" -ForegroundColor Gray
    }
    Write-Host "  [0] None / Local-Only Staging" -ForegroundColor Gray
    
    $Selection = Read-Host "`nSelect drive number to write directly to [0-$($volList.Count), Default: 0]"
    if ($Selection -match '^[1-9]\d*$' -and [int]$Selection -le $volList.Count) {
        $TargetUSBDrive = "$($volList[[int]$Selection - 1].DriveLetter):\"
        Write-Host "[+] Target Drive set to: $TargetUSBDrive" -ForegroundColor Green
    } else {
        Write-Host "[*] No drive selected. Proceeding with local staging only." -ForegroundColor Gray
    }
} else {
    Write-Host "No external drives detected. Staging will remain local-only." -ForegroundColor Gray
}

# Ensure local cache folders exist
if (-not (Test-Path $CacheFolder)) { New-Item -Path $CacheFolder -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $ModelCache)) { New-Item -Path $ModelCache -ItemType Directory -Force | Out-Null }

# 2. Run sync-versions.py
Write-Host "`n[*] Step 1: Synchronizing configuration files with versions.yaml..." -ForegroundColor Yellow
$SyncScript = "$ProjectRoot\scripts\sync-versions.py"
if (Test-Path $SyncScript) {
    python $SyncScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to run version synchronization script."
        exit $LASTEXITCODE
    }
}

# 3. Determine Zarf Version
Write-Host "`n[*] Step 2: Determining active Zarf CLI version..." -ForegroundColor Yellow
$ZarfBin = "zarf"
$ZarfVersion = ""
if (Test-Path "$ProjectRoot\zarf.exe") { $ZarfBin = "$ProjectRoot\zarf.exe" }
try {
    $ZarfVersion = & $ZarfBin version
    $ZarfVersion = $ZarfVersion.Trim()
} catch {
    $ZarfVersion = "v0.33.0"
}
Write-Host "Detected Zarf Version: $ZarfVersion" -ForegroundColor Green

# 4. Download Linux Zarf CLI Binary to Local Cache (Skip if scripts-only)
$LinuxZarfPath = "$CacheFolder\zarf-linux-amd64"
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 3: Skipping Linux Zarf binary download." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 3: Downloading matching Linux amd64 Zarf binary..." -ForegroundColor Yellow
    if (-not (Test-Path $LinuxZarfPath)) {
        $LinuxZarfUrl = "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf_${ZarfVersion}_Linux_amd64"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $LinuxZarfUrl -OutFile $LinuxZarfPath -UseBasicParsing
    } else {
        Write-Host "Cached Linux Zarf binary exists." -ForegroundColor Green
    }
}

# 5. Download matching Zarf Init Package to Local Cache (Skip if scripts-only)
$ZarfInitPkgPath = "$CacheFolder\zarf-init-amd64-${ZarfVersion}.tar.zst"
if ($ScriptsOnly) {
    Write-Host "`n[*] Step 3b: Skipping Zarf Init Package download." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 3b: Downloading matching Zarf Init Package (amd64)..." -ForegroundColor Yellow
    if (-not (Test-Path $ZarfInitPkgPath)) {
        $ZarfInitPkgUrl = "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf-init-amd64-${ZarfVersion}.tar.zst"
        Invoke-WebRequest -Uri $ZarfInitPkgUrl -OutFile $ZarfInitPkgPath -UseBasicParsing
    } else {
        Write-Host "Cached Zarf Init Package exists." -ForegroundColor Green
    }
}

# 6. Download AI Models (Skip if scripts/software only)
if ($ScriptsOnly -or $SoftwareOnly) {
    Write-Host "`n[*] Step 3c: Skipping heavy AI model downloads." -ForegroundColor Gray
} else {
    Write-Host "`n[*] Step 3c: Downloading/Verifying AI Model weights..." -ForegroundColor Yellow
    
    # Load model info from versions.yaml (simplified parsing for PowerShell)
    $VersionsContent = Get-Content "$ProjectRoot\versions.yaml" -Raw
    $70bName = [regex]::Match($VersionsContent, '70b_gguf_name:\s*"([^"]+)"').Groups[1].Value
    $70bUrl = [regex]::Match($VersionsContent, '70b_gguf_url:\s*"([^"]+)"').Groups[1].Value
    $14bGGUFName = [regex]::Match($VersionsContent, '14b_gguf_name:\s*"([^"]+)"').Groups[1].Value
    $14bGGUFUrl = [regex]::Match($VersionsContent, '14b_gguf_url:\s*"([^"]+)"').Groups[1].Value
    $14bRepo = [regex]::Match($VersionsContent, '14b_awq_repo:\s*"([^"]+)"').Groups[1].Value
    
    # 70B GGUF Download
    $70bPath = "$ModelCache\$70bName"
    if (-not (Test-Path $70bPath)) {
        Write-Host "Downloading 70B GGUF Model (~43GB) via curl... This is MUCH faster." -ForegroundColor Yellow
        & curl.exe -L -C - "$70bUrl" -o "$70bPath"
    } else { Write-Host "Cached 70B GGUF model found." -ForegroundColor Green }
    
    # 14B GGUF Download
    $14bGGUFPath = "$ModelCache\$14bGGUFName"
    if (-not (Test-Path $14bGGUFPath)) {
        Write-Host "Downloading 14B GGUF Model (~9GB) via curl..." -ForegroundColor Yellow
        & curl.exe -L -C - "$14bGGUFUrl" -o "$14bGGUFPath"
    } else { Write-Host "Cached 14B GGUF model found." -ForegroundColor Green }
    
    # 14B AWQ Download
    $14bDir = "$ModelCache\deepseek-r1-distill-qwen-14b-awq"
    if (-not (Test-Path $14bDir)) {
        New-Item -Path $14bDir -ItemType Directory -Force | Out-Null
        Write-Host "Downloading 14B AWQ Model weights via curl..." -ForegroundColor Yellow
        $files = @("config.json", "generation_config.json", "model.safetensors", "quantization_config.json", "tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json")
        foreach ($f in $files) {
            $fUrl = "https://huggingface.co/$14bRepo/resolve/main/$f"
            $fPath = "$14bDir\$f"
            if (-not (Test-Path $fPath)) { 
                & curl.exe -L -C - "$fUrl" -o "$fPath"
            }
        }
    } else { Write-Host "Cached 14B AWQ model directory found." -ForegroundColor Green }
}

# 7. Clean / Create Staging Folder
Write-Host "`n[*] Step 4: Preparing staging directory..." -ForegroundColor Yellow
if (-not (Test-Path $StagingFolder)) { New-Item -Path $StagingFolder -ItemType Directory -Force | Out-Null }
if ($ScriptsOnly) {
    Safe-RemoveItem -Path (Join-Path $StagingFolder "scripts") -Recurse
    Safe-RemoveItem -Path (Join-Path $StagingFolder "versions.yaml")
} else {
    Safe-RemoveItem -Path $StagingFolder -Recurse
    New-Item -Path $StagingFolder -ItemType Directory -Force | Out-Null
}

# 8. Build Packages (Conditional)
if (-not $ScriptsOnly) {
    # Software Packages
    Write-Host "`n[*] Step 5: Compiling Software Zarf packages..." -ForegroundColor Yellow
    & $ZarfBin package create "$ProjectRoot\bootstrap\zarf-beelink.yaml" --output "$StagingFolder" --architecture amd64 --skip-sbom --confirm
    & $ZarfBin package create "$ProjectRoot\bootstrap\zarf-4090.yaml" --output "$StagingFolder" --architecture amd64 --skip-sbom --confirm
    
    # Model Packages (Only in Full Mode)
    if (-not $SoftwareOnly) {
        Write-Host "`n[*] Step 6: Compiling individual Model Zarf packages directly from cache..." -ForegroundColor Yellow
        
        # 1. 70B GGUF Package
        Copy-Item "$ProjectRoot\bootstrap\zarf-model-70b-gguf.yaml" "$ModelCache\zarf.yaml"
        & $ZarfBin package create "$ModelCache" --output "$StagingFolder" --architecture amd64 --skip-sbom --confirm
        Safe-RemoveItem -Path "$ModelCache\zarf.yaml"
        
        # 2. 14B GGUF Package
        Copy-Item "$ProjectRoot\bootstrap\zarf-model-14b-gguf.yaml" "$ModelCache\zarf.yaml"
        & $ZarfBin package create "$ModelCache" --output "$StagingFolder" --architecture amd64 --skip-sbom --confirm
        Safe-RemoveItem -Path "$ModelCache\zarf.yaml"
        
        # 3. 14B AWQ Package
        Copy-Item "$ProjectRoot\bootstrap\zarf-model-14b-awq.yaml" "$ModelCache\zarf.yaml"
        & $ZarfBin package create "$ModelCache" --output "$StagingFolder" --architecture amd64 --skip-sbom --confirm
        Safe-RemoveItem -Path "$ModelCache\zarf.yaml"
    }
}

# 9. Final Staging (Scripts & Binaries)
Write-Host "`n[*] Step 7: Staging deployment scripts and binaries..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "$StagingFolder\scripts" -Force | Out-Null
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Get-ChildItem -Path "$ProjectRoot\scripts" | ForEach-Object {
    $TargetFile = "$StagingFolder\scripts\$($_.Name)"
    if ($_.Extension -eq ".sh" -or $_.Name -eq "gcert") {
        $Content = [System.IO.File]::ReadAllText($_.FullName).Replace("`r", "")
        [System.IO.File]::WriteAllText($TargetFile, $Content, $Utf8NoBom)
    } else { Copy-Item $_.FullName $TargetFile }
}
if (Test-Path $LinuxZarfPath) { Copy-Item $LinuxZarfPath "$StagingFolder\zarf" -Force }
if (Test-Path $ZarfInitPkgPath) { Copy-Item $ZarfInitPkgPath "$StagingFolder\zarf-init-amd64-${ZarfVersion}.tar.zst" -Force }
Copy-Item "$ProjectRoot\versions.yaml" $StagingFolder -Force

# 10. Direct USB Copy (Optional)
if ($TargetUSBDrive) {
    Write-Host "`n[*] Step 8: Copying staging payload to USB drive ($TargetUSBDrive)..." -ForegroundColor Yellow
    if ($ScriptsOnly) {
        # Scripts-Only: Target specific folders to avoid 60GB copy
        Copy-Item -Path (Join-Path $StagingFolder "scripts") -Destination $TargetUSBDrive -Recurse -Force
        Copy-Item -Path (Join-Path $StagingFolder "versions.yaml") -Destination $TargetUSBDrive -Force
    } else {
        # Full or Software: Copy everything
        Copy-Item -Path "$StagingFolder\*" -Destination $TargetUSBDrive -Recurse -Force
    }
    Write-Host "[+] USB drive updated successfully." -ForegroundColor Green
}

Write-Host "`n[+] Offline USB Payload Preparation Complete! [+]" -ForegroundColor Green
if (-not $TargetUSBDrive) {
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "1. Format your USB flash drive (if first-time setup)." -ForegroundColor White
    Write-Host "2. Copy updated contents of [$StagingFolder] directly to the root of your USB drive." -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
}
