#!/bin/bash
set -e

echo "🔒 [1/3] Validating Host Operating System STIG Compliance Status..."
if ! oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml > /dev/null 2>&1; then
    echo "⚠️ Warning: Host OS has open STIG compliance alerts. Continuing configuration..."
fi

echo "📦 [2/3] Initializing Zarf Local Cluster Layer..."

# Auto-detect and install Zarf CLI if missing from system path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v zarf &> /dev/null; then
    echo "🔍 Zarf CLI not found in system PATH. Checking local directory for binary..."
    
    # Check if a local 'zarf' binary exists in current dir (on USB) or script's directory
    ZARF_BIN=""
    if [ -f "./zarf" ]; then
        ZARF_BIN="./zarf"
    elif [ -f "$SCRIPT_DIR/zarf" ]; then
        ZARF_BIN="$SCRIPT_DIR/zarf"
    elif [ -f "$SCRIPT_DIR/../zarf" ]; then
        ZARF_BIN="$SCRIPT_DIR/../zarf"
    fi

    if [ -n "$ZARF_BIN" ]; then
        echo "🚀 Installing local Zarf binary to /usr/local/bin/zarf..."
        sudo cp "$ZARF_BIN" /usr/local/bin/zarf
        sudo chmod +x /usr/local/bin/zarf
    else
        echo "❌ Error: Zarf is not installed, and no Linux 'zarf' binary was found in this directory."
        echo "Please download the Linux amd64 static 'zarf' binary and place it in the same folder as this script on your USB."
        exit 1
    fi
fi

# Ask user for Node Type Selection
echo ""
echo "Select the Sovereign Enclave Node Type to set up on this machine:"
echo "1) Beelink Gateway (Control Plane / K3s Server)"
echo "2) RTX 4090 Workstation (Worker Node / K3s Agent)"
read -p "Enter choice [1-2]: " NODE_CHOICE
echo ""

# Find USB Root directory for configuration sharing
USB_ROOT="/mnt/usb"
if [ ! -d "$USB_ROOT" ]; then
    # Fallback to the parent of the scripts folder
    USB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

JOIN_INFO_FILE="$USB_ROOT/cluster-join-info.env"

if [ "$NODE_CHOICE" = "1" ]; then
    echo "Configuring as Beelink Gateway (Control Plane Server)..."
    
    # Bootstrap control plane with registry, agent, etc.
    zarf init --confirm

    echo "🚀 [3/3] Deploying Beelink Gateway AI Container Layer..."
    # Find and deploy Beelink-specific package
    beelink_pkg=$(ls zarf-package-sovereign-ai-enclave-beelink-*.tar.zst 2>/dev/null | head -n 1)
    if [ -n "$beelink_pkg" ] && [ -f "$beelink_pkg" ]; then
        echo "Deploying Beelink Gateway package: $beelink_pkg"
        zarf package deploy "$beelink_pkg" --confirm
    else
        echo "❌ Error: Beelink Zarf package (zarf-package-sovereign-ai-enclave-beelink-*.tar.zst) not found!"
        exit 1
    fi

    # Apply Cluster-Level GitOps Configurations (Server/Control-Plane only)
    kubectl apply -f ../gitops/base/network-policy.yaml
    kubectl apply -f ../gitops/base/observability-dashboards.yaml

    # Retrieve Join Token and IP
    JOIN_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "PENDING")
    
    # Intelligently find local network IP (preferring 10.x, 192.x, or 172.x subnets)
    LOCAL_IP=""
    for ip in $(hostname -I); do
        if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^172\. ]]; then
            LOCAL_IP="$ip"
            break
        fi
    done
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(hostname -I | awk '{print $1}')
    fi

    # Write connection details to the USB drive for seamless plug-and-play join on Node 2!
    if [ -d "$USB_ROOT" ] && [ "$JOIN_TOKEN" != "PENDING" ]; then
        echo "Writing cluster join configuration to USB drive for the worker node..."
        echo "SERVER_IP=$LOCAL_IP" > "$JOIN_INFO_FILE"
        echo "NODE_TOKEN=$JOIN_TOKEN" >> "$JOIN_INFO_FILE"
        # Sync changes to ensure it's written completely to physical media
        sync || true
    fi

    echo ""
    echo "=========================================================================="
    echo "✅ Day-Zero Enclave Cluster Initialization Complete on Beelink Gateway!"
    echo "=========================================================================="
    echo "The cluster join configuration has been written directly to your USB drive!"
    echo "Simply plug this USB into your RTX 4090 Workstation and run the same script."
    echo "=========================================================================="
    echo "Server IP Address: $LOCAL_IP"
    echo "K3s Node Join Token: $JOIN_TOKEN"
    echo "=========================================================================="

