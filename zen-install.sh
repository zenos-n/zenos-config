#!/usr/bin/env bash
set -e

# ensure we are in the config dir
cd /iso-config || { echo "cant find /iso-config"; exit 1; }

echo "--- 0x-zenos interactive installer ---"

# 1. Host Picker (Eval flake outputs)
echo "fetching hosts from flake..."
HOSTS=$(nix flake show --json . | jq -r '.nixosConfigurations | keys[]')
SELECTED_HOST=$(echo "$HOSTS" | fzf --header "Select host configuration:")

if [ -z "$SELECTED_HOST" ]; then
    echo "no host selected. exiting."
    exit 1
fi

# 2. Disk Picker
echo "detecting disks..."
SELECTED_DISK=$(lsblk -dno NAME,SIZE,MODEL | fzf --header "SELECT TARGET DISK (ALL DATA WILL BE WIPED):" | awk '{print $1}')

if [ -z "$SELECTED_DISK" ]; then
    echo "no disk selected. exiting."
    exit 1
fi

DISK_PATH="/dev/$SELECTED_DISK"
echo "TARGET: $DISK_PATH ($SELECTED_HOST)"
read -p "ARE YOU SURE? THIS WIPES EVERYTHING ON $DISK_PATH (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then exit 1; fi

# 3. Auto-Partitioning (Simple UEFI Layout)
echo "partitioning $DISK_PATH..."
parted "$DISK_PATH" -- mklabel gpt
parted "$DISK_PATH" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK_PATH" -- set 1 boot on
parted "$DISK_PATH" -- mkpart primary ext4 512MiB 100%

# Determine partition suffixes (nvme0n1p1 vs sda1)
if [[ $DISK_PATH == *"nvme"* ]]; then
    BOOT_PART="${DISK_PATH}p1"
    ROOT_PART="${DISK_PATH}p2"
else
    BOOT_PART="${DISK_PATH}1"
    ROOT_PART="${DISK_PATH}2"
fi

echo "patching flake inputs for portability..."

# check if zenpkgs was bundled
if [ -d "/etc/iso-config/zenpkgs" ]; then
    cp -r /etc/iso-config/zenpkgs /mnt/etc/zenos/zenpkgs
    # rewrite the flake.nix to point to the local copy
    # search for the path: string and replace with relative ./zenpkgs
    sed -i 's|path:/home/doromiert/Projects/zenpkgs-2|./zenpkgs|g' /mnt/etc/zenos/flake.nix
fi

# 4. Format & Mount
mkfs.fat -F 32 "$BOOT_PART"
mkfs.ext4 -L zenos_root "$ROOT_PART"

mount /dev/disk/by-label/zenos_root /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# 5. Copy config & Install
mkdir -p /mnt/etc/zenos
cp -r /iso-config/* /mnt/etc/zenos/

nixos-install --flake "/mnt/etc/zenos#$SELECTED_HOST" --no-root-passwd

echo "done. pull the usb and reboot."