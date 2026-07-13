# Sovereign Enclave: External Infrastructure & Hardware Prerequisites

This document outlines the step-by-step configuration for all physical hardware, network perimeters, and cloud instances that live **outside** your Kubernetes stack. This setup is required to establish your cryptographic root of trust and secure access gateways.

---

## 🔑 1. Hardware Security Keys (YubiKeys)

To enforce military-grade branch protection and administrative security, you require **two physical FIDO2 keys** (e.g., YubiKey 5 Series).

### Step 1: Set Your Physical YubiKey PIN
By default, YubiKeys ship without a FIDO2 PIN. You must set a strong numeric PIN before creating resident credentials:
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

## 🌐 2. Public DNS & Domain Delegation

You require a public domain name (e.g., managed via Cloudflare, Namecheap, or AWS Route53) to serve as your entry-point gateway.

### Required DNS Zone Records
Once you obtain the public IPv4 address of your **Mesh VPS Coordinator** (e.g., `192.0.2.1`), add the following DNS records to your registrar control panel:

| Record Type | Name / Subdomain | Target Value | Purpose |
| :--- | :--- | :--- | :--- |
| **A Record** | `vpn.yourdomain.com` | `192.0.2.1` | Points SPA knocks & Headscale to VPS |
| **A Record** | `auth.yourdomain.com` | `192.0.2.1` | Directs user authentication traffic |
| **CNAME** | `*.internal-mesh.local` | (None / Internal Only) | Handled by internal Headscale MagicDNS |

---

## ☁️ 3. Public Cloud VPS Coordinator

Your mesh network needs a public-facing coordinator to orchestrate peer-to-peer WireGuard tunnels and broker OAuth handshakes.

### VPS Hardware Specifications
*   **Provider**: Any standard cloud (Hetzner, DigitalOcean, Linode, AWS).
*   **Profile**: Minimal (1 vCPU, 2GB RAM, 20GB SSD).
*   **OS**: Rocky Linux 9 (matches your STIG baseline).

### Host Firewall Ports configuration
Initially, block all inbound ports. Once SPA is set up, only the following ports are open:

| Protocol | Port | Source | Target Service |
| :--- | :--- | :--- | :--- |
| **UDP** | `62201` | `Any` | **fwknopd** (Single Packet Authorization daemon) |
| **TCP** | `443` | `Dynamic (SPA Opened)` | **Headscale / Caddy Ingress Gateway** |
| **UDP** | `51820` | `Any` | **WireGuard / Headscale P2P tunnel broker** |

---

## 🛡️ 4. Single Packet Authorization (SPA) on VPS

SPA ensures that port `443` is completely closed to the public internet, making your VPN entry point completely invisible to automated port-scanners.

### Step 1: Install `fwknopd` on VPS
```bash
sudo dnf install -y epel-release
sudo dnf install -y fwknop
```

### Step 2: Configure Server-Side Access rules (`/etc/fwknop/access.conf`)
Add an entry pinning access to your developer machine:
```text
SOURCE: ANY
REQUIRE_SOURCE_ADDRESS: N
KEY_BASE64: [GENERATED_BASE64_HMAC_KEY]
HMAC_KEY_BASE64: [GENERATED_BASE64_HMAC_KEY_2]
FW_ACCESS_TIMEOUT: 15
FORCE_PORT: TCP 443
```
*When a valid SPA packet is received, the VPS local iptables firewall opens port 443 for exactly 15 seconds to allow the Headscale tunnel to handshake, then instantly locks the port shut.*

---

## 🕸️ 5. Tailscale Mesh Tunnel & Tailnet Locking

To eliminate default trust of the central coordination server, we employ **Tailscale (Official)** alongside **Tailnet Locking**. This ensures that even if Tailscale's servers are compromised, no unauthorized devices can join your mesh.

