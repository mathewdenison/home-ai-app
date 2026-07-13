#!/bin/bash
set -e

ISO_URL="https://dl.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-minimal.iso"
ISO_PATH="/tmp/rocky9.8-minimal.iso"
TARGET_USB=$1

if [ -z "$TARGET_USB" ]; then
    echo "❌ Error: Target USB drive path missing. Usage: sudo ./bake-usb.sh /dev/sdX"
    exit 1
fi

if [[ "$TARGET_USB" == "/dev/sda" || "$TARGET_USB" == "/dev/nvme"* ]]; then
    echo "⚠️ System target safety trigger: Targeted system critical partition."
    exit 1
fi

echo "📥 [1/3] Fetching verified baseline Rocky Linux 9 installation medium..."
if [ ! -f "$ISO_PATH" ]; then
    curl -L "$ISO_URL" -o "$ISO_PATH"
fi

echo "🛠️ [2/3] Writing baseline operating system files to device partition matrix..."
sudo dd if="$ISO_PATH" of="$TARGET_USB" bs=4M status=progress conv=fdatasync

echo "📂 [3/3] Embedding custom declarative Kickstart definitions..."
mkdir -p /tmp/usb-target
sudo mount "${TARGET_USB}1" /tmp/usb-target || sudo mount "${TARGET_USB}" /tmp/usb-target

sudo cp ../bootstrap/enclave-kickstart.cfg /tmp/usb-target/ks.cfg

# Determine the directory where this script resides to locate resources reliably
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f /tmp/usb-target/EFI/BOOT/grub.cfg ]; then
    echo "💾 Overwriting target bootloader configuration with customized grub.cfg..."
    sudo cp "$SCRIPT_DIR/../grub.cfg" /tmp/usb-target/EFI/BOOT/grub.cfg
fi

sudo umount /tmp/usb-target
echo "✅ Deployment medium successfully finalized. Plug USB into target node and initiate boot layout."
