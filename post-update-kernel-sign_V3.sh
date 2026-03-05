#!/usr/bin/env bash
set -euo pipefail

# OSTree variables
REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"
BRANCH="custom/signed-nextboot"
MODULE_DIR="/tmp/nextboot/usr/lib/modules"

echo "== Getting current OSTree commit =="

# Get the current OSTree commit hash
COMMIT=$(ostree admin status --json | jq -r '.deployments[0].checksum')

if [[ -z "$COMMIT" ]]; then
    echo "Failed to detect current commit"
    exit 1
fi

echo "Current commit: $COMMIT"

echo "== Preparing workspace =="

# Clean up the workspace before checking out the tree
rm -rf "$WORKDIR" || true
mkdir -p "$WORKDIR"

echo "== Checking out kernel and modules subtree =="

# Checkout only the kernel and modules (not the entire system)
ostree checkout \
    --union \
    --subpath=/usr/lib/modules \
    "$COMMIT" \
    "$WORKDIR"

echo "== Signing kernel modules and kernel image in $MODULE_DIR =="

# Check if the directory exists
if [[ ! -d "$MODULE_DIR" ]]; then
    echo "Error: $MODULE_DIR does not exist."
    exit 1
fi

# Sign kernel modules
find "$MODULE_DIR" -type f -name "*.ko*" | while read -r file; do
    if sbctl sign -s "$file"; then
        echo "Successfully signed: $file"
    else
        echo "Failed to sign: $file"
    fi
done

# Sign the kernel image (vmlinuz)
echo "Signing kernel image (vmlinuz)..."
sbctl sign -s "$MODULE_DIR"/vmlinuz

echo "== Committing only signed kernel and modules to OSTree repo =="

# Commit only the modified modules and kernel image, not the full tree
NEW_COMMIT=$(ostree commit \
    --repo="$REPO" \
    --branch="$BRANCH" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel modules and kernel image ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying new commit =="

# Deploy the new commit so it will be used at the next reboot
ostree admin deploy "$BRANCH"

echo
echo "Deployment ready for next reboot."
echo
echo "Reboot to use signed modules and kernel:"
echo "  systemctl reboot"
