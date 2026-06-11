#!/usr/bin/env bash
# micro-docker.sh — the simplest possible container: namespaces + chroot.
# A stripped-down sibling of mini-docker.sh for the Paradox 2026 workshop.
# repo: https://github.com/sayan-iitm/minidocker
#
# No pivot_root dance, no cgroups, no systemd-run — just `unshare` + `chroot`.
# chroot only changes what "/" points at; the old root stays mounted underneath,
# so a privileged process can climb back out (the classic chroot escape).
# mini-docker.sh does it properly with pivot_root + umount. Think of this as the
# "looks isolated" version and mini-docker as the "is isolated" version.
#
# Usage:
#   ./micro-docker.sh run <rootfs-dir> [cmd...]   # default cmd: /bin/sh
#   ./micro-docker.sh help
#
# rootfs is a directory laid out like an Alpine minirootfs; the pre-flight
# extracts one at ~/paradox-workshop/rootfs.

set -euo pipefail

ROOTFS_DEFAULT="${HOME}/paradox-workshop/rootfs"

die() { printf 'micro-docker: %s\n' "$*" >&2; exit 1; }

cmd_help() {
  cat <<'EOF'
micro-docker — a container in a dozen lines of bash (namespaces + chroot).

usage:
  micro-docker run <rootfs-dir> [cmd...]   # default cmd: /bin/sh
  micro-docker help
EOF
}

cmd_run() {
  local rootfs="${1:-$ROOTFS_DEFAULT}"; shift || true
  [ -x "$rootfs/bin/sh" ] || die "no /bin/sh inside rootfs: $rootfs"
  local cmd=("${@:-/bin/sh}")

  # user + UTS + PID + mount namespaces, then chroot into the rootfs. The inner
  # shell sets the hostname and mounts a fresh /proc (so `ps` reflects our PID
  # namespace), then execs the requested command.
  exec unshare --user --map-root-user --uts --pid --mount --fork \
    chroot "$rootfs" /bin/sh -c '
      hostname micro-container 2>/dev/null || true
      mount -t proc proc /proc 2>/dev/null || true
      exec "$@"
    ' _ "${cmd[@]}"
}

sub="${1:-help}"; shift || true
case "$sub" in
  run)            cmd_run "$@" ;;
  help|-h|--help) cmd_help ;;
  *)              cmd_help; exit 2 ;;
esac
