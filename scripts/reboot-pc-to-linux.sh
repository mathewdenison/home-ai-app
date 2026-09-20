#!/bin/bash
# reboot-pc-to-linux.sh - Remote Operating System Boot Override Utility
# This script runs on the Beelink Gateway as root and instructs your dual-boot
# PC node (connected via the direct Cat6 link) to reboot natively into Fedora Linux.

# Enforce root execution so it can access the root SSH key (/root/.ssh/id_beelink_to_pc)
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run as root (using sudo) to access administrative SSH keys."
    exit 1
fi

# CONFIGURATION - CHANGE THESE TO MATCH YOUR ENVIRONMENT
DEFAULT_USER="mat"                          # Default Windows administrator username
WINDOWS_IP="10.0.0.2"                        # Your Windows PC's direct link IP
KEY_PATH="/root/.ssh/id_beelink_to_pc"       # Path to root's private key

# Allow overriding the username via environment variable, otherwise prompt or fallback
WINDOWS_USER="${WINDOWS_USER}"
if [ -z "$WINDOWS_USER" ]; then
    if [ -t 0 ]; then
        read -t 5 -p "Enter Windows Administrator Username [Default: $DEFAULT_USER]: " INPUT_USER
        WINDOWS_USER="${INPUT_USER:-$DEFAULT_USER}"
    else
        WINDOWS_USER="$DEFAULT_USER"
    fi
fi
# Clean up any trailing space or newline
WINDOWS_USER=$(echo "$WINDOWS_USER" | tr -d '[:space:]')

# Default Fedora boot GUID (will be overridden by $1 if provided)
FEDORA_GUID="{your-fedora-guid-here}"

# Allow overriding the GUID via command-line argument
if [ -n "$1" ]; then
    FEDORA_GUID="$1"
fi

# Validate that the user replaced the placeholder GUID
if [[ "$FEDORA_GUID" == *your-fedora-guid-here* ]]; then
    echo "❌ Error: Fedora GUID not configured!"
    echo "Please retrieve your Fedora Boot GUID from Windows (using 'bcdedit /enum firmware')"
    echo "and either pass it as an argument or configure it inside this script."
    echo ""
    echo "Usage: sudo $0 {FEDORA-BOOT-GUID}"
    exit 1
fi

# Check if the private key exists
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ Error: Private key not found at: $KEY_PATH"
    echo "Ensure you generated the SSH key as root under that exact filename."
    exit 1
fi

echo "🔌 Pinging Windows PC at $WINDOWS_IP over direct link..."
if ! ping -c 1 -W 2 "$WINDOWS_IP" >/dev/null 2>&1; then
    echo "❌ Error: Cannot reach Windows PC at $WINDOWS_IP."
    echo "Please check that your direct Cat6 cable is connected and the IP is active."
    exit 1
fi

echo "🚀 Issuing remote boot override command to $WINDOWS_IP via SSH..."
echo "🔒 Target: Boot sequence set to Fedora ($FEDORA_GUID)"

# Execute the remote boot sequence setting and immediate shutdown/reboot via Windows PowerShell
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${WINDOWS_USER}@${WINDOWS_IP}" \
  "powershell.exe -Command \"Start-Process bcdedit -ArgumentList '/bootsequence $FEDORA_GUID' -NoNewWindow -Wait; shutdown /r /t 0 /f\""

if [ $? -eq 0 ]; then
    echo "✅ Remote boot command executed successfully! Your PC is now rebooting into Fedora."
else
    echo "❌ Error: Remote SSH boot override command failed."
    exit 1
fi
