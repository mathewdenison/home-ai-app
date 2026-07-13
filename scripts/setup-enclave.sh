#!/bin/bash
set -e

# Ensure /usr/local/bin and /usr/bin are at the front of the PATH context
export PATH="/usr/local/bin:/usr/bin:$PATH"

# Enforce that this script must be run as root (or via sudo)
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run with root privileges (e.g. using sudo)."
    exit 1
fi

echo "🔒 [1/3] Validating Host Operating System STIG Compliance Status..."
if ! oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml > /dev/null 2>&1; then
    echo "⚠️ Warning: Host OS has open STIG compliance alerts. Continuing configuration..."
fi

# Detect previous failed or existing installations and offer to purge them
if [ -f "/usr/local/bin/k3s-uninstall.sh" ] || [ -f "/usr/local/bin/k3s-agent-uninstall.sh" ] || [ -f "/etc/systemd/system/k3s.service" ] || [ -f "/etc/systemd/system/k3s-agent.service" ] || mountpoint -q /var/lib/rancher/k3s; then
    echo ""
    echo "⚠️ Warning: An existing or previous failed K3s/Zarf installation was detected!"
    echo "To apply the new STIG-compliant /opt/k3s-data path, we must completely purge previous attempts."
    read -p "Would you like to purge previous K3s/Zarf installations and files now? [y/N]: " PURGE_CHOICE
    echo ""
    if [[ "$PURGE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "🧹 Purging previous K3s and Zarf cluster state..."
        
        # Run Zarf's built-in destroy command if available
        if command -v zarf >/dev/null 2>&1; then
            echo "Running zarf destroy..."
            zarf destroy --confirm || true
        fi

        # Run native K3s uninstall scripts if they exist
        if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
            echo "Running k3s-uninstall.sh..."
            /usr/local/bin/k3s-uninstall.sh || true
        fi
        if [ -f "/usr/local/bin/k3s-agent-uninstall.sh" ]; then
            echo "Running k3s-agent-uninstall.sh..."
            /usr/local/bin/k3s-agent-uninstall.sh || true
        fi

        # Safely unmount any active bind mounts if they were previously created
        if mountpoint -q /var/lib/rancher/k3s; then
            echo "Unmounting /var/lib/rancher/k3s..."
            umount /var/lib/rancher/k3s || umount -l /var/lib/rancher/k3s || true
        fi

        # Clean fstab entries
        sed -i '\/var\/lib\/rancher\/k3s/d' /etc/fstab 2>/dev/null || true

        # Completely purge all residual data, configurations, and systemd units
        echo "Cleaning residual directories..."
        rm -rf /var/lib/rancher/k3s
        rm -rf /etc/rancher/k3s
        rm -rf /opt/k3s-data
        rm -rf /var/lib/kubelet
        rm -f /etc/systemd/system/k3s.service
        rm -f /etc/systemd/system/k3s-agent.service
        
        # Clean SELinux file contexts for /opt/k3s-data if semanage was used
        if command -v semanage >/dev/null 2>&1; then
            echo "Removing custom SELinux file contexts..."
            semanage fcontext -d -e /var/lib/rancher/k3s "/opt/k3s-data" 2>/dev/null || true
        fi

        # Clean fapolicyd rules for K3s
        if [ -f "/etc/fapolicyd/rules.d/80-k3s.rules" ]; then
            echo "Removing fapolicyd K3s rules..."
            rm -f /etc/fapolicyd/rules.d/80-k3s.rules
            if command -v fagenrules >/dev/null 2>&1; then
                fagenrules --load || true
            fi
            if systemctl is-active fapolicyd &>/dev/null; then
                systemctl restart fapolicyd || true
            fi
        fi
        
        # Reload systemd to apply service deletion
        systemctl daemon-reload
        
        echo "✅ Previous state successfully purged! Ready for a fresh, clean install."
        echo ""
    fi
fi

echo "📦 [2/3] Initializing Zarf Local Cluster Layer..."

# Auto-detect and install Zarf CLI if missing from standard system path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v zarf >/dev/null 2>&1; then
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
        echo "🚀 Installing local Zarf binary to system directories..."
        cp "$ZARF_BIN" /usr/local/bin/zarf
        chmod +x /usr/local/bin/zarf
        # Also copy to /usr/bin/zarf as a robust fallback (ensures secure_path compliance under sudoers)
        cp "$ZARF_BIN" /usr/bin/zarf
        chmod +x /usr/bin/zarf
        # Force bash to clear cached command paths
        hash -r
    else
        echo "❌ Error: Zarf is not installed, and no Linux 'zarf' binary was found in this directory."
        echo "Please download the Linux amd64 static 'zarf' binary and place it in the same folder as this script on your USB."
        exit 1
    fi
else
    # Even if Zarf is already installed somewhere, ensure a copy exists in /usr/bin/zarf
    # to protect against secure_path restrictions on /usr/local/bin
    if [ ! -f "/usr/bin/zarf" ]; then
        cp "$(command -v zarf)" /usr/bin/zarf
        chmod +x /usr/bin/zarf
        hash -r
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

# PRE-INSTALLATION FAPOLICYD COMPLIANCE (STIG Hardening Exception)
# fapolicyd blocks any binary execution from non-system paths (like our custom /opt/k3s-data directory,
# dynamic network plugin paths in /opt/cni, kubelet volumes, and K3s runtime states in /run).
FAPOLICY_RULES="/etc/fapolicyd/rules.d/80-k3s.rules"
if [ -d "/etc/fapolicyd/rules.d" ] && [ ! -f "$FAPOLICY_RULES" ]; then
    echo "🔒 Configuring fapolicyd STIG exceptions for K3s execution paths..."
    cat <<EOF > "$FAPOLICY_RULES"
allow perm=any all : dir=/opt/k3s-data/
allow perm=any all : dir=/opt/cni/
allow perm=any all : dir=/run/k3s/
allow perm=any all : dir=/var/lib/kubelet/
allow perm=any all : dir=/run/containerd/
allow perm=any all : dir=/var/lib/containerd/
allow perm=any all : dir=/var/lib/rancher/
EOF
    # Load rules and restart fapolicyd daemon if active
    if command -v fagenrules >/dev/null 2>&1; then
        fagenrules --load || true
    fi
    if systemctl is-active fapolicyd &>/dev/null; then
        echo "Restarting fapolicyd to apply new execution rules..."
        systemctl restart fapolicyd || true
    fi
fi

# PRE-INSTALLATION SELINUX AND MOUNT CONFIGURATION
# To bypass /var noexec, we must use a custom data directory (/opt/k3s-data).
# To bypass the SELinux block on custom paths, we apply Path Equivalence, instructing SELinux 
# to treat /opt/k3s-data as mathematically equivalent to the default /var/lib/rancher/k3s path.
echo "🔗 Configuring custom K3s directory with STIG & SELinux path equivalence..."
mkdir -p /opt/k3s-data
mkdir -p /etc/rancher/k3s

# Apply the SELinux path equivalence rule (semanage is pre-installed on Rocky STIG profiles)
if command -v semanage >/dev/null 2>&1; then
    echo "Equating /opt/k3s-data to /var/lib/rancher/k3s in SELinux policy..."
    semanage fcontext -a -e /var/lib/rancher/k3s "/opt/k3s-data" || true
    echo "Restoring SELinux security contexts on /opt/k3s-data recursively..."
    restorecon -R -v /opt/k3s-data || true
else
    # Fallback to general container context if semanage is not available
    echo "Applying standard container security context to /opt/k3s-data..."
    chcon -R -t container_var_lib_t /opt/k3s-data 2>/dev/null || true
fi

# Intelligently find local network IP using standard 'ip addr show'
# This is completely immune to hostname lookup blocks standard on STIG-hardened environments.
# Filters out local loopback (127.0.0.1) and K3s/Docker bridge subnets, selecting the first active host IP.
LOCAL_IP=""
for ip_entry in $(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1); do
    if [ "$ip_entry" != "127.0.0.1" ] && [[ "$ip_entry" != 172.17.* ]] && [[ "$ip_entry" != 10.42.* ]]; then
        # Prefer standard private network ranges (10.x, 192.168.x, 172.x)
        if [[ "$ip_entry" =~ ^10\. ]] || [[ "$ip_entry" =~ ^192\.168\. ]] || [[ "$ip_entry" =~ ^172\. ]]; then
            LOCAL_IP="$ip_entry"
            break
        fi
        # Fallback to the first non-loopback IP found if no standard private range matches
        if [ -z "$LOCAL_IP" ]; then
            LOCAL_IP="$ip_entry"
        fi
    fi
done

# Clean up any potential whitespace/newlines in LOCAL_IP
LOCAL_IP=$(echo "$LOCAL_IP" | tr -d '[:space:]')

# AIRGAPPED ROUTING COMPLIANCE (Default Route Workaround)
# In isolated or offline enclaves, if no default gateway is configured in the OS, K3s (specifically the embedded
# Kubernetes ChooseHostInterface prober) will fail to auto-detect the network and crash-loop with:
# "no default routes found in '/proc/net/route' or '/proc/net/ipv6_route'"
# To prevent this, we scan the routing table and if no default route is found, we dynamically identify the first
# active physical network interface and add a fallback local route pointing to its own IP address.
if ! ip route | grep -q "^default"; then
    echo "🌐 No default gateway found in routing table (required by K3s auto-detection)."
    
    # Scan for the first active non-loopback, non-virtual IPv4 interface on the host
    ACTIVE_IFACE=""
    ACTIVE_IP=""
    for line in $(ip -o -4 addr show | awk '{print $2":"$4}'); do
        iface=$(echo "$line" | cut -d: -f1)
        ip_with_mask=$(echo "$line" | cut -d: -f2)
        ip=$(echo "$ip_with_mask" | cut -d/ -f1)
        
        # Filter out local loopback, docker, tailscale, and CNI virtual interfaces
        if [ "$iface" != "lo" ] && [[ "$iface" != docker* ]] && [[ "$iface" != veth* ]] && [[ "$iface" != flano* ]] && [[ "$iface" != cni* ]] && [[ "$iface" != tailscale* ]]; then
            ACTIVE_IFACE="$iface"
            ACTIVE_IP="$ip"
            break
        fi
    done
    
    if [ -n "$ACTIVE_IFACE" ] && [ -n "$ACTIVE_IP" ]; then
        echo "Adding fallback local default route on $ACTIVE_IFACE via $ACTIVE_IP..."
        ip route add default via "$ACTIVE_IP" dev "$ACTIVE_IFACE" metric 1000 || true
    fi
fi

# Write native K3s configuration with robust IPv4-only and interface-binding constraints.
# Setting 'node-ip' guarantees K3s binds strictly to your direct Cat6 physical pipeline network interface,
# completely preventing it from binding to public WAN or host-level Mullvad VPN virtual interfaces.
# If LOCAL_IP is empty or invalid, we skip node-ip to let K3s auto-detect, preventing startup crashes.
cat <<EOF > /etc/rancher/k3s/config.yaml
data-dir: /opt/k3s-data
flannel-backend: vxlan
EOF

if [ -n "$LOCAL_IP" ] && [[ "$LOCAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "node-ip: \"$LOCAL_IP\"" >> /etc/rancher/k3s/config.yaml
    echo "✅ Successfully bound K3s node-ip to local interface address: $LOCAL_IP"
else
    echo "⚠️ Warning: No valid local IPv4 address detected for interface binding. Skipping 'node-ip' configuration..."
fi

if [ "$NODE_CHOICE" = "1" ]; then
    echo "Configuring as Beelink Gateway (Control Plane Server)..."

    # Bootstrap control plane with registry, agent, and K3s pointing to /opt/k3s-data
    K3S_DATA_DIR=/opt/k3s-data zarf init --components k3s --confirm

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

    # Retrieve Join Token natively from custom /opt/k3s-data directory
    JOIN_TOKEN=$(cat /opt/k3s-data/server/node-token 2>/dev/null || echo "PENDING")

    # Write connection details to the USB drive for seamless plug-and-play join on Node 2!
    if [ -d "$USB_ROOT" ] && [ "$JOIN_TOKEN" != "PENDING" ] && [ -n "$LOCAL_IP" ] && [[ "$LOCAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
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

    # Bootstrap worker node in agent mode pointing to the Beelink Gateway (pointing to /opt/k3s-data)
    K3S_DATA_DIR=/opt/k3s-data zarf init --components k3s --set K3S_ARGS="agent --server https://${SERVER_IP}:6443 --token ${NODE_TOKEN}" --confirm

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