### Step 0: Set Up Your Free Tailscale Account
1.  Navigate to **[https://login.tailscale.com/start](https://login.tailscale.com/start)** in your web browser.
2.  Select your preferred **Identity Provider (IdP)** to sign up (we recommend **Google OAuth** or **GitHub** to align with your existing developer and Authentik social federation).
3.  Once signed in, you are automatically assigned your personal **Tailnet** domain.

### Step 1: Enable Tailnet Lock in the Tailscale Admin Console
1.  Navigate to your **Tailscale Admin Console** > **Settings** > **General**.
2.  Scroll down to the **Tailnet Lock** section and select **Enable Tailnet Lock**.

### Step 2: Extract Your Signing Node Keys
On your primary administrative computer (or Beelink Gateway node), retrieve its Tailnet Lock public key:
```bash
tailscale lock
```
Look for: `This node's tailnet-lock key: tlpub:1234abc...`

### Step 3: Initialize Tailnet Lock
From your administrative node, initialize the lock with your trusted key (you should include both your admin workstation and your Beelink Gateway key to ensure redundancy):
```bash
tailscale lock init tlpub:ADMIN_KEY_HERE tlpub:BEELINK_KEY_HERE --gen-disablements 2
```
*Save the generated disablement/recovery secrets in a secure physical location (e.g., your lockbox alongside your OpenBao unseal shards).*

### Step 4: Signing New Nodes into the Enclave
When your 4090 Workstation or any new node registers with your account, it will be instantly locked out (blocked from communicating with your mesh) until you cryptographically sign it.
To approve and sign a node:
1.  Obtain the new node's **Node Key** (from the Admin Console or by running `tailscale status` on the node).
2.  From your trusted signing admin node, run:
    ```bash
    tailscale lock sign nodekey:abcdef123456...
    ```

---

## 🔄 6. Host-Level Privacy VPN Integration (Home IP Protection)

To completely hide and protect your home IP address from both your AWS Lightsail VPS and the public internet, we install a **Commercial Privacy VPN (Mullvad VPN)** directly at the **Host OS level** on the Beelink Gateway (and optionally the 4090 Workstation).

By establishing your privacy VPN tunnel at the Host OS level *before* starting Tailscale, **all outbound host traffic—including Tailscale’s connection to your VPS—is routed through Mullvad first**. If an attacker compromises your VPS, they will only see a Mullvad exit IP, never your home residential IP!

### Step 1: Install the Mullvad VPN CLI on your Rocky Linux Host Node
Run the standard installation scripts directly on your host machines:
```bash
# Add the official Mullvad repository and install the daemon
sudo dnf config-manager --add-repo https://repository.mullvad.net/rpm/stable/mullvad.repo
sudo dnf install -y mullvad-vpn
```

### Step 2: Configure Local LAN Sharing (Cat6 Direct Link Protection)
Because Mullvad is a strict zero-leak VPN, its default firewall blocks all local network traffic. You **must** enable LAN sharing to ensure your Beelink server can still communicate with your 4090 Workstation over your physical Cat6 direct line (`10.0.0.x` subnet):
```bash
# Enable local subnet visibility and local routing sharing
mullvad lan set allow
```

### Step 3: Enable the Strict VPN Kill-Switch
To ensure your real home IP address *never* leaks to your VPS or the internet if the VPN tunnel drops:
```bash
mullvad lockdown-mode set on
```

### Step 4: Authenticate and Connect
```bash
# Set your account number
mullvad account login [YOUR_MULLVAD_ACCOUNT_NUMBER]

# Pick a target country (e.g. US or Switzerland for privacy) and connect
mullvad relay set location us nyc
mullvad connect
```

### Step 5: Start Tailscale over the VPN
Once the Mullvad tunnel interface (`mullvad-wg`) is active, start your Tailscale service. Tailscale will automatically sense the default route, establish its encrypted WireGuard connection *over* the Mullvad interface, and handshake securely with your AWS VPS.
*   **Validation**: Run `tailscale status` on your VPS or log in to the admin panel. The client IP displayed for your Beelink server will be a **Mullvad VPN Exit IP address**, proving that your home residential location is completely shielded!
*   Any Kubernetes pod workloads running on the Beelink gateway will also automatically route their internet egress via Mullvad natively, completely protecting model downloads and web search scrapes without needing complex container-level proxies.
