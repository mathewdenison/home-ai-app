# Sovereign Enclave: Day-One Runbook & Configuration Checklist

This manual lists every single placeholder, configuration toggle, local DNS domain, and secret that must be updated/swapped out once your Fedora 44 Workstation servers (the Beelink Gateway and the local 4090 Workstation) are active.

---

## 🗺️ Quick-Reference Directory of Placeholders

| Scope / File | Placeholder Variable | Production Value | Impact / Purpose |
| :--- | :--- | :--- | :--- |
| **Authentication** | `https://auth.yourdomain.com` | Your local Authentik URL | Ingress gate for user verification |
| **Authentication** | `YOUR_AUTHENTIK_CLIENT_ID_HERE` | Authentik OIDC Client ID | Registers the CLI (`gcert`) in Authentik |
| **Authentication** | `open-webui-client-id-placeholder` | Authentik App Client ID | Connects the Web UI container to OIDC |
| **Cluster Topology** | `desktop-4090` | Actual host name | Binds heavy GPU tasks to the 4090 Node |
| **Host Directory Paths**| `/home/admin/ai-hub/workspace` | Actual admin path | Maps host sandboxes to cluster volumes |

---

## 🛠️ Step-by-Step Resolution Procedures

### 1. GPU Worker Binding (`gitops/base/enclave-apps.yaml`)
After joining your 4090 workstation to the K3s cluster:
1. Run `kubectl get nodes` to find the exact name registered for your 4090 machine.
2. Under the `vllm-inference-engine` deployment in `enclave-apps.yaml`, ensure the `nodeSelector` matches that exact hostname:
   ```yaml
   nodeSelector:
     kubernetes.io/hostname: [EXACT_4090_NODE_NAME]
   ```

### 2. Token Hydration & SSO (`scripts/gcert.ps1` & `gitops/config/auth-settings.yaml`)
Once your local Authentik portal is up:
*   Swap `https://auth.yourdomain.com` with your local Authentik domain (e.g. `https://auth.internal-mesh.local` or standard LAN domain).
*   Once you register a **Device Code Authorization flow** client in the Authentik Admin Portal, extract the Client ID and paste it over `YOUR_AUTHENTIK_CLIENT_ID_HERE` in `scripts/gcert.ps1`.
*   In `gitops/config/auth-settings.yaml`, update `authentik_client_id_placeholder` with the newly generated WebUI client ID.

---

## 🔒 3. Hydrating Secrets via OpenBao (Dynamic Injection)

The `enclave-apps.yaml` workload retrieves its secrets dynamically using **OpenBao Sidecar Injection**. You must manually seed the master secrets into the vault's KV store.

### The Required Secret Payload Scheme
Execute these commands from a machine with `kubectl` access to your cluster (e.g. your Beelink terminal or your workstation over the local network):

```bash
# 1. Fetch the OpenBao Root Token (stored during auto-init)
ROOT_TOKEN=$(kubectl get secret openbao-root-token -n ai-enclave -o jsonpath='{.data.token}' | base64 -d)

# 2. Inject your production secrets into the vault
# Replace placeholders with your actual production values!
kubectl exec -it openbao-0 -n ai-enclave -- env BAO_TOKEN="$ROOT_TOKEN" bao kv put secret/enclave/runtime \
  OPENID_PROVIDER_SECRET="your_authentik_webui_client_secret" \
  SEARXNG_SECRET_KEY="your_randomly_generated_hex_key" \
  LITELLM_MASTER_KEY="your_super_secure_api_master_key" \
  HF_TOKEN="your_huggingface_write_token"

# 3. (Optional) Verify the secrets are correctly stored
kubectl exec -it openbao-0 -n ai-enclave -- env BAO_TOKEN="$ROOT_TOKEN" bao kv get secret/enclave/runtime
```

*Note: Once written to OpenBao, your application pods will automatically pick up these changes upon their next restart.*

---

