# scripts/prepare-usb.ps1
# This script prepares the offline USB payload for deploying your Sovereign Enclave.
# It runs on your Windows developer machine.

# 1. Setup paths
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$StagingFolder = "$ProjectRoot\usb-payload"
$CacheFolder = "$ProjectRoot\.cache"
$ModelCache = "$CacheFolder\models"

# 1a. Hard-coded path definitions (unconditional)
$LinuxZarfPath = "$CacheFolder\zarf-linux-amd64"
$ZarfInitPkgPath = "" # Defined dynamically once version is known

Write-Host "--- Starting Sovereign Enclave offline USB preparation script ---" -ForegroundColor Cyan

# Helper Function: Safely remove files/folders with retries
function Safe-RemoveItem {
    param([string]$Path, [switch]$Recurse)
    if (Test-Path $Path) {
        for ($i=0; $i -lt 5; $i++) {
            try {
                if ($Recurse) { Remove-Item $Path -Recurse -Force -ErrorAction Stop }
                else { Remove-Item $Path -Force -ErrorAction Stop }
                return
            } catch { Start-Sleep -Seconds 1 }
        }
    }
}

# Helper Function: High-speed copy with real-time metrics
function Copy-WithProgress {
    param([string]$SourcePath, [string]$DestinationPath)
    $files = Get-ChildItem -Path $SourcePath -Recurse -File
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $processedBytes = 0
    $startTime = Get-Date
    Write-Host "--- Total data to transfer: $([math]::Round($totalBytes / 1GB, 2)) GB ---" -ForegroundColor Gray
    foreach ($file in $files) {
        $relativeName = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
        $targetFile = Join-Path $DestinationPath $relativeName
        $targetDir = Split-Path $targetFile
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        $sourceStream = [System.IO.File]::OpenRead($file.FullName)
        $destStream = [System.IO.File]::Create($targetFile)
        $buffer = New-Object byte[] 10MB
        while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destStream.Write($buffer, 0, $read)
            $processedBytes += $read
            $elapsed = (Get-Date) - $startTime
            $totalSeconds = $elapsed.TotalSeconds
            $speed = 0
            if ($totalSeconds -gt 0) { $speed = $processedBytes / $totalSeconds }
            $remainingBytes = $totalBytes - $processedBytes
            $etaSeconds = 0
            if ($speed -gt 0) { $etaSeconds = $remainingBytes / $speed }
            $etaTime = [TimeSpan]::FromSeconds($etaSeconds)
            $percent = [math]::Round(($processedBytes / $totalBytes) * 100, 1)
            $doneGB = [math]::Round($processedBytes / 1GB, 2)
            $totalGB = [math]::Round($totalBytes / 1GB, 2)
            $speedMB = [math]::Round($speed / 1MB, 2)
            $etaStr = $etaTime.ToString('hh\:mm\:ss')
            $status = "`r--- Progress: $percent% | Done: $doneGB GB / $totalGB GB | Speed: $speedMB MB/s | ETA: $etaStr ---   "
            Write-Host -NoNewline $status
        }
        $sourceStream.Close(); $destStream.Close()
    }
    Write-Host "`n"
}

# Execution Mode selection
Write-Host "`nSelect the USB Preparation Mode:" -ForegroundColor Cyan
Write-Host "  1: Full Payload (Sync versions, Zarf binaries, Software + ALL Models - Takes ~15-20 mins)" -ForegroundColor Gray
Write-Host "  2: Software Only (Compile app packages only, skipping heavy models - Fast!)" -ForegroundColor Gray
Write-Host "  3: Scripts Only (Sync versions and stage scripts ONLY - Super Fast!)" -ForegroundColor Gray
$Choice = Read-Host "Select an option [1-3, Default: 1]"
$ScriptsOnly = ($Choice -eq "3"); $SoftwareOnly = ($Choice -eq "2")

# USB Drive Auto-Discovery
$TargetUSBDrive = $null
Write-Host "`n--- Scanning for connected external drives ---" -ForegroundColor Yellow
$volList = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -match '^[A-Z]$' -and $_.Name -ne 'C' })
if ($volList.Count -gt 0) {
    Write-Host "Available External Drives:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $volList.Count; $i++) {
        $Vol = $volList[$i]; $Label = ""
        try { $Label = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Vol.Name):'").VolumeName } catch {}
        if (-not $Label) { $Label = "No Label" }
        Write-Host "  $($i + 1): $($Vol.Name): ($Label)" -ForegroundColor Gray
    }
    Write-Host "  0: None / Local-Only Staging" -ForegroundColor Gray
    $Selection = Read-Host "`nSelect drive number [0-$($volList.Count), Default: 0]"
    if ($Selection -match '^[1-9]\d*$' -and [int]$Selection -le $volList.Count) { 
        $TargetUSBDrive = "$($volList[[int]$Selection - 1].Name):\" 
        Write-Host "--- Target Drive set to: $TargetUSBDrive ---" -ForegroundColor Green
    }
} else { Write-Host "`nNo external drives detected. Staging will remain local-only." -ForegroundColor Gray }

