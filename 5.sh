#!/usr/bin/env bash
set -euo pipefail

### transactional-btrfs.sh — Dynamic automated transactional update system for Arch Linux using Btrfs

### CONFIGURATION ###
ROOT_MOUNTPOINT="/"
SUBVOL_ROOT="@"
TRANS_DIR="/.snapshots"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
SNAP_NAME="txn-${TIMESTAMP}"
SNAP_PATH="${TRANS_DIR}/${SNAP_NAME}"

### CHECKS ###
if [[ $EUID -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
fi
if ! findmnt -n -o FSTYPE "$ROOT_MOUNTPOINT" | grep -q btrfs; then
    echo "Root is not on Btrfs." >&2
    exit 1
fi
if ! command -v btrfs &>/dev/null || ! command -v pacman &>/dev/null; then
    echo "Missing btrfs-progs or pacman." >&2
    exit 1
fi

### PREPARE ###
mkdir -p "${TRANS_DIR}"

### SNAPSHOT CURRENT ROOT ###
echo "[*] Creating snapshot ${SNAP_PATH}"
btrfs subvolume snapshot -r "${ROOT_MOUNTPOINT}${SUBVOL_ROOT}" "${SNAP_PATH}-base"

### CREATE WRITABLE SNAPSHOT FOR TRANSACTION ###
btrfs subvolume snapshot "${ROOT_MOUNTPOINT}${SUBVOL_ROOT}" "${SNAP_PATH}"

### MOUNT TEMP ROOT ###
MNT=$(mktemp -d)
mount -o subvol="$(basename "${SNAP_PATH}")" "$(findmnt -n -o SOURCE /)" "$MNT"

### CHROOT UPDATE ###
echo "[*] Performing pacman update inside transactional snapshot..."
mount --bind /dev "$MNT/dev"
mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"
mount --bind /run "$MNT/run"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

arch-chroot "$MNT" bash -c "pacman -Syu --noconfirm"

### CLEANUP ###
umount -R "$MNT" || true
rmdir "$MNT"

### CREATE FINAL READ-ONLY SNAPSHOT ###
btrfs property set "${SNAP_PATH}" ro true

### PRINT BOOT ENTRY INSTRUCTION ###
echo
echo "[*] Transactional update complete."
echo "    Snapshot: ${SNAP_PATH}"
echo "To boot into it, edit your bootloader to use subvol=$(basename "${SNAP_PATH}")"
echo "After verification, you can make it default or delete it with:"
echo "    btrfs subvolume delete ${SNAP_PATH}"
