#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"
KERNEL_FILE="/usr/lib/modules/5.20.0/vmlinuz"  # change to your file

echo "== Detecting current deployment =="
STATUS=$(ostree admin status --json)
COMMIT=$(jq -r '.deployments[0].checksum' <<<"$STATUS")

if [[ -z "$COMMIT" || "$COMMIT" == "null" ]]; then
    echo "Failed to detect current commit"
    exit 1
fi

echo "Current commit: $COMMIT"

echo "== Preparing workspace =="
rm -rf "$WORKDIR" || true
mkdir -p "$WORKDIR"

echo "== Checking out kernel directory =="
KERNEL_DIR=$(dirname "$KERNEL_FILE")
ostree checkout --repo="$REPO" --subpath="$KERNEL_DIR" "$COMMIT" "$WORKDIR"

WORK_KERNEL_FILE="$WORKDIR/$(basename "$KERNEL_FILE")"

echo "== Signing kernel =="
sbctl sign -s "$WORK_KERNEL_FILE"
echo "Signed: $WORK_KERNEL_FILE"

echo "== Committing overlay =="
NEW_COMMIT=$(ostree commit \
    --repo="$REPO" \
    --parent="$COMMIT" \
    --tree=ref="$COMMIT" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel $(basename "$KERNEL_FILE") ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying =="
ostree admin deploy "$NEW_COMMIT"

echo
echo "Next boot will use the signed kernel."
echo "Reboot when ready: systemctl reboot"
