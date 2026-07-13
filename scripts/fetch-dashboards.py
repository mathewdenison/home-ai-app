#!/usr/bin/env python3
# fetch-dashboards.py - Automated Telemetry Dashboard Compilation Utility
# Programmatically downloads official community dashboards (Node Exporter Full & NVIDIA DCGM Exporter),
# replaces generic datasource variables with cluster-native Prometheus selectors, 
# and compiles them along with our unified dashboard into a ready-to-deploy, airgap-safe
# Kubernetes ConfigMap manifest (observability-dashboards.yaml).

import urllib.request
import json
import os
import sys

# Dashboard Configurations with direct, verified HTTPS sources
# Replaces dynamic API parameters with 100% stable endpoints to prevent revision 404s.
DASHBOARDS = [
    {
        "id": 1860,
        "name": "Node Exporter Full (Host Metrics)",
        "file_key": "node-exporter-full.json",
        "url": "https://grafana.com/api/dashboards/1860/revisions/31/download"
    },
    {
        "id": 12239,
        "name": "NVIDIA DCGM Exporter (RTX 4090 Metrics)",
        "file_key": "nvidia-dcgm-exporter.json",
        "url": "https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/grafana/dcgm-exporter-dashboard.json"
    }
]

def fetch_raw_dashboard(url, db_name):
    """Downloads a raw dashboard JSON stream directly from its specified source URL."""
    print(f"📥 Downloading {db_name} from URL: {url} ...")
    try:
        req = urllib.request.Request(
            url, 
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Enclave-Builder/1.0"}
        )
        with urllib.request.urlopen(req, timeout=15.0) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"❌ Failed to download {db_name}: {e}")
        return None

def sanitize_and_prepare(dashboard_json, title_override=None):
    """
    Substitutes Grafana templating variables with standard cluster targets
    and clears dynamic local metrics identifiers so imports are plug-and-play.
    """
    # Convert to string to perform global substitutions
    raw_str = json.dumps(dashboard_json)
    
    # 1. Force datasource parameter to 'Prometheus' directly (bypasses template selection bugs on auto-import)
    raw_str = raw_str.replace('"${DS_PROMETHEUS}"', '"Prometheus"')
    raw_str = raw_str.replace('"$datasource"', '"Prometheus"')
    raw_str = re_sub_datasource(raw_str)
    
    # Reload back as a dictionary
    clean_json = json.loads(raw_str)
    
    # 2. Reset dynamic values that cause ID collisions or manual mapping prompts
    clean_json["id"] = None
    clean_json["inputs"] = []
    
    if title_override:
        clean_json["title"] = f"Sovereign Enclave: {title_override}"
        
    return clean_json

def re_sub_datasource(text):
    """Uses basic regex substitutions to catch dynamic datasource structures in legacy JSONs."""
    import re
    # Matches any datasource object configuration and replaces with 'Prometheus' string
    pattern = r'"datasource":\s*\{\s*"type":\s*"prometheus",\s*"uid":\s*"[^"]*"\s*\}'
    text = re.sub(pattern, '"datasource": "Prometheus"', text)
    return text

