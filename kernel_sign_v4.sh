#!/usr/bin/env bash
set -euo pipefail

REPO="/sysroot/ostree/repo"
WORKDIR="/tmp/signing"

BOOTED_LINE=$(ostree admin status | grep '\*')
BRANCH=$(echo "$BOOTED_LINE" | awk '{print ($1=="*")?$2:$1}')
COMMIT=$(echo "$BOOTED_LINE" | awk '{print ($1=="*")?$3:$2}')
CLEAN_COMMIT="${COMMIT%%.*}"

rm -rf "$WORKDIR"

# Find kernel paths inside the commit
KERNELS=$(ostree ls "$CLEAN_COMMIT" /usr/lib/modules | awk '/vmlinuz/ {print $NF}')

for k in $KERNELS; do
    SRC="/usr/lib/modules/$k/vmlinuz"
    DST="$WORKDIR/vmlinuz-$k"

    # Extract kernel
    ostree cat "$CLEAN_COMMIT" "$SRC" > "$DST"

    # Sign it
    sbctl sign -s "$DST"

    echo "✓ Signed $SRC"
done

# Build minimal overlay tree
mkdir -p "$WORKDIR/tree/usr/lib/modules"

for k in $KERNELS; do
    mkdir -p "$WORKDIR/tree/usr/lib/modules/$k"
    mv "$WORKDIR/vmlinuz-$k" "$WORKDIR/tree/usr/lib/modules/$k/vmlinuz"
done

# Commit overlay on top of existing commit
ostree commit \
    --repo="$REPO" \
    --branch="$BRANCH" \
    --parent="$CLEAN_COMMIT" \
    --tree=ref="$CLEAN_COMMIT" \
    --tree=dir="$WORKDIR/tree" \
    --subject="Signed kernels ($(date))"

ostree admin deploy "$BRANCH"

echo "Deployment ready. Reboot to use signed kernels."
