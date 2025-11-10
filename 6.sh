#!/usr/bin/env bash
set -euo pipefail

### transactional-btrfs-auto.sh — Fully automated transactional update system for Arch Linux (GRUB/Limine compatible)

ROOT_MOUNTPOINT="/"
SUBVOL_ROOT="@"
TRANS_DIR="/.snapshots"
KEEP_SNAPSHOTS=3
DEVICE="$(findmnt -n -o SOURCE "$ROOT_MOUNTPOINT")"

[[ $EUID -ne 0 ]] && { echo "Run as root." >&2; exit 1; }
findmnt -n -o FSTYPE "$ROOT_MOUNTPOINT" | grep -q btrfs || { echo "Root is not on Btrfs." >&2; exit 1; }
command -v btrfs >/dev/null || { echo "Missing btrfs-progs." >&2; exit 1; }
command -v pacman >/dev/null || { echo "Missing pacman." >&2; exit 1; }

mkdir -p "$TRANS_DIR"

SNAP_NAME="txn-$(date +%Y%m%d-%H%M%S)"
SNAP_PATH="${TRANS_DIR}/${SNAP_NAME}"

echo "[*] Creating transactional snapshot: ${SNAP_PATH}"
btrfs subvolume snapshot -r "${ROOT_MOUNTPOINT}${SUBVOL_ROOT}" "${SNAP_PATH}-base"
btrfs subvolume snapshot "${ROOT_MOUNTPOINT}${SUBVOL_ROOT}" "${SNAP_PATH}"

echo "[*] Performing update inside transactional snapshot..."
btrfs property set "${SNAP_PATH}" ro false
systemd-nspawn -D "${ROOT_MOUNTPOINT}${SNAP_PATH}" --quiet --machine "txn-$(date +%s)" pacman -Syu --noconfirm
btrfs property set "${SNAP_PATH}" ro true

echo "[*] Cleaning old snapshots (keeping last ${KEEP_SNAPSHOTS})..."
mapfile -t snaps < <(btrfs subvolume list -o "$TRANS_DIR" | awk '{print $9}' | grep -E '^txn-' | sort)
if (( ${#snaps[@]} > KEEP_SNAPSHOTS )); then
    for old in "${snaps[@]:0:${#snaps[@]}-KEEP_SNAPSHOTS}"; do
        echo "    Deleting old snapshot: $old"
        btrfs subvolume delete "${ROOT_MOUNTPOINT}${TRANS_DIR}/${old}" || true
    done
fi

echo "[*] Detecting bootloader..."
BOOTLOADER=""
if command -v grub-mkconfig &>/dev/null && [ -d /boot/grub ]; then
    BOOTLOADER="grub"
elif command -v limine &>/dev/null && [ -f /boot/limine.cfg ]; then
    BOOTLOADER="limine"
fi

if [[ $BOOTLOADER == "grub" ]]; then
    echo "[*] Updating GRUB configuration..."
    mkdir -p /boot/grub
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || echo "    Warning: grub-mkconfig failed."
elif [[ $BOOTLOADER == "limine" ]]; then
    echo "[*] Updating Limine configuration..."
    if [[ -f /boot/limine/limine-deploy ]]; then
        /boot/limine/limine-deploy /boot >/dev/null 2>&1 || true
    fi
    if [[ -f /boot/limine.cfg ]]; then
        grep -v '^ENTRY ' /boot/limine.cfg > /boot/limine.cfg.new
        echo "ENTRY Arch (txn ${SNAP_NAME})" >> /boot/limine.cfg.new
        echo "    PROTOCOL linux" >> /boot/limine.cfg.new
        echo "    CMDLINE root=${DEVICE} rootflags=subvol=${SNAP_NAME} rw quiet" >> /boot/limine.cfg.new
        mv /boot/limine.cfg.new /boot/limine.cfg
    fi
else
    echo "[!] Bootloader not detected — please configure manually if needed."
fi

echo
echo "[*] Transactional update complete."
echo "    New snapshot: ${SNAP_PATH}"
echo "    Bootloader: ${BOOTLOADER:-unknown}"
echo "    Kept last ${KEEP_SNAPSHOTS} snapshots."
echo "Done."
