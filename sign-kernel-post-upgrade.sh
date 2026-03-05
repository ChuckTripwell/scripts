#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"
BRANCH="custom/signed-nextboot"

echo "== Getting current OSTree commit =="

COMMIT=$(ostree admin status --json | jq -r '.deployments[0].checksum')

if [[ -z "$COMMIT" ]]; then
    echo "Failed to detect current commit"
    exit 1
fi

echo "Current commit: $COMMIT"

echo "== Preparing workspace =="

sudo rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "== Checking out OSTree commit =="

sudo ostree checkout \
    --union \
    "$COMMIT" \
    "$WORKDIR"

echo "== Signing kernel modules =="

MODULE_DIR="$WORKDIR/usr/lib/modules"

if [[ ! -d "$MODULE_DIR" ]]; then
    echo "Modules directory missing"
    exit 1
fi

find "$MODULE_DIR" -type f -name "*.ko*" | while read -r module; do
    echo "Signing $module"
    sudo sbctl sign -s "$module"
done

echo "== Committing modified tree to OSTree repo =="

NEW_COMMIT=$(sudo ostree commit \
    --repo="$REPO" \
    --branch="$BRANCH" \
    --selinux \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel modules ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying new commit =="

sudo ostree admin deploy "$BRANCH"

echo
echo "Deployment ready for next reboot."
echo
echo "Reboot to use signed modules:"
echo "  systemctl reboot"
