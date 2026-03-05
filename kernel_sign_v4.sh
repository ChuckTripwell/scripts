#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"

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

echo "== Checking out all kernel module directories =="
# This checks out all subdirectories under /usr/lib/modules/
ostree checkout --repo="$REPO" --subpath=/usr/lib/modules "$COMMIT" "$WORKDIR"

# Automatically find the kernel image(s) using wildcard
KERNEL_IMAGES=("$WORKDIR"/*/vmlinuz)

if [[ ${#KERNEL_IMAGES[@]} -eq 0 ]]; then
    echo "No kernel images found under $WORKDIR/*/vmlinuz"
    exit 1
fi

echo "== Signing kernel image(s) =="
for kernel in "${KERNEL_IMAGES[@]}"; do
    sbctl sign -s "$kernel"
    echo "Signed: $kernel"
done

echo "== Creating overlay commit =="
NEW_COMMIT=$(ostree commit \
    --repo="$REPO" \
    --parent="$COMMIT" \
    --tree=ref="$COMMIT" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel image(s) ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying =="
ostree admin deploy "$NEW_COMMIT"

echo
echo "Next boot will use the signed kernel(s)."
echo "Reboot when ready: systemctl reboot"
