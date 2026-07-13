# Sovereign Enclave: Master Developer Operations Manual (`README.md`)

This repository is the single source of truth, cryptographic root, and declarative blueprint for bootstrapping, securing, and maintaining a high-performance, private, multi-node AI inference cluster. 

The architecture enforces **Rocky Linux 9 (DISA STIG)** kernel profiles, **K3s micro-orchestration**, **gVisor user-space kernel containment**, **Single Packet Authorization (SPA)** network perimeters, **Tailscale Tailnet Locking** (cryptographically removing VPS/Coordination trust), **Zarf immutable hermetic packages**, **Outbound SOCKS5 Double-Proxy Egress** (to completely hide and protect home IP addresses), and an **unattended Kickstart bare-metal installer**.

---

## 1. System Architecture Topology

[ Local Terminal: Run gcert ] ──( 1. SPA Port Knock )──► [ Public Cloud VPS Gateway (vpn.yourdomain.com) ]
│ (Opens Port 443 for 15 Secs)
▼
[ Tailscale Mesh Tunnel (Cryptographically Verified via Tailnet Lock) ]
│ (Direct P2P Encrypted Loop)
▼
[ Beelink Gateway Node ]
│
▼
[ Authentik Gateway ] ──► (Triggers Device Flow Code)
│
▼
[ Opens Local Browser ] ──► (Validates via Google OAuth)
│
▼
[ Issues 12-Hour Token ] ──► [ Drops back into CLI RAM ]

Outbound Traffic:
[ Pod Workloads (Open WebUI/vLLM) ] ──► [ Gost Local Double Proxy ] ──► (Encrypted Mesh) ──► [ AWS Lightsail SOCKS5 (Proxy 1) ] ──► [ Commercial SOCKS5 VPN (Proxy 2) ] ──► [ Public Internet ] (Home IP 100% Protected)


### Physical Link Layer Layout
+───────────────────────────────────────+   +───────────────────────────────────────+
|   BEELINK GATEWAY (Rocky Linux 9)     |   |    4090 WORKER (Rocky Linux 9)        |
|         (100.64.0.1 / 10.0.0.1)       |   |         (100.64.0.2 / 10.0.0.2)       |
|                                       |   |                                       |
|  • Pre-Hardened DISA STIG Baseline    |   |  • Pre-Hardened DISA STIG Baseline    |
|  • K3s Control Plane / Leader Node    |   |  • K3s Worker / Inference Node        |
|  • OpenBao Memory-Mapped Secret Vault |   |  • High-Throughput vLLM Engine        |
|  • Authentik SSO Identity Manager     |   |  • Isolated IPC /dev/shm Overrides   |
|  • Open WebUI Panel + SearXNG Engine  |   |  • Active DCGM GPU Telemetry Hook     |
+───────────────────────────────────────+   +───────────────────────────────────────+
▲                                                           ▲
└═══════════════════════ Direct Cat6 Wire ══════════════════┘
(Private 10.0.0.x / No Gateway)


---

## 2. Access, Cryptography & Authentication Matrix

| Attribute | Tier 1: Device Mesh Layer | Tier 2: Developer / User Access | Tier 3: Cluster Administrator |
| :--- | :--- | :--- | :--- |
| **Target Identity** | Authorized Hardware Nodes | Your Wife & Programmatic CLIs | You (The System Owner) |
| **Authentication** | WireGuard Public Key Exchanges + Manual Phone Token Verification | Google OAuth Social Login Federation (via Authentik) | Multi-Stage: SPA Firewall Bypass + Google Auth + **Physical FIDO2 Hardware Key Touch** |
| **Ingress Gate** | Headscale Control Plane | Open WebUI Frontend / LiteLLM API | Host OS Kernel / OpenBao Secret Vault |
| **Token Lifecycles** | Permanent Hardware Key Pinning | Web UI: 30-Day Session Cookie<br>CLI: 12-Hour OAuth Device Token | Explicit Validation per administrative session |
| **Code Signing** | N/A | Rejected by Branch Protection Policy | **Mandatory:** Hardware-backed `ed25519-sk` YubiKey verification on every commit |

