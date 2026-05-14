#!/usr/bin/env bash
# pre-flight.sh — Paradox 2026 / "Build Your Own Mini Docker" workshop
# version: 3.0
# repo:    https://github.com/sayan-iitm/minidocker
#
# Bidirectional, deterministic check for whether this machine can run the
# workshop. Two phases:
#
#   A. fast probes — kernel, binaries, namespaces (informational hints).
#   B. end-to-end — the real workshop call: systemd-run --user --scope
#      wrapping unshare + pivot_root + exec inside an Alpine rootfs.
#
# The verdict is phase B. Phase A exists so you can see what's wrong fast
# if phase B fails. If phase B is GREEN, you are good — even if a phase A
# line went yellow.
#
# Philosophy: lean toward passing. We fail only on things that *will*
# break the workshop. Things that merely degrade (e.g. missing cgroup
# limits) are warnings, not failures. The workshop's mini-docker.sh has
# the same fall-through behaviour for those.
#
# Side effects:
#   - creates ~/paradox-workshop/
#   - caches the Alpine minirootfs (~3 MB) inside it
#   - writes ~/paradox-workshop/preflight-report.txt (color-stripped,
#     safe to paste into a GitHub Discussions thread)

set -u
SCRIPT_VERSION="3.0"

# ===== printing ==========================================================
if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  G="" R="" Y="" B="" N=""
fi
PASS=0; FAIL=0
ok()    { printf '  %sPASS%s  %s\n' "$G" "$N" "$*"; PASS=$((PASS+1)); }
bad()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$*"; FAIL=$((FAIL+1)); }
warn()  { printf '  %sWARN%s  %s\n' "$Y" "$N" "$*"; }
note()  { printf '          %s\n' "$*"; }
head_() { printf '\n%s[%s] %s%s\n' "$B" "$1" "$2" "$N"; }
hr()    { printf -- '-%.0s' {1..68}; printf '\n'; }

WORKDIR="${HOME}/paradox-workshop"
ROOTFS_DIR="$WORKDIR/rootfs"
TGZ="$WORKDIR/alpine-minirootfs.tar.gz"
mkdir -p "$WORKDIR"
REPORT="$WORKDIR/preflight-report.txt"

# Mirror stdout+stderr into the report file (color stripped) while keeping
# the terminal coloured. tty status was captured above this redirection.
exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT")) 2>&1

# ===== header ============================================================
hr
printf '%sParadox 2026 — pre-flight v%s%s\n' "$B" "$SCRIPT_VERSION" "$N"
printf 'report:   %s\n' "$REPORT"
printf 'date:     %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'user:     %s (uid=%s)\n' "$(id -un)" "$(id -u)"
hr
cat <<'BANNER'
GREEN = this machine will run the workshop. RED = it won't.

Phase A is fast probes. Phase B is the real end-to-end run. The verdict
is phase B. If phase B is green you are done, regardless of phase A.
BANNER

# ===== phase A ===========================================================
head_ "A" "fast environment probes"

# --- OS (hard stop if not Linux) --------------------------------------
case "$(uname -s)" in
  Linux) ok "OS: $(uname -srm)" ;;
  Darwin)
    bad "OS is macOS — workshop needs Linux (VM, WSL2, or cloud VM)"
    hr; printf '%sCannot continue on non-Linux.%s\n' "$R" "$N"; exit 1 ;;
  MINGW*|MSYS*|CYGWIN*)
    bad "running in Git-Bash/MSYS — use WSL2 Ubuntu instead"
    hr; printf '%sCannot continue.%s\n' "$R" "$N"; exit 1 ;;
  *)
    bad "OS '$(uname -s)' is not Linux"
    hr; printf '%sCannot continue.%s\n' "$R" "$N"; exit 1 ;;
esac

# --- distro (informational only) --------------------------------------
DISTRO_PRETTY="unknown"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_PRETTY="${PRETTY_NAME:-unknown}"
fi
ok "distro: $DISTRO_PRETTY"
if grep -qi microsoft /proc/version 2>/dev/null; then
  note "(WSL2 detected; ensure /etc/wsl.conf has [boot] systemd=true, then 'wsl --shutdown')"
fi

