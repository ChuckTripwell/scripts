#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Clean workspace
rm -rf /tmp/nextboot || true
#mkdir -p /tmp/nextboot

# Get next deployment commit (or fallback to booted)
NEXT=$(ostree admin status | grep '^  Next ref:' | awk '{print $3}')
[[ -z "$NEXT" ]] && NEXT=$(ostree admin status | grep '^  Booted ref:' | awk '{print $3}')

# Get current branch
BRANCH=$(ostree admin status | grep '^  Booted ref:' | awk '{print $3}')

echo "Next deployment commit: $NEXT"
echo "Current branch: $BRANCH"

# Checkout only kernel directories
ostree checkout --repo=/sysroot/ostree/repo --subpath=/usr/lib/modules "$NEXT" /tmp/nextboot

# Find the kernel dynamically
KERNELS=(/tmp/nextboot/*/vmlinuz)

if [[ ${#KERNELS[@]} -eq 0 ]]; then
    echo "Error: No kernel found under /tmp/nextboot/*/vmlinuz"
    exit 1
fi

KERNEL=${KERNELS[0]}
echo "Signing kernel: $KERNEL"
sbctl sign -s "$KERNEL"
echo "Signed: $KERNEL"

# Commit overlay to current branch
NEW=$(ostree commit \
    --repo=/sysroot/ostree/repo \
    --branch="$BRANCH" \
    --parent="$NEXT" \
    --tree=ref="$NEXT" \
    --tree=dir=/tmp/nextboot \
    --subject="Signed kernel image ($(date))")

# Deploy new commit
ostree admin deploy "$BRANCH"

echo "Next boot will use the signed kernel. Reboot with: systemctl reboot"