# 2. Setup folders and sync versions
if (-not (Test-Path $CacheFolder)) { New-Item -Path $CacheFolder -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $ModelCache)) { New-Item -Path $ModelCache -ItemType Directory -Force | Out-Null }
python "$ProjectRoot\scripts\sync-versions.py"

# 3. Determine Zarf
$ZarfBin = if (Test-Path "$ProjectRoot\zarf.exe") { "$ProjectRoot\zarf.exe" } else { "zarf" }
$ZarfVersion = try { (& $ZarfBin version).Trim() } catch { "v0.33.0" }
Write-Host "`n--- Active Zarf Version: $ZarfVersion ---" -ForegroundColor Green

# Update Init Package path now that version is known
$ZarfInitPkgPath = "$CacheFolder\zarf-init-amd64-${ZarfVersion}.tar.zst"

# 4. Download Binaries
if (-not $ScriptsOnly) {
    Write-Host "`n--- Downloading matching Linux amd64 Zarf binary ---" -ForegroundColor Yellow
    if (-not (Test-Path $LinuxZarfPath)) { & curl.exe -L "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf_${ZarfVersion}_Linux_amd64" -o "$LinuxZarfPath" }
    
    Write-Host "`n--- Downloading matching Zarf Init Package (amd64) ---" -ForegroundColor Yellow
    if (-not (Test-Path $ZarfInitPkgPath)) { & curl.exe -L "https://github.com/zarf-dev/zarf/releases/download/$ZarfVersion/zarf-init-amd64-${ZarfVersion}.tar.zst" -o "$ZarfInitPkgPath" }
}

# 5. Download Models
if (-not ($ScriptsOnly -or $SoftwareOnly)) {
    $VersionsContent = Get-Content "$ProjectRoot\versions.yaml" -Raw
    $70bName = [regex]::Match($VersionsContent, '70b_gguf_name:\s*"([^"]+)"').Groups[1].Value
    $70bUrl = [regex]::Match($VersionsContent, '70b_gguf_url:\s*"([^"]+)"').Groups[1].Value
    $14bGGUFName = [regex]::Match($VersionsContent, '14b_gguf_name:\s*"([^"]+)"').Groups[1].Value
    $14bGGUFUrl = [regex]::Match($VersionsContent, '14b_gguf_url:\s*"([^"]+)"').Groups[1].Value
    $14bRepo = [regex]::Match($VersionsContent, '14b_awq_repo:\s*"([^"]+)"').Groups[1].Value
    
    if (-not (Test-Path "$ModelCache\$70bName")) { Write-Host "--- Downloading 70B GGUF Model (~43GB) via curl... ---" -ForegroundColor Yellow; & curl.exe -L -C - "$70bUrl" -o "$ModelCache\$70bName" }
    if (-not (Test-Path "$ModelCache\$14bGGUFName")) { Write-Host "--- Downloading 14B GGUF Model (~9GB) via curl... ---" -ForegroundColor Yellow; & curl.exe -L -C - "$14bGGUFUrl" -o "$ModelCache\$14bGGUFName" }
    $14bDir = "$ModelCache\deepseek-r1-distill-qwen-14b-awq"
    if (-not (Test-Path $14bDir)) {
        New-Item $14bDir -ItemType Directory -Force | Out-Null
        $files = @("config.json", "generation_config.json", "model.safetensors", "quantization_config.json", "tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json")
        foreach ($f in $files) { & curl.exe -L -C - "https://huggingface.co/$14bRepo/resolve/main/$f" -o "$14bDir\$f" }
    }
}

# 6. Clean and Build
Write-Host "`n--- Preparing staging directory ---" -ForegroundColor Yellow
if (-not (Test-Path $StagingFolder)) { New-Item $StagingFolder -ItemType Directory -Force | Out-Null }
if ($ScriptsOnly) { Safe-RemoveItem -Path (Join-Path $StagingFolder "scripts") -Recurse; Safe-RemoveItem -Path (Join-Path $StagingFolder "versions.yaml") }
else { Safe-RemoveItem $StagingFolder -Recurse; New-Item $StagingFolder -ItemType Directory -Force | Out-Null }