---

## 3. Monorepo Directory Layout

This repository isolates immutable application binaries (Zarf packaging blueprints) from declarative orchestration states (GitOps). Massive tarball payloads (`*.tar.zst`), local keys, and unseal secrets must never be pushed to version control.

```text
.
├── README.md                  # Comprehensive developer setup documentation and master strategy
├── versions.yaml              # Single source of truth for all dependent package and image versions
├── scripts/
│   ├── bake-usb.sh            # Automated workstation utility to flash the Kickstart-injected OS installer
│   ├── setup-enclave.sh       # Day-Zero automated cluster installation and bootstrap script
│   ├── sync-versions.py       # Cross-platform Python utility to synchronize versions.yaml across all manifests
│   ├── fetch-dashboards.py    # Python utility to pre-compile and adapt official community dashboards offline
│   ├── gcert                  # Token hydration tool (OAuth 2.0 Device Code Flow + SPA knock) - Linux/macOS
│   └── gcert.ps1              # Token hydration tool (OAuth 2.0 Device Code Flow + SPA knock) - Windows PowerShell
├── bootstrap/
│   ├── enclave-kickstart.cfg  # Unattended automation Kickstart blueprint for Rocky Linux 9 STIG setup
│   ├── zarf-beelink.yaml      # Zarf airgap package mapping Beelink control plane dependencies
│   └── zarf-4090.yaml         # Zarf airgap package mapping 4090 worker GPU dependencies
├── gitops/
│   ├── base/                  # Hardened Kubernetes workload definitions
│   │   ├── enclave-apps.yaml  
│   │   ├── network-policy.yaml
│   │   └── observability-dashboards.yaml # Unified Grafana telemetry dashboards (Beelink & 4090 GPU)
│   └── config/
│       └── auth-settings.yaml # Non-sensitive identity provider configuration parameters
└── .github/
    └── workflows/
        └── gitops-sync.yml    # Outbound GitOps deployment continuous delivery workflow
```

---

## 4. Hardware Security Token & Git Integrity Provisioning
Before executing any commands against remote cloud instances or committing layout alterations to this repository, you must anchor your cryptographic identity to your hardware security modules.

1. Generating Hardware-Bound SSH Signing Keys
Run this on your primary developer workstation with your primary YubiKey inserted:

```bash
ssh-keygen -t ed25519-sk -O resident -O verify-required -f ~/.ssh/id_yubikey_signing
```
- `-O resident`: Stores the reference pointers permanently on the YubiKey's security chip.
- `-O verify-required`: Forces the local host OS to demand your physical PIN sequence and contact tap upon execution.

2. Establishing the Emergency Recovery Path
Because a resident key cannot be software-cloned to a backup device, you must configure a dual-path recovery schema. Pin an identical secondary backup YubiKey to your main credentials accounts, and generate an airgapped recovery document for code signing:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_enclave_emergency_backup
```
Add both public signing keys (`id_yubikey_signing.pub` and `id_enclave_emergency_backup.pub`) to your GitHub Profile under Settings → SSH and GPG Keys → New SSH Key (Set Key Type to "Signing Key").

Print the private string (`cat ~/.ssh/id_enclave_emergency_backup`), write/print it onto a physical document, store it inside your home lockbox alongside your OpenBao Unseal Shards, and completely delete the file from your working drive.

3. Binding Git Configuration Locally
Configure your shell environment to sign modifications using the primary hardware element:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_yubikey_signing.pub
git config --global commit.gpgsign true
```
*Note: Ensure GitHub Branch Protection is toggled ON for main with "Require signed commits" active.*

---

## 5. Day-Zero Operational Installation Workflow
### Pre-Deployment Cloud Architecture Setup
1. **Provision the Mesh Coordinator VPS**: Stand up a minimal instance (Rocky Linux 9, 1 vCPU, 2GB RAM) under a public provider. Update external DNS mappings (A-Record) for `vpn.yourdomain.com` to target this public routing interface.
2. **Deploy SPA Firewall Hardening**: Configure the cloud perimeter firewall to explicitly reject all incoming packets on all ports by default. Install `fwknopd` (Firewall Knock Operator Daemon) on the host. Ingest your developer machine's public SPA signature key into `/etc/fwknop/access.conf`.
3. **Initialize Headscale**: Install Docker, pull down Headscale configuration matrices, bind port 443 through Caddy for automated Let's Encrypt TLS encryption, and map the user account:

```bash
docker exec -it headscale-core headscale users create ai-user
```

### Execution Step 1: Prepare and Bake the Offline USB Payload
Run this automated workflow on an internet-connected Windows developer machine to synchronize versions, download the required Linux binaries, compile the offline Zarf packages, and organize the files for staging.

1. **Automated Windows USB Staging Utility (`scripts/prepare-usb.ps1`)**:
   Run the newly created PowerShell utility from your Windows terminal:
   ```powershell
   .\scripts\prepare-usb.ps1
   ```
   This script will automatically:
   - Synchronize versions across all manifests using your central `versions.yaml`.
   - Detect your local Windows Zarf version and auto-download the matching Linux `amd64` `zarf` binary from GitHub.
   - Compile both Zarf offline packages (`zarf-beelink` and `zarf-4090`) sequentially.
   - Stage all compiled bundles, Linux binaries, and deployment scripts into a unified directory at `/usb-payload`.

2. **Bake the Installation OS (Optional/First-Time Setup)**:
   If you have a Linux machine available and need to make the bootable unattended Kickstart installer for Rocky Linux, use the flash provisioner:
   ```bash
   chmod +x scripts/bake-usb.sh
   sudo ./scripts/bake-usb.sh /dev/sdX
   ```

3. **Stage the AI Payloads onto the USB**:
   Format your USB flash drive (FAT32/exFAT) and copy **all contents** of the generated `/usb-payload` directory directly to the root of your USB drive. Your USB will now contain:
   - `zarf` (the static Linux Zarf binary)
   - `zarf-package-sovereign-ai-enclave-beelink-amd64-1.0.0.tar.zst`
   - `zarf-package-sovereign-ai-enclave-4090-amd64-1.0.0.tar.zst`
   - `scripts/` (including the target node installer `setup-enclave.sh`)
   - `versions.yaml`

### Execution Step 2: Unattended Hardware Node Provisioning & Clustering
1. **Install the Host Operating System**: Insert the baked USB drive into your new Beelink server (or your 4090 Workstation Linux partition) and boot from it. The machine will instantly parse `bootstrap/enclave-kickstart.cfg` and configure the hardware automatically:
   - Enforces the official DISA STIG system profile limits.
   - Wipes target sectors and automatically binds drives into a mirrored Btrfs RAID 1 storage pool.
   - Binds static IP parameters to the physical direct Cat6 pipeline interface.
   - Auto-reboots the machine into a finalized, pristine terminal screen upon completion.

2. **Manually Authorize the USB on Hardened OS**:
   Since the STIG-hardened OS blocks USB storage and utilizes **USBGuard**, you must manually unblock it on your server console before mounting:
   ```bash
   # List blocked USB devices and find your drive's ID (e.g., 5)
   sudo usbguard list-devices
   
   # Temporarily allow the USB drive
   sudo usbguard allow-device <ID>
   ```

3. **Mount the USB and Deploy Beelink Gateway (Node 1 - Control Plane)**:
   Plug your USB drive into your Beelink Gateway, mount it, and run the enclave setup script:
   ```bash
   sudo mkdir -p /mnt/usb
   sudo mount /dev/sdb1 /mnt/usb
   cd /mnt/usb
   sudo ./scripts/setup-enclave.sh
   ```
   - Select **Option 1 (Beelink Gateway)** when prompted.
   - The script will auto-install the Linux `zarf` binary from the USB to `/usr/local/bin/zarf`.
   - It bootstraps the main K3s server, local registry, and deploys the core AI containers.
   - Finally, it writes the server's local IP and join token to `cluster-join-info.env` directly onto your USB drive.