# --- kernel ≥ 5.10 ----------------------------------------------------
KVER=$(uname -r)
KMAJ=${KVER%%.*}
_rest=${KVER#*.}
KMIN=${_rest%%.*}
if { [ "${KMAJ:-0}" -gt 5 ] 2>/dev/null; } \
   || { [ "${KMAJ:-0}" -eq 5 ] 2>/dev/null && [ "${KMIN:-0}" -ge 10 ] 2>/dev/null; }; then
  ok "kernel $KVER (>= 5.10)"
else
  bad "kernel $KVER too old; need >= 5.10 — upgrade your distro"
fi

# --- required binaries -------------------------------------------------
for cmd in bash unshare mount umount tar; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd at $(command -v "$cmd")"
  else
    bad "$cmd not on PATH — install util-linux + coreutils"
  fi
done

# curl OR wget is acceptable
if command -v curl >/dev/null 2>&1; then
  ok "curl at $(command -v curl)"
elif command -v wget >/dev/null 2>&1; then
  ok "wget at $(command -v wget) (curl absent; wget is fine)"
else
  bad "neither curl nor wget on PATH — install one"
fi

# pivot_root usually lives in /usr/sbin, not on the user's PATH
PIVOT=$(command -v pivot_root 2>/dev/null || true)
if [ -z "$PIVOT" ]; then
  for d in /usr/sbin /sbin /usr/lib/klibc/bin; do
    if [ -x "$d/pivot_root" ]; then
      PIVOT="$d/pivot_root"
      break
    fi
  done
fi
if [ -n "$PIVOT" ]; then
  ok "pivot_root at $PIVOT"
else
  bad "pivot_root not found — install util-linux (or util-linux-extra on Ubuntu 24.04+, klibc-utils as fallback)"
fi

# --- unshare flags we use ---------------------------------------------
if command -v unshare >/dev/null 2>&1; then
  MISSING=()
  HELP=$(unshare --help 2>&1)
  for f in --map-root-user --mount-proc --fork --user --pid --mount --uts --net --ipc --cgroup; do
    if ! grep -q -- "$f" <<<"$HELP"; then
      MISSING+=("$f")
    fi
  done
  if [ "${#MISSING[@]}" -eq 0 ]; then
    ok "unshare supports every flag we need"
  else
    bad "unshare missing flags: ${MISSING[*]} — util-linux < 2.27?"
  fi
fi

# --- unprivileged user namespaces -------------------------------------
if unshare -Ur true 2>/dev/null; then
  ok "unprivileged user namespaces work (unshare -Ur)"
else
  bad "unshare -Ur denied — likely AppArmor (Ubuntu 24.04+) or kernel.unprivileged_userns_clone=0"
  note "Ubuntu 24.04+:"
  note "  echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/60-userns.conf"
  note "  sudo sysctl --system"
  note "Other distros:"
  note "  echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/60-userns.conf"
  note "  sudo sysctl --system"
fi

# --- cgroup v2 unified hierarchy --------------------------------------
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  ok "cgroup v2 unified hierarchy"
else
  bad "cgroup v2 not active — common on Amazon Linux 2; use AL2023, or add"
  note "  systemd.unified_cgroup_hierarchy=1 to GRUB_CMDLINE_LINUX and reboot"
fi

# --- systemd-run --user --scope (WARN only; mini-docker falls back) --
if command -v systemd-run >/dev/null 2>&1; then
  if systemd-run --user --scope --quiet true 2>/dev/null; then
    ok "systemd-run --user --scope works"
  else
    warn "systemd-run --user --scope failed — workshop will run without cgroup limits"
    note "to enable on a fresh SSH session:  sudo loginctl enable-linger \$USER  (then re-login)"
    note "on WSL2: enable systemd in /etc/wsl.conf; 'wsl --shutdown'"
  fi
else
  warn "systemd-run not found — workshop will run without cgroup limits"
fi

# ===== phase B ===========================================================
head_ "B" "end-to-end — actually run the workshop scenario"

# --- arch + URL --------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.3-x86_64.tar.gz" ;;
  aarch64|arm64) ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.3-aarch64.tar.gz" ;;
  *)             ALPINE_URL=""; bad "unsupported CPU arch '$ARCH'" ;;
esac

# --- disk --------------------------------------------------------------
AVAIL_MB=$(df -Pm "$WORKDIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${AVAIL_MB:-}" ] && [ "${AVAIL_MB}" -ge 200 ] 2>/dev/null; then
  ok "${AVAIL_MB} MB free in $WORKDIR"
else
  bad "only ${AVAIL_MB:-?} MB free in $WORKDIR (need >= 200)"
fi

# --- fetch rootfs (idempotent, cached) --------------------------------
# We verify with bin/busybox — the REAL file — never bin/sh. Alpine ships
# /bin/sh as an *absolute* symlink to /bin/busybox, which makes
# `[ -x bin/sh ]` from the host follow into the host's filesystem and
# silently lie about the rootfs's health.
fetch_rootfs() {
  rm -rf "$ROOTFS_DIR" "$TGZ"
  mkdir -p "$ROOTFS_DIR"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --max-time 60 -o "$TGZ" "$ALPINE_URL" 2>/dev/null
  else
    wget -q --tries=3 --timeout=60 -O "$TGZ" "$ALPINE_URL" 2>/dev/null
  fi
}

