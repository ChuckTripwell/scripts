#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/tmp/nextboot"

# Clean workspace
rm -rf "$WORKDIR" || true
mkdir -p "$WORKDIR"

# Detect current commit and branch
COMMIT=$(ostree admin status --json | jq -r '.deployments[0].checksum')
BRANCH=$(ostree admin status --json | jq -r '.deployments[0].origin')

[[ -z "$COMMIT" || -z "$BRANCH" || "$COMMIT" == "null" || "$BRANCH" == "null" ]] && {
    echo "Failed to detect current commit or branch"; exit 1
}

echo "Current commit: $COMMIT"
echo "Current branch: $BRANCH"

# Checkout only /usr/lib/modules (kernel + modules)
ostree checkout --union --subpath=/usr/lib/modules "$COMMIT" "$WORKDIR"

# Sign kernel image
KERNEL="$WORKDIR"/*/vmlinuz
[[ -f "$KERNEL" ]] || { echo "Kernel not found!"; exit 1; }

echo "Signing kernel image: $KERNEL"
sbctl sign -s "$KERNEL"

# Commit overlay to current branch
NEW=$(ostree commit \
    --repo=/sysroot/ostree/repo \
    --branch="$BRANCH" \
    --parent="$COMMIT" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel and modules ($(date))")

# Deploy new commit
ostree admin deploy "$BRANCH"

echo "Deployment ready. Reboot to use signed kernel and modules:"
echo "  systemctl reboot"
