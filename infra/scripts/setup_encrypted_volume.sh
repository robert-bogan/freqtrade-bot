#!/bin/bash

# This script sets up an encrypted volume on a Hetzner cloud instance
# WARNING: This will erase everything on /dev/sdb (adjust as needed)

set -e

# Parameters
DEVICE="/dev/sdb"
MAPPER_NAME="securedata"
MOUNT_POINT="/mnt/encrypted"
VOLUME_LABEL="EncryptedVolume"

# Step 1: Install required tools
sudo apt-get update
sudo apt-get install -y cryptsetup

# Step 2: Create LUKS partition (interactive passphrase prompt)
echo "[*] Creating LUKS encrypted partition on $DEVICE..."
sudo cryptsetup luksFormat $DEVICE

# Step 3: Open encrypted volume
echo "[*] Opening encrypted volume..."
sudo cryptsetup luksOpen $DEVICE $MAPPER_NAME

# Step 4: Create ext4 filesystem
echo "[*] Creating filesystem..."
sudo mkfs.ext4 /dev/mapper/$MAPPER_NAME -L $VOLUME_LABEL

# Step 5: Create mount point and mount
echo "[*] Mounting encrypted volume..."
sudo mkdir -p $MOUNT_POINT
sudo mount /dev/mapper/$MAPPER_NAME $MOUNT_POINT

# Step 6: Set permissions
sudo chown -R $(whoami):$(whoami) $MOUNT_POINT

echo "[✔] Encrypted volume mounted at $MOUNT_POINT"
echo "Put your sensitive files (e.g. .env, DB) here."
