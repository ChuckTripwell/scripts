#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"

echo "== Detecting current deployment =="
STATUS=$(ostree admin status --json)
COMMIT=$(jq -r '.deployments[0].checksum' <<<"$STATUS")
BRANCH=$(jq -r '.deployments[0].origin' <<<"$STATUS")

if [[ -z "$COMMIT" || "$COMMIT" == "null" || -z "$BRANCH" || "$BRANCH" == "null" ]]; then
    echo "Failed to detect current commit or branch"
    exit 1
fi

echo "Current commit: $COMMIT"
echo "Current branch: $BRANCH"

echo "== Preparing workspace =="
rm -rf "$WORKDIR" || true
mkdir -p "$WORKDIR"

echo "== Checking out /usr/lib/modules =="
# Checkout all kernel module directories dynamically
ostree checkout --repo="$REPO" --subpath=/usr/lib/modules "$COMMIT" "$WORKDIR"

# Automatically find all kernel images
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

echo "== Creating overlay commit on current branch =="
NEW_COMMIT=$(ostree commit \
    --repo="$REPO" \
    --branch="$BRANCH" \
    --parent="$COMMIT" \
    --tree=ref="$COMMIT" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel image(s) ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying =="
ostree admin deploy "$BRANCH"

echo
echo "Next boot will use the signed kernel(s)."
echo "Reboot when ready: systemctl reboot"