elif [ "$NODE_CHOICE" = "2" ]; then
    echo "Configuring as RTX 4090 Workstation (Worker Node)..."
    
    SERVER_IP=""
    NODE_TOKEN=""

    # Attempt Plug-and-Play auto-discovery of connection details from USB
    if [ -f "$JOIN_INFO_FILE" ]; then
        echo "🔌 Found plug-and-play join configuration on USB at $JOIN_INFO_FILE!"
        source "$JOIN_INFO_FILE"
        echo "Auto-detected Server IP: $SERVER_IP"
    fi

    # Fallback to interactive prompts if join info is missing or incomplete
    if [ -z "$SERVER_IP" ] || [ -z "$NODE_TOKEN" ]; then
        echo "⚠️ Join configuration not found on USB. Falling back to manual entry..."
        read -p "Enter Beelink Gateway Server IP Address: " SERVER_IP
        read -p "Enter K3s Node Join Token: " NODE_TOKEN
        echo ""
    fi

    if [ -z "$SERVER_IP" ] || [ -z "$NODE_TOKEN" ]; then
        echo "❌ Error: Both Server IP and Node Join Token are required to join the cluster."
        exit 1
    fi

    # Network verification check before starting installation work!
    echo "🔗 Verifying network connectivity to Beelink Gateway ($SERVER_IP:6443)..."
    if ! timeout 5 bash -c "cat < /dev/null > /dev/tcp/${SERVER_IP}/6443" 2>/dev/null; then
        echo "❌ Error: Cannot reach the Beelink Gateway at $SERVER_IP on port 6443."
        echo "Please verify before retrying:"
        echo "  1. The Beelink Gateway is powered on and K3s is running."
        echo "  2. The direct Cat6 ethernet cable is plugged into both nodes."
        echo "  3. The local network interfaces are active and configured with IPs in the same subnet (e.g. 10.0.0.x)."
        exit 1
    else
        echo "✅ Network connectivity verified!"
    fi

    # Bootstrap worker node in agent mode pointing to the Beelink Gateway
    sudo zarf init --components k3s --set K3S_ARGS="agent --server https://${SERVER_IP}:6443 --token ${NODE_TOKEN}" --confirm

    echo "🚀 [3/3] Deploying RTX 4090 Workstation GPU AI Container Layer..."
    # Find and deploy 4090-specific package
    workstation_pkg=$(ls zarf-package-sovereign-ai-enclave-4090-*.tar.zst 2>/dev/null | head -n 1)
    if [ -n "$workstation_pkg" ] && [ -f "$workstation_pkg" ]; then
        echo "Deploying RTX 4090 package: $workstation_pkg"
        zarf package deploy "$workstation_pkg" --confirm
    else
        echo "❌ Error: RTX 4090 Workstation Zarf package (zarf-package-sovereign-ai-enclave-4090-*.tar.zst) not found!"
        exit 1
    fi

    echo ""
    echo "=========================================================================="
    echo "✅ Day-Zero Enclave Cluster Initialization Complete on RTX 4090 Node!"
    echo "This worker is now fully joined to the Beelink Gateway control plane."
    echo "=========================================================================="

else
    echo "❌ Error: Invalid selection."
    exit 1
fi
