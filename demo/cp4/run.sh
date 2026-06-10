#!/usr/bin/env bash
# CP4 — pivot_root: your own root filesystem (real Alpine Linux)
#
# THE IDEA: so far the container still sees the HOST's files. A real container
# has its OWN root filesystem. pivot_root swaps "/" for a directory we choose
# (an extracted Alpine), then throws the old root away so it can't be reached.
#
# This is the one fiddly checkpoint. The comments explain each line — the three
# gotchas (make-rprivate, the bind-mount, hash -r) trip up everyone the first time.

set -e

# The Alpine rootfs the pre-flight extracted. Override with: ROOTFS=/path bash run.sh
ROOTFS="${ROOTFS:-$HOME/paradox-workshop/rootfs}"
export ROOTFS

if [ ! -x "$ROOTFS/bin/sh" ]; then
  echo "No Alpine rootfs at $ROOTFS"
  echo "Run pre-flight.sh from the repo root first (it extracts one for you)."
  exit 1
fi

echo "host filesystem has, e.g.: $(ls / | tr '\n' ' ')"
echo "pivoting into the Alpine rootfs at $ROOTFS ..."
echo

# Same namespaces as CP3. $ROOTFS is inherited into the inner shell via export.
unshare --user --map-root-user \
        --uts --pid --mount --fork --mount-proc \
  bash -c '
    set -e

    # systemd marks / as "shared"; pivot_root refuses a shared parent.
    # Make our private mount namespace fully private. Host is unaffected.
    mount --make-rprivate /

    # pivot_root requires the new root to be a mount point, so bind it to itself.
    cd "$ROOTFS"
    mount --bind . .
    mount --make-private .

    # A place to stash the old root for a moment.
    mkdir -p .old_root

    # The swap: "." becomes the new /, old root moves under /.old_root
    pivot_root . .old_root
    cd /

    # bash cached command paths (e.g. /usr/bin/mount) from the OLD root.
    # Alpine keeps them at /bin. Flush the cache so PATH lookup re-runs.
    hash -r

    # Give the container the standard mounts.
    mount -t proc proc /proc
    mount -t tmpfs tmpfs /tmp

    # Detach the old host root entirely — now the host FS is unreachable.
    umount -l /.old_root
    rmdir /.old_root

    hostname mini-container
    echo "we are inside Alpine now:"
    cat /etc/os-release | head -1
    echo "and / now contains ONLY Alpine: $(ls / | tr "\n" " ")"
    echo
    echo "type exit to leave."
    exec /bin/sh
  '

echo
echo "back on the host — your real / is exactly as it was."
