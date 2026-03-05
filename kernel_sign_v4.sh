#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"

# Clean workspace
rm -rf "$WORKDIR" || true
mkdir -p "$WORKDIR"

# Get current deployment commit and branch
CURRENT_COMMIT=$(ostree admin status --json | jq -r '.deployments[0].checksum')
CURRENT_BRANCH=$(ostree admin status --json | jq -r '.deployments[0].origin')

echo "Current commit: $CURRENT_COMMIT"
echo "Current branch: $CURRENT_BRANCH"

# Checkout only the directories under /usr/lib/modules
ostree checkout --repo="$REPO" --subpath=/usr/lib/modules "$CURRENT_COMMIT" "$WORKDIR"

# Sign all kernel images dynamically (wildcard)
for kernel in "$WORKDIR"/*/vmlinuz; do
    if [[ -f "$kernel" ]]; then
        sbctl sign -s "$kernel"
        echo "Signed: $kernel"
    fi
done

# Commit overlay to the current branch
NEW_COMMIT=$(ostree commit \
    --repo="$REPO" \
    --branch="$CURRENT_BRANCH" \
    --parent="$CURRENT_COMMIT" \
    --tree=ref="$CURRENT_COMMIT" \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel image(s) ($(date))")

echo "New commit: $NEW_COMMIT"

# Deploy new commit for next boot
ostree admin deploy "$CURRENT_BRANCH"

echo "Next boot will use the signed kernel(s). Reboot with: systemctl reboot"