if (-not $ScriptsOnly) {
    Write-Host "`n--- Compiling Software and Model packages in PARALLEL ---" -ForegroundColor Yellow
    $BuildJobs = @()

    # Define build script blocks
    $SBlocks = @(
        { param($zb, $root, $out) & $zb package create "$root\bootstrap\zarf-beelink.yaml" --output "$out" --architecture amd64 --skip-sbom --confirm },
        { param($zb, $root, $out) & $zb package create "$root\bootstrap\zarf-4090.yaml" --output "$out" --architecture amd64 --skip-sbom --confirm }
    )
    if (-not $SoftwareOnly) {
        $SBlocks += { param($zb, $root, $out, $cache, $name) 
            $tmp = New-Item "$cache\70b-tmp" -ItemType Directory -Force
            Copy-Item "$root\bootstrap\zarf-model-70b-gguf.yaml" "$tmp\zarf.yaml"
            New-Item -ItemType HardLink -Path "$tmp\$name" -Value "$cache\$name" -Force | Out-Null
            & $zb package create "$tmp" --output "$out" --architecture amd64 --skip-sbom --confirm
            Remove-Item $tmp -Recurse -Force
        }
        $SBlocks += { param($zb, $root, $out, $cache, $name) 
            $tmp = New-Item "$cache\14b-gguf-tmp" -ItemType Directory -Force
            Copy-Item "$root\bootstrap\zarf-model-14b-gguf.yaml" "$tmp\zarf.yaml"
            New-Item -ItemType HardLink -Path "$tmp\$name" -Value "$cache\$name" -Force | Out-Null
            & $zb package create "$tmp" --output "$out" --architecture amd64 --skip-sbom --confirm
            Remove-Item $tmp -Recurse -Force
        }
        $SBlocks += { param($zb, $root, $out, $cache) 
            $tmp = New-Item "$cache\14b-awq-tmp" -ItemType Directory -Force
            Copy-Item "$root\bootstrap\zarf-model-14b-awq.yaml" "$tmp\zarf.yaml"
            $targetDir = Join-Path $tmp "deepseek-r1-distill-qwen-14b-awq"
            $sourceDir = Join-Path $cache "deepseek-r1-distill-qwen-14b-awq"
            New-Item -ItemType Junction -Path "$targetDir" -Value "$sourceDir" -Force | Out-Null
            & $zb package create "$tmp" --output "$out" --architecture amd64 --skip-sbom --confirm
            Remove-Item $tmp -Recurse -Force
        }
    }

    $BuildJobs += Start-Job -ScriptBlock $SBlocks[0] -ArgumentList $ZarfBin, $ProjectRoot, $StagingFolder
    $BuildJobs += Start-Job -ScriptBlock $SBlocks[1] -ArgumentList $ZarfBin, $ProjectRoot, $StagingFolder
    if (-not $SoftwareOnly) {
        $BuildJobs += Start-Job -ScriptBlock $SBlocks[2] -ArgumentList $ZarfBin, $ProjectRoot, $StagingFolder, $ModelCache, $70bName
        $BuildJobs += Start-Job -ScriptBlock $SBlocks[3] -ArgumentList $ZarfBin, $ProjectRoot, $StagingFolder, $ModelCache, $14bGGUFName
        $BuildJobs += Start-Job -ScriptBlock $SBlocks[4] -ArgumentList $ZarfBin, $ProjectRoot, $StagingFolder, $ModelCache
    }
    
    Write-Host "--- Waiting for parallel compilations to complete ---" -ForegroundColor Gray
    Wait-Job $BuildJobs | Out-Null
    Receive-Job $BuildJobs
}

# 7. Final Staging
Write-Host "`n--- Staging deployment scripts and binaries ---" -ForegroundColor Yellow
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

if ($TargetUSBDrive) {
    Write-Host "`n--- Copying staging payload to USB drive ($TargetUSBDrive) ---" -ForegroundColor Yellow
    if ($ScriptsOnly) { Copy-Item (Join-Path $StagingFolder "scripts") $TargetUSBDrive -Recurse -Force; Copy-Item (Join-Path $StagingFolder "versions.yaml") $TargetUSBDrive -Force }
    else { Copy-WithProgress -SourcePath "$StagingFolder\" -DestinationPath $TargetUSBDrive }
    Write-Host "--- USB drive updated successfully ---" -ForegroundColor Green
}
Write-Host "`n--- Offline USB Payload Preparation Complete! ---" -ForegroundColor Green
