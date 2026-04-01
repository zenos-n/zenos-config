#!/usr/bin/env bash
set -e

cd /iso-config || exit 1

echo "--- zenos dual-boot installer ---"

# 1. Host Picker
HOSTS=$(nix flake show --json . | jq -r '.nixosConfigurations | keys[]')
SELECTED_HOST=$(echo "$HOSTS" | fzf --header "Select ZenOS host:")
[ -z "$SELECTED_HOST" ] && exit 1

# 2. Partition Picker
echo "select the partition where ZenOS root should go (e.g. nvme0n1p3):"
TARGET_PART=$(lsblk -lnp -o NAME,SIZE,TYPE,MOUNTPOINTS | grep part | fzf --header "SELECT ROOT PARTITION (WILL BE FORMATTED):" | awk '{print $1}')
[ -z "$TARGET_PART" ] && exit 1

echo "select your existing EFI partition (e.g. nvme0n1p1):"
EFI_PART=$(lsblk -lnp -o NAME,SIZE,TYPE,MOUNTPOINTS | grep part | fzf --header "SELECT EXISTING EFI PARTITION (WILL NOT BE FORMATTED):" | awk '{print $1}')
[ -z "$EFI_PART" ] && exit 1

read -p "Format $TARGET_PART as ext4 and install ZenOS? (y/N): " CONFIRM
[[ ! $CONFIRM =~ ^[Yy]$ ]] && exit 1

# 3. Format & Mount
echo "formatting root..."
mkfs.ext4 -L zenos_root "$TARGET_PART"

mount "$TARGET_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# 4. Bundle & Patch
mkdir -p /mnt/etc/zenos
cp -r /iso-config/source/* /mnt/etc/zenos/
if [ -d "/etc/iso-config/zenpkgs" ]; then
    cp -r /etc/iso-config/zenpkgs /mnt/etc/zenos/zenpkgs
    sed -i 's|path:/home/doromiert/Projects/zenpkgs-2|./zenpkgs|g' /mnt/etc/zenos/flake.nix
fi

# 5. Install
nixos-install --flake "/mnt/etc/zenos#$SELECTED_HOST" --no-root-passwd

echo "done. systemd-boot should auto-detect arch if it's on the same ESP."