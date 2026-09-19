#!/usr/bin/env python3
# sync-versions.py - Sovereign Enclave Versions Synchronization Utility
# Automatically keeps bootstrap/zarf.yaml and gitops/base/enclave-apps.yaml updated with versions.yaml.
# This runs natively on Windows PowerShell or standard Linux/macOS.

import os
import re
import sys

def load_versions(versions_path):
    """Parses versions.yaml without any external dependencies."""
    versions = {}
    current_section = None
    if not os.path.exists(versions_path):
        print(f"❌ Error: {versions_path} not found.")
        sys.exit(1)
        
    with open(versions_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.endswith(':'):
                current_section = line[:-1].strip()
                continue
            match = re.match(r'([\w_]+):\s*"([^"]+)"', line)
            if match and current_section:
                key = f"{current_section}.{match.group(1)}"
                versions[key] = match.group(2)
    return versions

def update_images(content, versions):
    """Replaces container image tags globally across standard layouts without duplicates."""
    # Maps internal identifiers in versions.yaml to actual repository prefixes
    replacements = [
        (r'(?:ghcr\.io/)?open-webui/open-webui:[^\s\n\r"\'`\]]+', versions['images.open_webui']),
        (r'(?:docker\.io/)?searxng/searxng:[^\s\n\r"\'`\]]+', versions['images.searxng']),
        (r'(?:docker\.io/)?vllm/vllm-openai:[^\s\n\r"\'`\]]+', versions['images.vllm']),
        (r'(?:docker\.io/(?:library/)?)?python:[^\s\n\r"\'`\]]+', versions['images.python_sandbox']),
        (r'(?:ghcr\.io/)?matatonic/openedai-speech:[^\s\n\r"\'`\]]+', versions['images.openedai_speech']),
        (r'(?:ghcr\.io/)?ai-dock/comfyui:[^\s\n\r"\'`\]]+', versions['images.comfyui']),
        (r'(?:docker\.io/)?ollama/ollama:[^\s\n\r"\'`\]]+', versions['images.ollama']),
        (r'(?:ghcr\.io/)?berriai/litellm:[^\s\n\r"\'`\]]+', versions['images.litellm']),
        (r'(?:ghcr\.io/)?go-authentik/server:[^\s\n\r"\'`\]]+', versions['images.authentik']),
        (r'(?:docker\.io/)?bitnami/postgresql:[^\s\n\r"\'`\]]+', versions['images.postgres']),
        (r'(?:docker\.io/)?bitnami/redis:[^\s\n\r"\'`\]]+', versions['images.redis'])
    ]
    for pattern, replacement in replacements:
        content = re.sub(pattern, replacement, content)
    return content

def update_chart_version(content, chart_name, new_version):
    """Replaces Helm chart version in zarf.yaml specifically."""
    # Matches chart block name: openbao followed by version string
    pattern = r'(-\s*name:\s*' + re.escape(chart_name) + r'[\s\S]*?version:\s*")([^"]+)(")'
    return re.sub(pattern, r'\g<1>' + new_version + r'\g<3>', content)

def sync_zarf_yaml(file_path, versions):
    """Synchronizes versions into bootstrap/zarf.yaml."""
    if not os.path.exists(file_path):
        print(f"⚠️ Warning: {file_path} not found. Skipping.")
        return False
        
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    original = content
    content = update_images(content, versions)
    content = update_chart_version(content, 'openbao', versions['charts.openbao'])
    content = update_chart_version(content, 'dcgm-exporter', versions['charts.dcgm_exporter'])
    content = update_chart_version(content, 'kube-prometheus-stack', versions['charts.kube_prometheus_stack'])
    content = update_chart_version(content, 'authentik', versions['charts.authentik'])
    
    if content != original:
        with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        print(f"✅ Synchronized and updated: {file_path}")
        return True
    else:
        print(f"ℹ️ {file_path} is already up to date.")
        return False

def sync_apps_yaml(file_path, versions):
    """Synchronizes versions into gitops/base/enclave-apps.yaml."""
    if not os.path.exists(file_path):
        print(f"⚠️ Warning: {file_path} not found. Skipping.")
        return False
        
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    original = content
    content = update_images(content, versions)
    
    # Update vLLM default model argument
    # Matches: "--model", "neuralmagic/Llama-3.3-70B-Instruct-AWQ"
    model_pattern = r'(--model",\s*")([^"]+)(")'
    content = re.sub(model_pattern, r'\g<1>' + versions['models.vllm_default'] + r'\g<3>', content)
    
    if content != original:
        with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        print(f"✅ Synchronized and updated: {file_path}")
        return True
    else:
        print(f"ℹ️ {file_path} is already up to date.")
        return False

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    versions_path = os.path.join(base_dir, 'versions.yaml')
    zarf_beelink_path = os.path.join(base_dir, 'bootstrap', 'zarf-beelink.yaml')
    zarf_4090_path = os.path.join(base_dir, 'bootstrap', 'zarf-4090.yaml')
    zarf_path = os.path.join(base_dir, 'bootstrap', 'zarf.yaml')
    apps_path = os.path.join(base_dir, 'gitops', 'base', 'enclave-apps.yaml')
    
    print("🔄 Starting Sovereign Enclave version synchronization...")
    versions = load_versions(versions_path)
    
    sync_zarf_yaml(zarf_beelink_path, versions)
    sync_zarf_yaml(zarf_4090_path, versions)
    if os.path.exists(zarf_path):
        sync_zarf_yaml(zarf_path, versions)
    sync_apps_yaml(apps_path, versions)
    print("✨ Version synchronization complete.")

if __name__ == '__main__':
    main()