## 🏃‍♂️ 4. Making day-one scripts executable
Once the files are pulled down onto your active Linux nodes (e.g. Beelink Gateway or WSL/Workstation), elevate execution permissions. Run this in your workspace directory:
```bash
chmod +x scripts/setup-enclave.sh
```
On Windows, PowerShell scripts may require adjusting the local execution policy to run `gcert.ps1` natively:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\gcert.ps1
```

---

## 🔄 5. Managing Single-Source-Of-Truth Upgrades

All container image versions, Helm chart releases, and default AI models are cataloged centrally in `versions.yaml`. To change a version (e.g., upgrading Open WebUI or pinning a specific vLLM build):

1. Edit **`versions.yaml`** in the root of your repository with the new tags.
2. Synchronize all configurations in-place (updates both node-specific Zarf files `bootstrap/zarf-beelink.yaml` and `bootstrap/zarf-4090.yaml`, and your Kubernetes manifest `gitops/base/enclave-apps.yaml` automatically):
   ```bash
   # Works identically on Windows PowerShell or Linux Bash
   python scripts/sync-versions.py
   ```
3. Compile the updated offline packages on an internet-connected computer:
   ```bash
   # Compile Beelink Gateway dependencies
   zarf package create bootstrap/zarf-beelink.yaml --architecture amd64 --confirm
   
   # Compile 4090 Workstation dependencies
   zarf package create bootstrap/zarf-4090.yaml --architecture amd64 --confirm
   ```
4. Copy the compiled `.tar.zst` payload files back onto your USB drive. When you plug the USB into either physical machine and execute `./setup-enclave.sh`, the installer will automatically scan, match, and deploy only the package matching that machine's requirements!
5. Commit the updated configuration files to your private GitHub repository to keep your version-controlled state in sync with your nodes.

---

## 🎨 6. Advanced Open WebUI Integrations (Images, Voice & Conduit App)

We have pre-configured Open WebUI in `enclave-apps.yaml` to enable high-fidelity image generation, real-time speech-to-text (STT), text-to-speech (TTS), and streaming WebSockets.

### A. Image Generation (Local ComfyUI Container Integration)
*   **Active Config**: Pre-configured to point natively to your new local `comfyui-service` running on your 4090 Workstation on `http://comfyui-service.ai-enclave.svc.cluster.local:8188/`.
*   **How to customize or drop models**:
    1.  Your ComfyUI models folder is mapped to the physical directory **`/home/admin/ai-hub/workspace/comfyui/models/checkpoints/`** on your 4090 machine's disk.
    2.  Simply download and drop your favorite SDXL or SD 1.5 checkpoints (e.g. from CivitAI) directly into that physical directory on your 4090 node.
    3.  Log in to Open WebUI as an Administrator. Navigate to **Admin Panel > Settings > Images**. Set Image Generation Engine to `comfyui` and ensure the API Base URL matches `http://comfyui-service.ai-enclave.svc.cluster.local:8188/`. Click save to instantly enable `/image` prompts in mobile Conduit or web!

### B. Continuous Voice Mode (STT and TTS Integration)
*   **Active Config**: Pre-routed to use your new local `speaches-audio-engine` cluster service natively.
*   **To configure voices and STT**:
    1.  Go to **Admin Panel > Settings > Audio**.
    2.  Configure **STT Engine**: Select `OpenAI`. Set API Base URL to `http://speaches-audio-service.ai-enclave.svc.cluster.local:8000/v1`, set API Key to `local-enclave-key`, and STT Model to `Systran/faster-whisper-small`.
    3.  Configure **TTS Engine**: Select `OpenAI`. Set API Base URL to `http://speaches-audio-service.ai-enclave.svc.cluster.local:8000/v1`, API Key to `local-enclave-key`, and TTS Model / Voice to `speaches-ai/Kokoro-82M-v1.0-ONNX` with your preferred voice identifier (e.g., `am_eric`).

### C. WebSockets & Mobile Conduit App Compatibility
The **Conduit** mobile app requires WebSocket connections (`ws://` / `wss://`) to stream tokens and orchestrate real-time socket events natively.
*   **Websockets Configuration**: Open WebUI is a FastAPI app running on Uvicorn, which has WebSocket support **turned on and active by default** on port `8080`.
*   **Reverse Proxy Requirement**: If you access your Web UI through a custom domain/ingress (like Caddy, NGINX Ingress, or Authentik Gateway), you **must** configure your reverse proxy to forward WebSocket upgrade headers.
    *   **Caddy Configuration (Example)**: Caddy supports WebSockets natively out of the box with zero extra config!
    *   **Nginx Configuration (Example)**: If using Nginx, ensure these lines are active inside your gateway `location /` reverse-proxy blocks:
        ```nginx
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        ```

### D. Natively Integrated Gateway Complexity Routing (Client-Agnostic!)
We have bypassed client-side scripting and **natively integrated the intelligent complexity router inside your LiteLLM Gateway container** inside `enclave-apps.yaml`! 

