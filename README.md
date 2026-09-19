# Sovereign AI Enclave 🌌

A private, dual-node local AI inference cluster designed to run fully offline inside your home network. This setup assumes a pre-installed, managed environment running **Fedora 44 Workstation** and is accessed securely via your router's built-in **Wireguard VPN**.

---

## 🏗️ Architectural Topology

The Sovereign Enclave splits its orchestrations across two physical nodes to optimize computing efficiency:

```text
               ┌───────────────────────────────────────────────┐
               │         HOME NETWORK / LAN SUBNET            │
               │  (Accessed remotely via Router Wireguard)     │
               └───────────────────────┬───────────────────────┘
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            │                                                     │
 ┌──────────▼──────────┐                               ┌──────────▼──────────┐
 │   BEELINK GATEWAY   │                               │     RTX 4090        │
 │ (Control Plane)     ◄───────────────────────────────►    WORKSTATION      │
 │                     │     PHYSICAL CAT6 LINK        │   (GPU Worker)      │
 │ • K3s Server        │                               │                     │
 │ • Traefik Ingress   │                               │ • K3s Agent         │
 │ • Authentik SSO     │                               │ • vLLM Engine       │
 │ • OpenBao (Secrets) │                               │ • Speaches (Audio)  │
 │ • Prometheus/Grafana│                               │ • ComfyUI (Images)  │
 │ • Ollama (70B GGUF) │                               │ • 14B AWQ Model     │
 └─────────────────────┘                               └─────────────────────┘
```

---

## ⚡ Core Technical Capabilities
- **Local AI Sovereignty:** Your data and conversations never leave your physical servers.
- **Intelligent Complexity Routing (LiteLLM):** Prompts are dynamically routed. Analytical/heavy queries (math, programming, in-depth design) automatically target the massive **DeepSeek-R1 70B GGUF** model running on the Beelink Gateway. Quick, conversational prompts route to the high-throughput **DeepSeek-R1 14B AWQ** running on the RTX 4090 Workstation GPU.
- **Continuous Voice Synthesis:** Sub-second speech-to-text (Whisper-small) and text-to-speech (Kokoro-ONNX) integrated into your interface via standard API routes.
- **Zero-Trust Network Microsegmentation:** Standard Kubernetes NetworkPolicies strictly isolate containers. Only whitelisted pods (e.g. Open WebUI) are allowed to access backend LLM engines.
- **Immutable Offline Packaging (Zarf):** Applications are compiled, bundled, and packaged into hermetic, offline Zarf archives for reproducible local airgap installs.

---

## 📂 Repository Layout

```text
├── .github/workflows/       # GitOps continuous delivery polling runners
├── bootstrap/               # Node-specific Zarf configuration manifests
│   ├── zarf-beelink.yaml    # Beelink control-plane packages & base images
│   ├── zarf-4090.yaml       # 4090 workstation GPU exporter & DCGM manifests
│   ├── zarf-model-70b-gguf.yaml
│   ├── zarf-model-14b-gguf.yaml
│   └── zarf-model-14b-awq.yaml
├── gitops/                  # GitOps base resources & policies
│   ├── base/                # Core Helm values, NetworkPolicies, & Dashboards
│   │   ├── enclave-apps.yaml # Primary open-webui, searxng, litellm, & audio deployments
│   │   ├── network-policy.yaml
│   │   ├── openbao-init.yaml # Auto-unseal & OpenBao configuration job
│   │   └── observability-dashboards.yaml
│   └── config/              # Ingress domain configuration & SSO values
├── scripts/                 # Administration and setup tools
│   ├── prepare-usb.ps1      # Windows utility to download models & compile offline packages
│   ├── setup-enclave.sh     # Primary Fedora 44 bootstrapping installer
│   ├── sync-versions.py     # Version synchronization manager
│   ├── fetch-dashboards.py  # Automation tool compiling telemetry dashboards
│   └── gcert.ps1            # Developer token hydration utility
├── versions.yaml            # Central single source of truth for all software versions
└── README.md                # System documentation
```

---

## 🛠️ Step-by-Step Deployment Guide

### Step 1: Assume Fedora 44 is Managed and Active
Your servers (Beelink Gateway and RTX 4090 Workstation) must already have a clean installation of **Fedora 44 Workstation** and be connected on the same physical local network.

*Recommend configuring a direct secondary Ethernet link (Cat6) between the Beelink and the 4090 node using a dedicated subnet (e.g. `10.0.0.0/24`) to isolate high-throughput inter-node communications.*

### Step 2: Prepare the Offline USB Staging Payload
On an internet-connected Windows developer workstation:
1.  Insert an external USB drive (formatted with NTFS/exFAT to support large model weights).
2.  Open PowerShell as Administrator and run the payload preparation script:
    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\scripts\prepare-usb.ps1
    ```
3.  Select **Option 1 (Full Payload)**. This script will automatically:
    - Run `sync-versions.py` to align and write the versions declared in `versions.yaml` across all configurations.
    - Download matching Linux `zarf` binaries.
    - Download DeepSeek-R1 model weights (70B GGUF, 14B GGUF, and 14B AWQ).
    - Compile the Beelink and 4090 workstation software bundles into offline Zarf packages.
    - Compile the three model archives into standalone Zarf packages.
    - Stage the prepared binaries, scripts, and bundles cleanly onto your USB drive.

### Step 3: Bootstrap the Beelink Gateway (Control Plane)
1.  Plug your prepared USB drive into your physical Beelink Gateway.
2.  Open a terminal as `root` (or use `sudo`) and navigate to your mounted USB path:
    ```bash
    cd /run/media/admin/your-usb-drive-name/scripts/
    ```
3.  Run the bootstrapping installer:
    ```bash
    sudo ./setup-enclave.sh
    ```
4.  Select **Option 1: Beelink Gateway**.
    - The script will automatically detect and install Zarf, initialize K3s, and deploy the base control plane services (OpenBao, Authentik, Traefik, Grafana).
    - It will then automatically locate the 70B and 14B fallback GGUF model packages on your USB and deploy them onto Ollama.
    - Upon completion, the script outputs server join variables to `cluster-join-info.env` directly on your USB.

### Step 4: Bootstrap the RTX 4090 Workstation (Worker Node)
1.  Plug the USB drive into your physical RTX 4090 Workstation.
2.  Open a terminal as `root` and navigate to the scripts directory:
    ```bash
    cd /run/media/admin/your-usb-drive-name/scripts/
    ```
3.  Run the bootstrapping installer:
    ```bash
    sudo ./setup-enclave.sh
    ```
4.  Select **Option 2: RTX 4090 Workstation**.
    - The script reads `cluster-join-info.env` directly from the USB, auto-configures the K3s agent, and connects the workstation to your Beelink Gateway control plane.
    - It installs the DCGM telemetry exporter and deploys ComfyUI, Speaches, and vLLM.
    - It registers and deploys the **DeepSeek-R1 14B AWQ** weights to the local vLLM engine, automatically binding execution to your physical GPU.

---

## 🪐 Post-Deployment Verification & SSO Hydration
To finalize and secure your private local AI stack, consult the **[Sovereign Enclave Day-One Runbook (enclave-deployment-checklist.md)](enclave-deployment-checklist.md)** for detailed procedures on:
1.  Exposing OIDC clients inside Authentik Admin Console.
2.  Injecting real production passwords and HuggingFace API tokens dynamically into OpenBao.
3.  Mapping and executing your local developer sessions using **`scripts/gcert.ps1`**.
4.  Accessing Grafana's pre-integrated custom system hardware telemetry dashboards.
