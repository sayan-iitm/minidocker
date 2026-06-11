#!/usr/bin/env bash
# mini-docker.sh — the ~100-line bash container that attendees build during
# the Paradox 2026 workshop "Build Your Own Mini Docker: Understanding
# Containers from Scratch". This is the finale; the per-checkpoint demos
# that build up to it live in demo/cp1 .. demo/cp5.
# repo: https://github.com/sayan-iitm/minidocker
#
# Usage:
#   ./mini-docker.sh run <image-dir> <cmd> [args...]
#   ./mini-docker.sh ps         # show running mini-containers
#   ./mini-docker.sh help
#
# Conventions: rootfs is a directory laid out like an Alpine minirootfs. The
# pre-flight script extracts one at ~/paradox-workshop/rootfs.

set -euo pipefail

# ----- knobs (env-tunable) ------------------------------------------------
ROOTFS_DEFAULT="${HOME}/paradox-workshop/rootfs"
MEM="${MEM:-100M}"          # cgroup MemoryMax
PIDS="${PIDS:-64}"          # cgroup TasksMax

# ----- helpers ------------------------------------------------------------
die()  { printf 'mini-docker: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "need '$1' on PATH"; }

cmd_help() {
  cat <<'EOF'
mini-docker — a Linux container in ~100 lines of bash.

usage:
  mini-docker run <rootfs-dir> <cmd> [args...]
  mini-docker ps
  mini-docker kill
  mini-docker help

env:
  MEM     memory limit (default 100M)
  PIDS    max processes (default 64)
EOF
}

# Build the in-container shell script. We pass this to bash inside the
# unshared namespaces. It does the pivot dance and execs the requested
# command.
build_inner_script() {
  local rootfs="$1"; shift
  # Note: $* is expanded at compose time, $$ stays literal (the inner shell's PID)
  cat <<EOF
set -e

# Bake all standard bin/sbin paths in explicitly. Don't trust the host's
# inherited \$PATH: AL2023 (and other usrmerged distros) omit /bin from
# ec2-user's PATH, and after pivot_root Alpine's mount/umount live at
# /bin/* — lookup would fail with "command not found". klibc-utils LAST:
# it ships a minimal mount that lacks --make-rprivate, so we never want it
# to win the lookup for mount; it's only a final fallback for pivot_root
# on Ubuntu 26.04+ without util-linux-extra.
export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/local/sbin:/usr/local/bin:/usr/lib/klibc/bin

# Bring loopback up. A fresh net namespace has only \`lo\`, and it starts DOWN,
# so anything that talks to 127.0.0.1 (redis-cli and most clients) can't connect
# until we raise it. Do this BEFORE pivot_root so we use the host's iproute2 —
# the container rootfs may not ship \`ip\`. The netns is ours (userns-owned), so
# we hold CAP_NET_ADMIN here. This is one of the things \`docker run\` does for you.
ip link set lo up 2>/dev/null || true

# 0. systemd marks / as MS_SHARED; pivot_root refuses on shared parents.
#    Inside our private mount namespace we de-shareify everything. This
#    affects the host nothing — it's a property of OUR namespace.
mount --make-rprivate /

# 1. The new root has to be a mount point.
mount --bind "$rootfs" "$rootfs"
mount --make-private "$rootfs"

# pivot_root needs a directory inside the new root to stash the old root
mkdir -p "$rootfs/.old_root"

cd "$rootfs"
pivot_root . .old_root
cd /

# 2. bash hashed /usr/bin/mount, /usr/bin/umount, etc. before pivot_root.
#    Those paths don't exist in the new root (Alpine has them under /bin
#    via busybox). Flush the command hash so PATH lookup re-runs.
hash -r 2>/dev/null || true

# wire up the standard "every container has these" mounts
mount -t proc proc /proc
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run 2>/dev/null || true
mount -t sysfs sysfs /sys  2>/dev/null || true

# unmount and forget about the host root
umount -l /.old_root
rmdir /.old_root

# minimal /dev — bind a handful of safe device nodes from the new root's
# /dev if Alpine already populated them; otherwise it's intentionally empty.
[ -e /dev/null ] || mknod -m 666 /dev/null c 1 3 2>/dev/null || true

# announce and exec
hostname mini-container
exec $*
EOF
}

cmd_run() {
  [ $# -ge 2 ] || { cmd_help; exit 2; }
  local rootfs="$1"; shift

  [ -d "$rootfs" ] || die "rootfs not found: $rootfs"
  [ -x "$rootfs/bin/sh" ] || die "no /bin/sh inside rootfs: $rootfs"

  need unshare
  need mount
  # pivot_root is resolved inside the inner script which prepends /usr/sbin
  # to PATH; we don't probe it here to avoid false-negatives on thin PATHs.

  local inner_script
  inner_script=$(build_inner_script "$rootfs" "$@")

  # Wrap the whole thing in a transient systemd scope so cgroup limits
  # apply. --user --scope = current login user, foreground, no daemonize.
  # If systemd-run isn't available we fall back to running without limits
  # (CP4 in the workshop covers the manual cgroup path).
  if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope --quiet true 2>/dev/null; then
    exec systemd-run --user --scope --quiet \
      -p MemoryMax="$MEM" -p TasksMax="$PIDS" -- \
      unshare \
        --user --map-root-user \
        --uts --pid --mount --fork --mount-proc \
        --net --ipc --cgroup \
        bash -c "$inner_script"
  else
    printf 'mini-docker: warning: systemd-run --user not available; running without cgroup limits\n' >&2
    exec unshare \
      --user --map-root-user \
      --uts --pid --mount --fork --mount-proc \
      --net --ipc --cgroup \
      bash -c "$inner_script"
  fi
}

cmd_ps() {
  # crude but illustrative: anything under the user's mini-docker scopes.
  if command -v systemctl >/dev/null 2>&1; then
    local units
    units=$(systemctl --user list-units --type=scope --no-legend 2>/dev/null \
              | awk '/run-/{print $1}')
    if [ -n "$units" ]; then
      echo "$units"
    else
      echo "(no running mini-containers)"
    fi
  else
    echo "(systemctl --user not available)"
  fi
}

cmd_kill() {
  # Send SIGKILL directly into every scope's cgroup. `systemctl stop` would
  # send SIGTERM and wait the unit's full stop-timeout (~90s) — which the
  # container's PID 1 ignores. SIGKILL is unblockable and kernel-delivered,
  # so every process in the scope dies immediately and the unit goes away.
  if ! command -v systemctl >/dev/null 2>&1; then
    pkill -9 -f 'unshare.*--map-root-user' 2>/dev/null \
      && echo 'killed unshare processes' \
      || echo 'nothing to kill'
    return
  fi
  local units
  units=$(systemctl --user list-units --type=scope --no-legend 2>/dev/null \
            | awk '/run-/{print $1}')
  if [ -z "$units" ]; then
    echo '(no running mini-containers)'
    return
  fi
  local n=0
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    systemctl --user kill --signal=SIGKILL "$unit" 2>/dev/null || true
    printf 'killed: %s\n' "$unit"
    n=$((n+1))
  done <<<"$units"
  # Belt-and-braces: if anything escaped the cgroup somehow.
  pkill -9 -f 'unshare.*--map-root-user' 2>/dev/null || true
  printf '%d container(s) killed\n' "$n"
}

# ----- dispatch -----------------------------------------------------------
sub="${1:-help}"; shift || true
case "$sub" in
  run)            cmd_run  "$@" ;;
  ps)             cmd_ps   "$@" ;;
  kill|stop)      cmd_kill "$@" ;;
  help|-h|--help) cmd_help ;;
  *)              cmd_help; exit 2 ;;
esac