*   **How it works**: LiteLLM hosts a secure async custom Python class (`ComplexityRouter`). When you submit a query to the virtual model name **`sovereign-enclave-model`**, the gateway analyzes the incoming prompt content:
    *   If the query is complex (contains keywords like `code`, `debug`, `math`, `design` or exceeds 500 characters), it automatically and transparently dispatches the request to the **Beelink's local 70B model**.
    *   For general conversations and quick questions, it routes it to the **4090 Workstation's fast GPU model**.
*   **Agnostic Client Benefits**: Because this lives on your cluster-internal gateway:
    1.  **Open WebUI**: Simply select the default **`sovereign-enclave-model`** dropdown. Routing happens seamlessly under the hood.
    2.  **Mobile Conduit App**: Point Conduit to your server. It will stream completions from `sovereign-enclave-model` utilizing dynamic routing.
    3.  **Local CLIs, API calls, and IDEs (Cursor/Cline)**: Point your dev tools to `http://lite-llm-service.ai-enclave.svc.cluster.local:8000/v1` targeting model `sovereign-enclave-model`. Your assistants will automatically receive fast 4090 GPU acceleration for small edits, and transparently scale up to the Beelink 70B for heavy reasoning pipelines!
*   **Automatic 4090 Failover**: If your 4090 node is powered down, LiteLLM's internal failover handler intercepts the timeout within 2.0 seconds and automatically shifts *all* traffic to the Beelink 70B CPU engine. Conversations never fail!

---

## 📊 7. Accessing and Configuring Grafana Observability Dashboards

Your cluster automatically captures comprehensive host-level, GPU-level, and container-level metrics across both physical servers simultaneously.

### A. Core Telemetry Architecture
*   **Beelink & 4090 Host Metrics**: Captured natively by **Node-Exporter** (running as a DaemonSet across all active servers in K3s). It records standard system CPU load, RAM usage, disk storage, and network interface traffic.
*   **RTX 4090 GPU Telemetry**: Captured by **DCGM-Exporter** (running on your 4090 node), recording real-time GPU core temperature, fan speed, VRAM consumption, and active power draw (W).
*   **Aggregator & Visualizer**: Prometheus collects these metrics, and **Grafana** (deployed via `kube-prometheus-stack` on your Beelink) serves as the visualization interface.

### B. Accessing your Grafana Dashboard
By default, Grafana runs inside your monitoring systems. You can access it securely from your workstation:
1.  Port-forward the Grafana service locally to access its interface:
    ```bash
    kubectl port-forward svc/kube-prometheus-stack-grafana -n ai-enclave 3000:80
    ```
2.  Open your browser and navigate to **`http://localhost:3000`** (or access it over your custom mesh DNS ingress mapping, e.g. `http://dashboards.internal-mesh.local`).
3.  Log in using your default credentials (standard is username: `admin` and password: `prom-operator` or dynamically configured via OpenBao!).

### C. Unified Custom Dashboard (Auto-Discovery Active!)
We deployed a dedicated telemetry manifest **`gitops/base/observability-dashboards.yaml`** inside your repository. 
*   **Zero-Config Auto-import**: This manifest contains a fully structured **ConfigMap** (`enclave-unified-dashboard`) labeled with `grafana_dashboard: "1"`. 
*   When Grafana initializes, its auto-discovery sidecar automatically registers this file, parses the PromQL panels, and **pre-loads a custom dashboard called "Sovereign Enclave: Core System Telemetry" inside your Grafana sidebar on boot!**
*   This unified dashboard displays:
    *   **Beelink CPU & RAM Utilization Gauges** side-by-side.
    *   **4090 Host CPU & RAM Utilization Gauges** side-by-side.
    *   **NVIDIA RTX 4090 Core Temperature Gauge** (color-coded: Green/Orange/Red).
    *   **RTX 4090 VRAM Allocation and Core Utilization graphs** in real-time.
    *   **RTX 4090 Live Power Draw (Watts)** tracking graph.

### D. Advanced Community Dashboards to Import (Highly Recommended)
If you want to view exhaustive, granular system details, you can import industry-standard, pre-built dashboards in seconds:
1.  Inside your Grafana sidebar, click **Dashboards > New > Import**.
2.  **To display host statistics for both Beelink & 4090**:
    *   Input Dashboard ID **`1860`** (Node Exporter Full dashboard).
    *   Click Load. This provides exhaustive, dropdown-grouped graphs comparing Beelink vs 4090 system stats.
3.  **To display RTX 4090 GPU metrics**:
    *   Input Dashboard ID **`12239`** (Official NVIDIA DCGM Exporter Dashboard) or **`15117`** (Optimized single-node GPU layout).
    *   Click Load. This provides complete thermal, PCIe bandwidth, and VRAM utilization analytics for your GPU.