if [ -n "$ALPINE_URL" ]; then
  if [ -x "$ROOTFS_DIR/bin/busybox" ]; then
    ok "rootfs cached at $ROOTFS_DIR ($(du -sh "$ROOTFS_DIR" | cut -f1))"
  elif fetch_rootfs && tar -xpzf "$TGZ" -C "$ROOTFS_DIR" 2>/dev/null \
       && [ -x "$ROOTFS_DIR/bin/busybox" ]; then
    ok "rootfs downloaded and extracted ($(du -sh "$ROOTFS_DIR" | cut -f1))"
  else
    bad "rootfs not ready: download or extraction failed"
    note "wipe and retry:  rm -rf '$ROOTFS_DIR' '$TGZ' && bash $0"
  fi
fi

# --- the deciding test -------------------------------------------------
# Mirrors mini-docker.sh's CP5 path exactly.
build_inner() {
  # $1 = host path of the rootfs. Heredoc is unquoted so $1 is substituted
  # at compose time; \$PATH stays literal for the inner shell to expand.
  cat <<EOF
set -e
export PATH=/usr/sbin:/sbin:\$PATH:/usr/lib/klibc/bin
mount --make-rprivate /
mount --bind '$1' '$1'
mount --make-private '$1'
mkdir -p '$1/.old_root'
cd '$1'
pivot_root . .old_root
cd /
hash -r 2>/dev/null || true
mount -t proc proc /proc
umount -l /.old_root
rmdir /.old_root 2>/dev/null || true
echo SENTINEL_OK
head -n 1 /etc/os-release
EOF
}

if [ -x "$ROOTFS_DIR/bin/busybox" ]; then
  INNER=$(build_inner "$ROOTFS_DIR")
  UNSHARE_ARGS=(--user --map-root-user --uts --pid --mount --fork
                --mount-proc --net --ipc --cgroup)

  # `|| E2E_RC=$?` captures the real exit code; a trailing `|| true` would
  # discard it because $? would then be `true`'s exit code (always 0).
  E2E_RC=0
  if command -v systemd-run >/dev/null 2>&1 \
     && systemd-run --user --scope --quiet true 2>/dev/null; then
    E2E=$(systemd-run --user --scope --quiet \
            -p MemoryMax=100M -p TasksMax=64 -- \
            unshare "${UNSHARE_ARGS[@]}" bash -c "$INNER" 2>&1) || E2E_RC=$?
    MODE="with systemd-run cgroup limits (MemoryMax=100M, TasksMax=64)"
  else
    E2E=$(unshare "${UNSHARE_ARGS[@]}" bash -c "$INNER" 2>&1) || E2E_RC=$?
    MODE="without cgroup limits (systemd-run --user unavailable)"
  fi

  if [ "$E2E_RC" -eq 0 ] && grep -q SENTINEL_OK <<<"$E2E"; then
    OS_LINE=$(grep -m1 -i NAME= <<<"$E2E" || echo Alpine)
    ok "namespaces + bind + pivot_root + Alpine exec succeeded"
    note "mode:    $MODE"
    note "alpine:  $OS_LINE"
  else
    bad "end-to-end test failed (rc=$E2E_RC)"
    note "trace (first 12 lines):"
    while IFS= read -r line; do
      note "  $line"
    done < <(printf '%s\n' "$E2E" | head -n 12)
    note ""
    note "Look back at phase A — most failures of this test are explained there."
    note "If phase A was clean, check for AppArmor/SELinux denials:"
    note "  sudo dmesg | tail -30   # look for 'audit' / 'denied' / 'AVC'"
  fi
  rmdir "$ROOTFS_DIR/.old_root" 2>/dev/null || true
else
  bad "end-to-end test skipped — rootfs not ready (fix above first)"
fi

# ===== verdict ===========================================================
hr
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '%sALL GREEN — %d/%d. This machine can run the workshop.%s\n' "$G" "$PASS" "$TOTAL" "$N"
  printf '\nReport: %s\n' "$REPORT"
  echo  "Bring this machine on workshop day. Re-run the night before."
  hr
  exit 0
else
  printf '%s%d failed, %d passed.%s Fix the RED lines above and re-run.\n' "$R" "$FAIL" "$PASS" "$N"
  printf '\nStuck? Paste this report in our GitHub Discussions:\n  %s\n' "$REPORT"
  hr
  exit 1
fi
