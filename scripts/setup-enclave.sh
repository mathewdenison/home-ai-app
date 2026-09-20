#!/bin/bash
set -e

# Ensure /usr/local/bin and /usr/bin are at the front of the PATH context
export PATH="/usr/local/bin:/usr/bin:$PATH"

# Enforce that this script must be run as root (or via sudo)
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run with root privileges (e.g. using sudo)."
    exit 1
fi

echo "🔒 [1/3] Validating Host Operating System Setup..."

# Detect previous failed or existing installations and offer to purge them
if [ -f "/usr/local/bin/k3s-uninstall.sh" ] || [ -f "/usr/local/bin/k3s-agent-uninstall.sh" ] || [ -f "/etc/systemd/system/k3s.service" ] || [ -f "/etc/systemd/system/k3s-agent.service" ] || mountpoint -q /var/lib/rancher/k3s || mount | grep -qE " /var/lib/kubelet| /var/lib/rancher| /opt/k3s-data| /var/lib/containerd"; then
    echo ""
    echo "⚠️ Warning: An existing or previous failed K3s/Zarf installation was detected!"
    echo "To apply the new /opt/k3s-data path, we must completely purge previous attempts."
    read -p "Would you like to purge previous K3s/Zarf installations and files now? [y/N]: " PURGE_CHOICE
    echo ""
    if [[ "$PURGE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "🧹 Purging previous K3s and Zarf cluster state..."
        
        if command -v zarf >/dev/null 2>&1; then
            echo "Running zarf destroy..."
            zarf destroy --confirm || true
        fi

        if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
            echo "Running k3s-uninstall.sh..."
            /usr/local/bin/k3s-uninstall.sh || true
        fi
        if [ -f "/usr/local/bin/k3s-agent-uninstall.sh" ]; then
            echo "Running k3s-agent-uninstall.sh..."
            /usr/local/bin/k3s-agent-uninstall.sh || true
        fi

        echo "Safely unmounting busy container filesystems and pod volumes..."
        for mount_point in $(mount | grep -E " /var/lib/kubelet| /var/lib/rancher| /opt/k3s-data| /var/lib/containerd" | awk '{print $3}' | sort -r); do
            echo "Unmounting busy resource: $mount_point"
            umount -l "$mount_point" || true
        done

        sed -i '\/var\/lib\/rancher\/k3s/d' /etc/fstab 2>/dev/null || true

        echo "Cleaning residual directories..."
        rm -rf /var/lib/rancher/k3s
        rm -rf /etc/rancher/k3s
        rm -rf /opt/k3s-data
        rm -rf /var/lib/kubelet
        rm -rf /var/lib/containerd
        
        systemctl daemon-reload
        
        if command -v semanage >/dev/null 2>&1; then
            echo "Removing custom SELinux file contexts..."
            semanage fcontext -d -e /var/lib/rancher/k3s "/opt/k3s-data" 2>/dev/null || true
        fi
        
        echo "✅ Previous state successfully purged! Ready for a fresh, clean install."
        echo ""
    fi
fi

echo "📦 [2/3] Initializing Zarf Local Cluster Layer..."

# Auto-detect and install Zarf CLI if missing from standard system path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v zarf >/dev/null 2>&1; then
    echo "🔍 Zarf CLI not found in system PATH. Checking local directory for binary..."
    ZARF_BIN=""
    if [ -f "./zarf" ]; then ZARF_BIN="./zarf"
    elif [ -f "$SCRIPT_DIR/zarf" ]; then ZARF_BIN="$SCRIPT_DIR/zarf"
    elif [ -f "$SCRIPT_DIR/../zarf" ]; then ZARF_BIN="$SCRIPT_DIR/../zarf"
    fi

    if [ -n "$ZARF_BIN" ]; then
        echo "🚀 Installing local Zarf binary to system directories..."
        cp "$ZARF_BIN" /usr/local/bin/zarf
        chmod +x /usr/local/bin/zarf
        cp "$ZARF_BIN" /usr/bin/zarf
        chmod +x /usr/bin/zarf
        hash -r
    else
        echo "❌ Error: Zarf is not installed, and no Linux 'zarf' binary was found."
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

# --- Hardened Payload Discovery Engine ---
SEARCH_PATHS=("$SCRIPT_DIR/.." "./" "/mnt/usb" "/mnt/media" "/mnt")
USB_ROOT=""

echo "🔍 Scanning for offline Zarf packages..."
for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ]; then
        abs_path=$(cd "$path" && pwd)
        echo "  - Checking: $abs_path"
        if ls "$abs_path"/zarf-package-*.tar.zst >/dev/null 2>&1; then
            USB_ROOT="$abs_path"
            echo "📂 Payload directory matched: $USB_ROOT"
            break
        fi
    fi
done

if [ -z "$USB_ROOT" ]; then
    echo "❌ Error: Could not locate any Sovereign Enclave Zarf packages (.tar.zst)."
    echo "Files found in current directory ($PWD):"
    ls -F
    exit 1
fi

JOIN_INFO_FILE="$USB_ROOT/cluster-join-info.env"

# PRE-INSTALLATION SELINUX AND MOUNT CONFIGURATION
echo "🔗 Configuring custom K3s directory with SELinux path equivalence..."
mkdir -p /opt/k3s-data /etc/rancher/k3s
if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -e /var/lib/rancher/k3s "/opt/k3s-data" || true
    restorecon -R -v /opt/k3s-data || true
else
    chcon -R -t container_var_lib_t /opt/k3s-data 2>/dev/null || true
fi

# Intelligently find local network IP and support multiple interfaces (e.g. direct link + switch)
VALID_IPS=()
for ip_entry in $(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1); do
    if [ "$ip_entry" != "127.0.0.1" ] && [[ "$ip_entry" != 172.17.* ]] && [[ "$ip_entry" != 10.42.* ]]; then
        if [[ "$ip_entry" =~ ^10\. ]] || [[ "$ip_entry" =~ ^192\.168\. ]] || [[ "$ip_entry" =~ ^172\. ]]; then
            VALID_IPS+=("$ip_entry")
        fi
    fi
done

LOCAL_IP=""
EXTERNAL_IP=""

if [ ${#VALID_IPS[@]} -gt 1 ]; then
    echo "🌐 Multiple network interfaces / IP addresses detected:"
    for i in "${!VALID_IPS[@]}"; do
        echo "  $((i + 1)): ${VALID_IPS[i]}"
    done
    echo ""
    read -p "Select the IP address to be used for INTERNAL cluster communication (Direct Link) [1-${#VALID_IPS[@]}, Default: 1]: " IP_SELECTION
    if [ -z "$IP_SELECTION" ]; then
        LOCAL_IP="${VALID_IPS[0]}"
    elif [[ "$IP_SELECTION" =~ ^[0-9]+$ ]] && [ "$IP_SELECTION" -le "${#VALID_IPS[@]}" ]; then
        LOCAL_IP="${VALID_IPS[$((IP_SELECTION - 1))]}"
    else
        echo "⚠️ Invalid selection. Defaulting to ${VALID_IPS[0]}"
        LOCAL_IP="${VALID_IPS[0]}"
    fi

    # Identify the external IP (for user ingress and TLS certificate SANs)
    for ip in "${VALID_IPS[@]}"; do
        if [ "$ip" != "$LOCAL_IP" ]; then
            EXTERNAL_IP="$ip"
            break
        fi
    done
else
    LOCAL_IP="${VALID_IPS[0]}"
fi

LOCAL_IP=$(echo "$LOCAL_IP" | tr -d '[:space:]')

# AIRGAPPED ROUTING COMPLIANCE
if ! ip route | grep -q "^default"; then
    echo "🌐 No default gateway found in routing table (required by K3s auto-detection)."
    ACTIVE_IFACE=""
    ACTIVE_IP=""
    for line in $(ip -o -4 addr show | awk '{print $2":"$4}'); do
        iface=$(echo "$line" | cut -d: -f1)
        ip=$(echo "$line" | cut -d: -f2 | cut -d/ -f1)
        if [ "$iface" != "lo" ] && [[ "$iface" != docker* ]] && [[ "$iface" != veth* ]] && [[ "$iface" != flano* ]] && [[ "$iface" != cni* ]] && [[ "$iface" != tailscale* ]]; then
            ACTIVE_IFACE="$iface"; ACTIVE_IP="$ip"; break
        fi
    done
    if [ -n "$ACTIVE_IFACE" ] && [ -n "$ACTIVE_IP" ]; then
        ip route add default via "$ACTIVE_IP" dev "$ACTIVE_IFACE" metric 1000 || true
    fi
fi

# SILENCE VERBOSE KERNEL NETWORKING CONSOLE SPAM
sysctl -w kernel.printk="3 4 1 7" >/dev/null 2>&1 || true



# Write native K3s configuration
cat <<EOF > /etc/rancher/k3s/config.yaml
data-dir: /opt/k3s-data
flannel-backend: vxlan
EOF
if [ -n "$LOCAL_IP" ] && [[ "$LOCAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "node-ip: \"$LOCAL_IP\"" >> /etc/rancher/k3s/config.yaml
fi

# Add TLS Subject Alternative Names (SANs) for secure client connection from the switch interface
if [ "$NODE_CHOICE" = "1" ]; then
    echo "tls-san:" >> /etc/rancher/k3s/config.yaml
    echo "  - \"home.internal-mesh.local\"" >> /etc/rancher/k3s/config.yaml
    echo "  - \"ai.internal-mesh.local\"" >> /etc/rancher/k3s/config.yaml
    echo "  - \"api.internal-mesh.local\"" >> /etc/rancher/k3s/config.yaml
    echo "  - \"dashboards.internal-mesh.local\"" >> /etc/rancher/k3s/config.yaml
    if [ -n "$EXTERNAL_IP" ]; then
        echo "  - \"$EXTERNAL_IP\"" >> /etc/rancher/k3s/config.yaml
    fi
fi

# Helper function to find a package by pattern
find_pkg() {
    local pattern="$1"
    find "$USB_ROOT" -maxdepth 1 -name "$pattern" -print -quit
}

if [ "$NODE_CHOICE" = "1" ]; then
    echo "Configuring as Beelink Gateway (Control Plane Server)..."
    init_pkg=$(ls "$USB_ROOT"/zarf-init-amd64-*.tar.zst 2>/dev/null | head -n 1)
    if [ -n "$init_pkg" ]; then cp "$init_pkg" ./zarf-init-amd64.tar.zst || true; fi
    
    mkdir -p /opt/k3s-data/zarf-tmp
    K3S_DATA_DIR=/opt/k3s-data zarf init --components k3s --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm

    echo "🚀 [3/3] Deploying Beelink Gateway AI Container Layer..."
    beelink_pkg=$(find_pkg "zarf-package-sovereign-ai-enclave-beelink-*.tar.zst")
    if [ -n "$beelink_pkg" ]; then 
        echo "Installing Beelink Software: $beelink_pkg"
        zarf package deploy "$beelink_pkg" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm
    else
        echo "⚠️ Warning: Beelink software package not found. Skipping."
    fi

    echo "🧠 Deploying DeepSeek-R1 Model Weights to Beelink..."
    model_70b=$(find_pkg "zarf-package-sovereign-ai-model-70b-gguf-*.tar.zst")
    if [ -n "$model_70b" ]; then
        echo "Installing 70B Heavy Model: $model_70b"
        zarf package deploy "$model_70b" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm
    fi
    model_14b_gguf=$(find_pkg "zarf-package-sovereign-ai-model-14b-gguf-*.tar.zst")
    if [ -n "$model_14b_gguf" ]; then
        echo "Installing 14B Fallback Model: $model_14b_gguf"
        zarf package deploy "$model_14b_gguf" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm
    fi

    JOIN_TOKEN=$(cat /opt/k3s-data/server/node-token 2>/dev/null || echo "PENDING")
    if [ -d "$USB_ROOT" ] && [ "$JOIN_TOKEN" != "PENDING" ] && [ -n "$LOCAL_IP" ]; then
        echo "SERVER_IP=$LOCAL_IP" > "$JOIN_INFO_FILE"
        echo "NODE_TOKEN=$JOIN_TOKEN" >> "$JOIN_INFO_FILE"
        sync || true
    fi
    echo "✅ Day-Zero Enclave Cluster Initialization Complete on Beelink Gateway!"

elif [ "$NODE_CHOICE" = "2" ]; then
    echo "Configuring as RTX 4090 Workstation (Worker Node)..."
    SERVER_IP=""; NODE_TOKEN=""
    if [ -f "$JOIN_INFO_FILE" ]; then source "$JOIN_INFO_FILE"; fi
    if [ -z "$SERVER_IP" ]; then
        read -p "Enter Beelink Gateway Server IP Address: " SERVER_IP
        read -p "Enter K3s Node Join Token: " NODE_TOKEN
    fi
    init_pkg=$(ls "$USB_ROOT"/zarf-init-amd64-*.tar.zst 2>/dev/null | head -n 1)
    if [ -n "$init_pkg" ]; then cp "$init_pkg" ./zarf-init-amd64.tar.zst || true; fi
    
    K3S_DATA_DIR=/opt/k3s-data zarf init --components k3s --set K3S_ARGS="agent --server https://${SERVER_IP}:6443 --token ${NODE_TOKEN}" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm

    echo "🚀 [3/3] Deploying RTX 4090 Workstation GPU AI Container Layer..."
    workstation_pkg=$(find_pkg "zarf-package-sovereign-ai-enclave-4090-*.tar.zst")
    if [ -n "$workstation_pkg" ]; then 
        echo "Installing 4090 Software: $workstation_pkg"
        zarf package deploy "$workstation_pkg" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm
    fi

    echo "🧠 Deploying DeepSeek-R1 14B AWQ Model Weights to Workstation..."
    model_14b_awq=$(find_pkg "zarf-package-sovereign-ai-model-14b-awq-*.tar.zst")
    if [ -n "$model_14b_awq" ]; then 
        echo "Installing 14B AWQ Weights: $model_14b_awq"
        zarf package deploy "$model_14b_awq" --tmpdir /opt/k3s-data/zarf-tmp --no-log-file --confirm
    fi

    echo "✅ Day-Zero Enclave Cluster Initialization Complete on RTX 4090 Node!"
else
    echo "❌ Error: Invalid selection."; exit 1
fi