4. **Plug-and-Play Deploy RTX 4090 Workstation (Node 2 - Worker Node)**:
   Safely unmount the USB from your Beelink Gateway, plug it into your RTX 4090 Workstation node, manually unblock USBGuard, mount it, and run the same setup script:
   ```bash
   sudo mkdir -p /mnt/usb
   sudo mount /dev/sdb1 /mnt/usb
   cd /mnt/usb
   sudo ./scripts/setup-enclave.sh
   ```
   - Select **Option 2 (RTX 4090 Workstation)** when prompted.
   - **Auto-Discovery**: The script will automatically load the Beelink Gateway's IP and Join Token directly from the USB!
   - **Pre-flight Connection Verification**: It will run a TCP handshake check on port `6443` to ensure the direct Cat6 ethernet connection to the Beelink is fully operational before executing any changes.
   - It auto-installs `zarf`, registers the node to the existing cluster in pure agent mode, and deploys the high-throughput GPU workloads (`vllm`, `speaches`, `comfyui`).

5. **Approve Cluster Entry via Your Phone**: The machines will check in and immediately drop into a blocked Headscale network mesh pending queue. Intercept the unique fingerprint token from your phone alert log (ntfy/Gotify), and whitelist your nodes:
```bash
docker exec -it headscale-core headscale auth register --user ai-user --auth-id [FINGERPRINT_ID]
```

---

## 6. Automation Configuration Blueprints & Source Code

### Hardened Kickstart Unattended OS Engine Profile (`bootstrap/enclave-kickstart.cfg`)
Included in the repo path `bootstrap/enclave-kickstart.cfg`.

### Automated USB Media Flash Provisioner (`scripts/bake-usb.sh`)
Included in the repo path `scripts/bake-usb.sh`.

### Initial Immutable Package Mappings (`bootstrap/zarf-beelink.yaml` & `bootstrap/zarf-4090.yaml`)
Included in the repo paths `bootstrap/zarf-beelink.yaml` and `bootstrap/zarf-4090.yaml`.

### Day-Zero Automated Bootstrap Setup Script (`scripts/setup-enclave.sh`)
Included in the repo path `scripts/setup-enclave.sh`.

### Windows Dev Workstation USB Preparation Utility (`scripts/prepare-usb.ps1`)
Included in the repo path `scripts/prepare-usb.ps1`.

### Core Application Declarative Specification (`gitops/base/enclave-apps.yaml`)
Included in the repo path `gitops/base/enclave-apps.yaml`.

### Sandbox Container Microsegmentation Policy (`gitops/base/network-policy.yaml`)
Included in the repo path `gitops/base/network-policy.yaml`.

### Custom Token Hydration Developer Utility (`scripts/gcert` & `scripts/gcert.ps1`)
Included in the repo paths `scripts/gcert` (Linux/macOS Bash) and `scripts/gcert.ps1` (Windows native PowerShell).

---

## 8. Day-Two Maintenance & Continuous GitOps Strategy
### Outbound Push-Based GitOps Lifecycle Execution
Instead of using traditional pull-based architectures that force you to expose an inbound network port to the public internet to listen for incoming GitHub webhooks, this deployment model uses an isolated local runner container (`enclave-runner`) running inside the cluster.

```text
[ Developer Local Machine ]
            │
            ▼ (Commits signed file change, e.g., extends cookie timeout to 45 days)
[ Private GitHub Repository ] 
            │
            ▼ (Detects commit state and queues the execution job)
[ Outbound Loop: Enclave GitOps Runner Container ]
            │
            ▼ (Fetches the job details safely over the Headscale mesh network)
[ Local K3s Cluster State Automatically Re-hydrated and Synchronized ]
```

The `enclave-runner` acts as an outbound-only polling agent, listening for state modifications to your private GitHub repository over your secure Headscale mesh network tunnel. When a cryptographically signed hardware commit arrives on the repository's main branch, the runner captures the job, instantiates a temporary staging testing environment (namespace: `enclave-staging`), runs validation checks against your manifest configurations, and applies the update directly to the production cluster. This architecture ensures your repository remains the single source of truth for your configuration while keeping your home environment hidden behind your SPA network perimeter.
