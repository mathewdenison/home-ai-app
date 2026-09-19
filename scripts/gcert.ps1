# gcert.ps1 - Windows Native Token Hydration Developer Utility
# Replicates the Google OAuth 2.0 Device Code Flow natively in PowerShell.

$AUTHENTIK_BASE = "https://auth.yourdomain.com"
$CLIENT_ID = "YOUR_AUTHENTIK_CLIENT_ID_HERE"

Write-Host "🌐 [1/3] Initializing OAuth Device Code Handshake with Authentik..." -ForegroundColor Yellow
$Body = @{
    client_id = $CLIENT_ID
    scope     = "openid email profile"
}

try {
    $InitResponse = Invoke-RestMethod -Uri "$AUTHENTIK_BASE/application/o/device/code/" -Method Post -Body $Body
} catch {
    Write-Error "❌ Handshake initialization failed: $_"
    exit 1
}

$DeviceCode = $InitResponse.device_code
$UserCode = $InitResponse.user_code
$VerifyUrl = $InitResponse.verification_uri
$PollInterval = if ($InitResponse.interval) { $InitResponse.interval } else { 5 }

Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  👉 STEP 1: Open your web browser and navigate to:" -ForegroundColor Cyan
Write-Host "     $VerifyUrl" -ForegroundColor Green
Write-Host ""
Write-Host "  🔑 STEP 2: Input this secure verification code:" -ForegroundColor Cyan
Write-Host "     $UserCode" -ForegroundColor Green
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan

# Open default system web browser
Start-Process $VerifyUrl

Write-Host "⏳ [2/3] Awaiting browser-based Google OAuth validation confirmation..." -ForegroundColor Yellow
$TokenBody = @{
    grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
    device_code = $DeviceCode
    client_id   = $CLIENT_ID
}

$AccessToken = $null
while ($true) {
    try {
        $PollResponse = Invoke-RestMethod -Uri "$AUTHENTIK_BASE/application/o/token/" -Method Post -Body $TokenBody
        if ($PollResponse.access_token) {
            $AccessToken = $PollResponse.access_token
            break
        }
    } catch {
        # Catch 400 Bad Request which carries the OAuth error responses (like authorization_pending)
        if ($_.Exception.Response) {
            $Reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $ErrorBody = $Reader.ReadToEnd() | ConvertFrom-Json
            if ($ErrorBody.error -eq "authorization_pending") {
                Start-Sleep -Seconds $PollInterval
                continue
            } else {
                Write-Error "❌ Token acquisition failed: $($ErrorBody.error_description) ($($ErrorBody.error))"
                exit 1
            }
        } else {
            Write-Error "❌ Request failed: $_"
            exit 1
        }
    }
}

Write-Host "✅ [3/3] Google Authentication Validated. Token acquired." -ForegroundColor Green

$ConfigDir = Join-Path $HOME ".config\enclave"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$TokenFile = Join-Path $ConfigDir "session_token"

# Write the token to the file (ASCII/UTF8 without BOM/newline)
[System.IO.File]::WriteAllText($TokenFile, $AccessToken)

# Enforce secure file permissions (Equivalent to chmod 600)
try {
    $Acl = Get-Acl $TokenFile
    # Disable inheritance and remove inherited rules
    $Acl.SetAccessRuleProtection($true, $false)
    # Grant Full Control to the current logged-in user only
    $User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, "FullControl", "Allow")
    $Acl.AddAccessRule($AccessRule)
    Set-Acl $TokenFile $Acl
    Write-Host "🔒 Session token secured natively (FullControl restricted to current user only)." -ForegroundColor Green
} catch {
    Write-Host "⚠️ Warning: Failed to apply strict ACLs to the token file. File remains at: $TokenFile" -ForegroundColor DarkYellow
}

Write-Host "🚀 Enclave developer session active. Token is valid for 12 hours." -ForegroundColor Green
