#!/usr/bin/env bash
set -euo pipefail

# OSTree variables
REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/nextboot"
BRANCH="custom/signed-nextboot"

# Directory for modules to be signed (you'll want to populate this)
MODULE_DIR="/tmp/modules"

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
sudo rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "== Checking out OSTree commit =="

# Checkout the OSTree commit to the working directory
sudo ostree checkout \
    --union \
    "$COMMIT" \
    "$WORKDIR"

echo "== Signing kernel modules in $MODULE_DIR =="

# Check if the directory exists
if [[ ! -d "$MODULE_DIR" ]]; then
    echo "Error: $MODULE_DIR does not exist."
    exit 1
fi

# Iterate through all files inside subdirectories of MODULE_DIR
find "$MODULE_DIR" -type f | while read -r file; do
    # Try signing the file, but if it fails, do not exit the script
    if sbctl sign -s "$file"; then
        echo "Successfully signed: $file"
    else
        echo "Failed to sign: $file"
    fi
done

echo "== Committing modified tree to OSTree repo =="

# Commit the modified tree with signed modules to the OSTree repo
NEW_COMMIT=$(sudo ostree commit \
    --repo="$REPO" \
    --branch="$BRANCH" \
    --selinux \
    --tree=dir="$WORKDIR" \
    --subject="Signed kernel modules ($(date))")

echo "New commit: $NEW_COMMIT"

echo "== Deploying new commit =="

# Deploy the new commit so it will be used at the next reboot
sudo ostree admin deploy "$BRANCH"

echo
echo "Deployment ready for next reboot."
echo
echo "Reboot to use signed modules:"
echo "  systemctl reboot"