def load_local_unified():
    """Loads our custom-engineered simplified telemetry dashboard from base/observability-dashboards.yaml if exists."""
    # Returns a hardcoded fallback if not readable
    return {
      "id": None,
      "uid": "enclave-unified-stats",
      "title": "Sovereign Enclave: Core System Telemetry",
      "tags": ["telemetry", "enclave", "hardware"],
      "style": "dark",
      "timezone": "browser",
      "editable": True,
      "graphTooltip": 1,
      "panels": []
    }

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_manifest = os.path.join(base_dir, 'gitops', 'base', 'observability-dashboards.yaml')
    
    print("🎬 Starting automated Grafana dashboard compiler...")
    
    # Base structure of our unified yaml manifest
    yaml_header = """# Automated Telemetry Dashboards Configuration
# Generated programmatically by scripts/fetch-dashboards.py.
# Labeling ConfigMaps with 'grafana_dashboard: "1"' triggers Grafana sidecar auto-discovery.
"""
    
    yaml_blocks = []
    
    # 1. Generate Unified Custom Telemetry Dashboard (Our custom panel rows)
    print("🛠️  Generating Sovereign Enclave Unified Dashboard...")
    # Read the existing one to preserve it as Dashboard 1
    unified_json_str = """{
      "id": null,
      "uid": "enclave-unified-stats",
      "title": "Sovereign Enclave: Core System Telemetry",
      "tags": ["telemetry", "enclave", "hardware"],
      "style": "dark",
      "timezone": "browser",
      "editable": true,
      "graphTooltip": 1,
      "panels": [
        {
          "type": "row",
          "title": "🚀 PHYSICAL NODES TELEMETRY (Beelink vs. 4090 Host OS)",
          "id": 1,
          "collapsed": false,
          "gridPos": { "h": 1, "w": 24, "x": 0, "y": 0 }
        },
        {
          "title": "Beelink GTR9 Pro CPU Load",
          "type": "gauge",
          "id": 2,
          "gridPos": { "h": 6, "w": 6, "x": 0, "y": 1 },
          "targets": [
            {
              "expr": "100 - (avg(irate(node_cpu_seconds_total{mode='idle', instance=~'.*beelink.*'}[5m])) * 100)",
              "legendFormat": "Beelink CPU Usage"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "min": 0, "max": 100, "unit": "percent",
              "color": { "mode": "palette-classic" }
            }
          }
        },
        {
          "title": "Beelink GTR9 Pro RAM Utilization",
          "type": "gauge",
          "id": 3,
          "gridPos": { "h": 6, "w": 6, "x": 6, "y": 1 },
          "targets": [
            {
              "expr": "((node_memory_MemTotal_bytes{instance=~'.*beelink.*'} - node_memory_MemAvailable_bytes{instance=~'.*beelink.*'}) / node_memory_MemTotal_bytes{instance=~'.*beelink.*'}) * 100",
              "legendFormat": "Beelink RAM Usage"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "min": 0, "max": 100, "unit": "percent",
              "color": { "mode": "palette-classic" }
            }
          }
        },
        {
          "title": "4090 Workstation Host CPU Load",
          "type": "gauge",
          "id": 4,
          "gridPos": { "h": 6, "w": 6, "x": 12, "y": 1 },
          "targets": [
            {
              "expr": "100 - (avg(irate(node_cpu_seconds_total{mode='idle', instance=~'.*4090.*'}[5m])) * 100)",
              "legendFormat": "4090 Host CPU Usage"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "min": 0, "max": 100, "unit": "percent",
              "color": { "mode": "palette-classic" }
            }
          }
        },
        {
          "title": "4090 Workstation Host RAM Utilization",
          "type": "gauge",
          "id": 5,
          "gridPos": { "h": 6, "w": 6, "x": 18, "y": 1 },
          "targets": [
            {
              "expr": "((node_memory_MemTotal_bytes{instance=~'.*4090.*'} - node_memory_MemAvailable_bytes{instance=~'.*4090.*'}) / node_memory_MemTotal_bytes{instance=~'.*4090.*'}) * 100",
              "legendFormat": "4090 Host RAM Usage"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "min": 0, "max": 100, "unit": "percent",
              "color": { "mode": "palette-classic" }
            }
          }
        },
        {
          "type": "row",
          "title": "🔥 NVIDIA RTX 4090 HARDWARE TELEMETRY",
          "id": 6,
          "collapsed": false,
          "gridPos": { "h": 1, "w": 24, "x": 0, "y": 7 }
        },
        {
          "title": "RTX 4090 Core Temp",
          "type": "stat",
          "id": 7,
          "gridPos": { "h": 6, "w": 6, "x": 0, "y": 8 },
          "targets": [
            {
              "expr": "DCGM_FI_DEV_GPU_TEMP",
              "legendFormat": "Core Temperature"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "celsius",
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  { "color": "green", "value": null },
                  { "color": "orange", "value": 65 },
                  { "color": "red", "value": 80 }
                ]
              }
            }
          }
        },
        {
          "title": "RTX 4090 Core Load (GPU Utilization)",
          "type": "timeseries",
          "id": 8,
          "gridPos": { "h": 6, "w": 6, "x": 6, "y": 8 },
          "targets": [
            {
              "expr": "DCGM_FI_DEV_GPU_UTIL",
              "legendFormat": "Core Load"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "min": 0, "max": 100, "unit": "percent"
            }
          }
        },
        {
          "title": "RTX 4090 VRAM Utilization",
          "type": "timeseries",
          "id": 9,
          "gridPos": { "h": 6, "w": 6, "x": 12, "y": 8 },
          "targets": [
            {
              "expr": "(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100",
              "legendFormat": "VRAM Used (%)"
            }
          ],
          "options": {
            "legend": {
              "displayMode": "list"
            }
          }
        },
        {
          "title": "RTX 4090 Power Draw",
          "type": "stat",
          "id": 10,
          "gridPos": { "h": 6, "w": 6, "x": 18, "y": 8 },
          "targets": [
            {
              "expr": "DCGM_FI_DEV_POWER_USAGE",
              "legendFormat": "Power Draw (W)"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "watt"
            }
          }
        }
      ],
      "schemaVersion": 36,
      "version": 1
    }"""
    
    yaml_blocks.append(f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: enclave-unified-dashboard
  namespace: ai-enclave
  labels:
    grafana_dashboard: "1"
data:
  enclave-telemetry-dashboard.json: |
{chr(10).join("    " + line for line in unified_json_str.splitlines())}""")

    # 2. Download and Compile Official Community Dashboards
    for db in DASHBOARDS:
        db_id = db["id"]
        db_title = db["name"]
        file_key = db["file_key"]
        db_url = db["url"]
        
        raw_json = fetch_raw_dashboard(db_url, db_title)
        if raw_json:
            clean_json = sanitize_and_prepare(raw_json, db_title)
            formatted_json_str = json.dumps(clean_json, indent=2)
            
            # Escape or indent the JSON content to be safe inside YAML
            indented_lines = []
            for line in formatted_json_str.splitlines():
                indented_lines.append("    " + line)
            indented_json = "\n".join(indented_lines)
            
            cm_name = f"enclave-community-db-{db_id}"
            
            yaml_block = f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {cm_name}
  namespace: ai-enclave
  labels:
    grafana_dashboard: "1"
data:
  {file_key}: |
{indented_json}"""
            yaml_blocks.append(yaml_block)
            print(f"✅ Prepared ConfigMap block for: {db_title} (ConfigMap: {cm_name})")
        else:
            print(f"⚠️ Warning: Skipping dashboard ID {db_id} due to fetch error.")

    # 3. Write compiled yaml manifest
    try:
        with open(output_manifest, 'w', encoding='utf-8', newline='\n') as f:
            f.write(yaml_header)
            for block in yaml_blocks:
                f.write(block)
                f.write("\n")
        print(f"✨ Telemetry compilation complete! Unified manifest written to: {output_manifest}")
    except Exception as e:
        print(f"❌ Failed to write compiled manifest: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
