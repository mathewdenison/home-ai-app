# Sovereign Enclave: External Infrastructure & Hardware Prerequisites

This document outlines the configuration for physical hardware, local network setup, and router settings required to deploy and access your Sovereign Enclave. Since all resources are hosted within your secure home network, access is brokered internally or through your router-level Wireguard VPN.

---

## 🔑 1. Hardware Security Keys (YubiKeys)

To enforce branch protection and administrative security for codebase operations, you can employ **two physical FIDO2 keys** (e.g., YubiKey 5 Series).

### Step 1: Set Your Physical YubiKey PIN
By default, YubiKeys ship without a FIDO2 PIN. You must set a strong numeric PIN before creating credentials:
```powershell
# On Windows, you can use the native YubiKey Manager CLI or GUI
ykman fido reset   # Warning: This clears existing FIDO credentials on the key!
ykman fido change-pin
```

### Step 2: Generate Your Hardware-Bound Keys
Insert your **Primary YubiKey** into your workstation and execute:
```bash
ssh-keygen -t ed25519-sk -O resident -O verify-required -f ~/.ssh/id_yubikey_signing
```
*   `-O resident`: Permanently writes the key stub to the YubiKey's hardware chip, allowing you to re-import it on any clean computer using `ssh-add -K`.
*   `-O verify-required`: Commands the OS to block execution until you input your PIN and physically tap the gold contact on the YubiKey.

### Step 3: Register and Bind Git Commits
Add the contents of `~/.ssh/id_yubikey_signing.pub` to your GitHub account under **SSH & GPG Keys → New SSH Key (Signing Key)**. Enforce local signing:
```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_yubikey_signing.pub
git config --global commit.gpgsign true
```

---

## 🌐 2. Local Network & Router-Level VPN

Because this project is deployed within your secure internal home network and is not exposed to the public internet, remote access is managed natively via your router's built-in VPN gateway.

### Router-Level Wireguard Setup
Ensure your router is configured to broker secure incoming Wireguard client tunnels:
- **Tunnel Subnet**: Standard router VPN assignment (e.g., `10.8.0.0/24` or similar).
- **Access Policies**: Ensure Wireguard clients are permitted to route traffic into your primary LAN subnet (e.g., `192.168.1.0/24` or `10.0.0.0/24`) where the Beelink Gateway and RTX 4090 workstation reside.
- **Client Configuration**: Import the generated Wireguard client profile onto your remote workstations (laptop, phone) using the official Wireguard client.

### Internal DNS Resolution
To access the enclave services under their proper local domain names (such as `ai.internal-mesh.local`, `auth.internal-mesh.local`, and `dashboards.internal-mesh.local`):
- **Option A (Router DNS / Pi-hole)**: Add local DNS records pointing `*.internal-mesh.local` (or each host individually) to the static IP address of your Beelink Gateway node on your primary LAN.
- **Option B (Hosts File)**: For developer workloads on your admin machine, map the host entries directly:
  ```text
  [BEELINK_STATIC_LAN_IP] ai.internal-mesh.local auth.internal-mesh.local dashboards.internal-mesh.local api.internal-mesh.local
  ```

---

## 🔌 3. Physical Inter-Node Direct Link (Cat6 Link)

For ultra-low-latency model transfers, pipeline synchronization, and heartbeat monitoring between the Beelink Gateway and the RTX 4090 Workstation, configure a physical direct Ethernet link:

- Connect a dedicated Cat6 cable between a secondary Ethernet interface on both systems.
- Assign static IP addresses on an isolated subnet (e.g. `10.0.0.1` for the Beelink Gateway and `10.0.0.2` for the RTX 4090 Workstation).
- Verify that both Fedora 44 nodes can ping each other directly across this interface without traversing your primary home router.
