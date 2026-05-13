#!/usr/bin/env bash
# pre-flight.sh — Paradox 2026 workshop
# "Build Your Own Mini Docker: Understanding Containers from Scratch"
# version: 2.0   (strict mode)
# repo:    https://github.com/sayan-iitm/minidocker
#
# Run this inside the Linux you plan to bring on workshop day.
#
#   curl -sSL https://raw.githubusercontent.com/sayan-iitm/minidocker/refs/heads/master/pre-flight.sh | bash
#   or:  bash pre-flight.sh
#
# This script is INTENTIONALLY strict. Every check that could fail on
# workshop day fails here, with the exact fix printed. Run it today, run
# it tomorrow, run it the night before. Green is the entry ticket.
#
# Side effects:
#   - creates ~/paradox-workshop/
#   - downloads alpine-minirootfs (~3 MB) into ~/paradox-workshop/
#   - writes a full diagnostic transcript to
#     ~/paradox-workshop/preflight-report.txt
# That's it. No system-wide installs, no sudo unless YOU run the AppArmor
# sysctl fix yourself.

set -u
SCRIPT_VERSION="2.0"
SCRIPT_DATE="2026-05-13"

# --- pretty printing ------------------------------------------------------
# Detect tty BEFORE we redirect stdout below — colors should still light up
# in the user's terminal, even though the file gets plain text via sed.
if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; N=""
fi
green()  { printf '%s%s%s\n' "$G" "$*" "$N"; }
red()    { printf '%s%s%s\n' "$R" "$*" "$N"; }
yellow() { printf '%s%s%s\n' "$Y" "$*" "$N"; }
bold()   { printf '%s%s%s\n' "$B" "$*" "$N"; }
hr()     { printf -- '-%.0s' {1..68}; echo; }

PASS=0; FAIL=0
# Each entry: "NN|short-name|fix-instructions" (newline-separated multi-line fix ok)
FIXES=()

WORKDIR="${HOME}/paradox-workshop"
mkdir -p "$WORKDIR"
REPORT="$WORKDIR/preflight-report.txt"

# Mirror everything to the report file in addition to stdout. The file gets
# a color-stripped copy so it pastes cleanly into a GitHub Discussions thread;
# the terminal keeps full color because we captured tty status above.
exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT")) 2>&1

ok() {
  green "  PASS  $1"
  PASS=$((PASS+1))
}
fail() {
  local check_num="$1" short="$2" reason="$3" fix="$4"
  red "  FAIL  [$check_num] $short — $reason"
  if [ -n "$fix" ]; then
    while IFS= read -r line; do
      yellow "        $line"
    done <<<"$fix"
  fi
  FAIL=$((FAIL+1))
  FIXES+=("$check_num|$short|$fix")
}

# ==========================================================================
hr
bold "Paradox 2026 — Build Your Own Mini Docker — pre-flight v$SCRIPT_VERSION"
echo "report:  $REPORT"
echo "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "user:    $(id -un) (uid=$(id -u))"
hr
cat <<'BANNER'
This workshop is hands-on. The entry ticket is a green pre-flight on the
laptop you'll bring on workshop day.

You bring your own Linux. Any of these works:
  - native Linux install (Ubuntu, Debian, Fedora, Arch, ...)
  - VMware/VirtualBox VM running Ubuntu 22.04+ or Debian 12+, >= 2 GB RAM
  - WSL2 + Ubuntu, with systemd enabled (Microsoft docs)
  - a personal cloud VM (DigitalOcean $4 / AWS t3.small / GCP e2-small)

We are NOT providing a shared SSH box. Run this script inside the Linux
you picked. If anything is red below, the FIX is printed right under it,
and the full checklist is at the bottom. Re-run until you see "All green".

BANNER
hr

# ==========================================================================
# CHECK 01 — OS is Linux
# ==========================================================================
bold "[01/14] Operating system"
echo "  why: unshare(1), namespaces, and cgroups exist only on Linux."
case "$(uname -s)" in
  Linux)
    ok "Linux detected ($(uname -srm))"
    ;;
  Darwin)
    fail 01 "Not Linux (macOS)" "unshare is a Linux syscall; cannot run natively on Mac" \
"You need a Linux environment. Pick one:
  - install UTM (free) or VMware Fusion, run an Ubuntu 22.04+ VM
  - rent a cloud VM (DigitalOcean \$4 droplet, AWS t3.small, GCP e2-small)
  - and re-run this script INSIDE that Linux"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    fail 01 "Not Linux (Windows shell)" "you are running this in Git Bash / MSYS / Cygwin, not inside Linux" \
"Run this script INSIDE WSL2 Ubuntu, not on Windows:
  1. open PowerShell (admin) and run:    wsl --install -d Ubuntu
  2. reboot, set up an Ubuntu user account when prompted
  3. open Ubuntu from the Start menu
  4. then re-run this script from the Ubuntu shell"
    ;;
  *)
    fail 01 "Unknown OS '$(uname -s)'" "neither Linux nor a recognised non-Linux shell" \
"Run this script inside a Linux environment (see banner above)."
    ;;
esac

# ==========================================================================
# CHECK 02 — Distribution
# ==========================================================================
bold "[02/14] Linux distribution"
echo "  why: distro-specific defaults (e.g. Ubuntu 24.04 AppArmor) affect later checks."
DISTRO_ID="unknown"
DISTRO_VER=""
DISTRO_PRETTY="unknown"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_VER="${VERSION_ID:-}"
  DISTRO_PRETTY="${PRETTY_NAME:-unknown}"
  ok "$DISTRO_PRETTY"
else
  fail 02 "No /etc/os-release" "cannot identify your distribution" \
"This is unusual on modern Linux. If you built your own minimal image, install lsb-release or
create /etc/os-release with at least ID= and VERSION_ID= lines."
fi

# Detect WSL — useful below
IS_WSL=no
if grep -qi 'microsoft' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  IS_WSL=yes
  echo "  note: WSL2 environment detected"
fi

# ==========================================================================
# CHECK 03 — Kernel version
# ==========================================================================
bold "[03/14] Kernel version"
echo "  why: cgroup v2 delegation and unprivileged userns features need >= 5.10."
KVER=$(uname -r)
KMAJ=$(echo "$KVER" | cut -d. -f1)
KMIN=$(echo "$KVER" | cut -d. -f2)
if [ "$KMAJ" -gt 5 ] 2>/dev/null || { [ "$KMAJ" -eq 5 ] 2>/dev/null && [ "$KMIN" -ge 10 ] 2>/dev/null; }; then
  ok "kernel $KVER (>= 5.10)"
else
  fail 03 "Kernel $KVER too old" "want >= 5.10 for the workshop's cgroups + userns features" \
"Update your distro to a current release, or your VM image to one with a newer kernel:
  - Ubuntu 22.04+ ships 5.15+; Ubuntu 24.04 ships 6.8.
  - Debian 12 (Bookworm) ships 6.1; Debian 13 (Trixie) ships 6.x.
  - On WSL2: 'wsl --update' in PowerShell, then 'wsl --shutdown'."
fi

# ==========================================================================
# CHECK 04 — util-linux unshare command + flags we need
# ==========================================================================
bold "[04/14] unshare(1) command"
echo "  why: unshare is the user-space front-end to the namespace syscalls."
if ! command -v unshare >/dev/null 2>&1; then
  fail 04 "unshare not found" "util-linux package missing or not on PATH" \
"Install util-linux for your distro:
  - Ubuntu/Debian:  sudo apt update && sudo apt install -y util-linux
  - Fedora/RHEL:    sudo dnf install -y util-linux
  - Arch:           sudo pacman -S util-linux"
else
  UVER=$(unshare --version 2>/dev/null | head -n1 || true)
  echo "  $UVER"
  MISSING=()
  for flag in --map-root-user --mount-proc --fork --user --pid --mount; do
    if ! unshare --help 2>&1 | grep -q -- "$flag"; then
      MISSING+=("$flag")
    fi
  done
  if [ ${#MISSING[@]} -eq 0 ]; then
    ok "unshare has every flag we need"
  else
    fail 04 "unshare missing flags" "your unshare lacks: ${MISSING[*]}" \
"Your util-linux is too old (need >= 2.27). Update via your package manager."
  fi
fi

# pivot_root also ships with util-linux but lives in /usr/sbin or /sbin —
# neither of which is on every user's PATH. We probe broadly: PATH first,
# then common locations, then a capped find as last resort. Distinguish
# "present but not executable" from "absent entirely" — they have different
# fixes.
PIVOT_PATH=""
PIVOT_NONEXEC=""
if command -v pivot_root >/dev/null 2>&1; then
  PIVOT_PATH=$(command -v pivot_root)
else
  # Ubuntu 26.04+ moved pivot_root out of util-linux into klibc-utils,
  # which installs to /usr/lib/klibc/bin. Search that too.
  for d in /usr/sbin /sbin /usr/bin /bin /usr/local/sbin /usr/local/bin /usr/lib/klibc/bin; do
    if [ -x "$d/pivot_root" ]; then
      PIVOT_PATH="$d/pivot_root"
      break
    elif [ -e "$d/pivot_root" ]; then
      PIVOT_NONEXEC="$d/pivot_root"
    fi
  done
fi

if [ -n "$PIVOT_PATH" ]; then
  ok "pivot_root at $PIVOT_PATH"
elif [ -n "$PIVOT_NONEXEC" ]; then
  fail 04 "pivot_root present but not executable" "$PIVOT_NONEXEC exists, has no exec bit" \
"Fix the permission:
  sudo chmod +x $PIVOT_NONEXEC
Then re-run this script. If it persists, your util-linux package may be
half-installed; reinstall it (see below)."
else
  # Last-resort discovery so the error message points at the actual binary.
  FOUND=$(timeout 5 find / -name pivot_root -type f 2>/dev/null | head -3)
  PKG_HINT=""
  case "$DISTRO_ID" in
    ubuntu|debian)
      # Modern Debian/Ubuntu split util-linux: pivot_root lives in
      # util-linux-extra. klibc-utils is a fallback (its binary is at
      # /usr/lib/klibc/bin/pivot_root, which we add to PATH separately).
      PKG_HINT="sudo apt update && sudo apt install -y util-linux-extra
    (fallback if util-linux-extra is unavailable: sudo apt install -y klibc-utils)"
      ;;
    fedora|rhel|centos|rocky|almalinux) PKG_HINT="sudo dnf reinstall -y util-linux util-linux-core" ;;
    arch|manjaro) PKG_HINT="sudo pacman -S util-linux klibc-utils" ;;
    alpine) PKG_HINT="sudo apk add util-linux klibc-utils" ;;
    *) PKG_HINT="install util-linux-extra (or util-linux on older distros) — one of them ships pivot_root" ;;
  esac
  EXTRA=""
  if [ -n "$FOUND" ]; then
    EXTRA="
However, a 'find /' did locate a pivot_root binary at:
$(echo "$FOUND" | sed 's/^/  /')
If that path is correct, you can either symlink it onto /usr/sbin:
  sudo ln -s $(echo "$FOUND" | head -n1) /usr/sbin/pivot_root
or set PIVOT_ROOT_BIN to that path before running mini-docker."
  fi
  fail 04 "pivot_root not found anywhere on PATH or in standard sbin dirs" "needed for CP4's mount switch" \
"It usually lives in util-linux. Install or reinstall the package for $DISTRO_ID:
  $PKG_HINT$EXTRA"
fi

# ==========================================================================
# CHECK 05 — Unprivileged user namespaces work
# ==========================================================================
bold "[05/14] Unprivileged user namespaces"
echo "  why: the whole workshop runs without sudo, by mapping you to root inside the namespace."
if unshare -Ur echo ok >/dev/null 2>&1; then
  ok "unshare -Ur works"
else
  FIX=""
  # Distro-specific advice first.
  if [ "$DISTRO_ID" = "ubuntu" ] && [ -n "$DISTRO_VER" ]; then
    UMAJ=$(echo "$DISTRO_VER" | cut -d. -f1)
    if [ "$UMAJ" -ge 24 ]; then
      FIX="Likely cause: Ubuntu 24.04+ AppArmor restriction on unprivileged userns.
Persistent fix (one time, needs sudo):
  echo 'kernel.apparmor_restrict_unprivileged_userns=0' | \\
    sudo tee /etc/sysctl.d/60-userns.conf
  sudo sysctl --system
Then re-run this script."
    fi
  fi
  if [ -z "$FIX" ] && [ -r /proc/sys/kernel/unprivileged_userns_clone ]; then
    UUC=$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 0)
    if [ "$UUC" != "1" ]; then
      FIX="Your kernel has unprivileged user namespaces disabled.
Persistent fix:
  echo 'kernel.unprivileged_userns_clone=1' | \\
    sudo tee /etc/sysctl.d/60-userns.conf
  sudo sysctl --system"
    fi
  fi
  if [ -z "$FIX" ]; then
    FIX="Cause unclear. Check 'dmesg | tail -20' for denials, or open a thread on the
workshop GitHub Discussions with this report file attached:
  $REPORT"
  fi
  fail 05 "unshare -Ur denied" "kernel or AppArmor is blocking unprivileged user namespaces" "$FIX"
fi

# ==========================================================================
# CHECK 06 — cgroups v2 unified hierarchy
# ==========================================================================
bold "[06/14] cgroups v2"
echo "  why: CP5 uses cgroups for memory + pids limits."
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  ok "cgroups v2 unified hierarchy mounted at /sys/fs/cgroup"
else
  fail 06 "cgroups v2 not detected" "/sys/fs/cgroup/cgroup.controllers missing" \
"You're on cgroups v1 only, which we don't support in the workshop.
Modern distros (Ubuntu 22.04+, Debian 12+, Fedora 38+) ship v2 by default.
On older systems, append this to /etc/default/grub on the GRUB_CMDLINE_LINUX line:
  systemd.unified_cgroup_hierarchy=1
then 'sudo update-grub && sudo reboot'.
On WSL2: 'wsl --update' usually moves you to v2."
fi

# ==========================================================================
# CHECK 07 — cgroup v2 user delegation (memory + pids)
# ==========================================================================
bold "[07/14] cgroup v2 delegation to your user"
echo "  why: systemd-run --user --scope needs memory + pids controllers delegated."
USERSLICE="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service"
if [ -d "$USERSLICE" ] && [ -r "$USERSLICE/cgroup.controllers" ]; then
  CTRLS=$(cat "$USERSLICE/cgroup.controllers")
  echo "  delegated: $CTRLS"
  if echo "$CTRLS" | grep -qw memory && echo "$CTRLS" | grep -qw pids; then
    ok "memory + pids delegated"
  else
    fail 07 "memory and/or pids not delegated" "your user slice lacks the controllers we need" \
"Add a systemd drop-in to delegate them:
  sudo mkdir -p /etc/systemd/system/user@.service.d
  printf '[Service]\\nDelegate=memory pids cpu io\\n' | \\
    sudo tee /etc/systemd/system/user@.service.d/delegate.conf
  sudo systemctl daemon-reexec
  loginctl terminate-user \$USER     # log back in after this
Then re-run this script."
  fi
else
  fail 07 "No user@$(id -u).service slice" "you are likely not in a logind session, or systemd-user is not running" \
"On WSL2: enable systemd ('echo -e \"[boot]\\nsystemd=true\" | sudo tee /etc/wsl.conf'
then 'wsl --shutdown' in PowerShell). On servers: 'sudo loginctl enable-linger \$USER'."
fi

# ==========================================================================
# CHECK 08 — systemd present and modern
# ==========================================================================
bold "[08/14] systemd version"
echo "  why: we use 'systemd-run --user --scope' for the cgroup wrapper in CP5."
if command -v systemctl >/dev/null 2>&1; then
  SDVER=$(systemctl --version 2>/dev/null | head -n1)
  echo "  $SDVER"
  SD_NUM=$(echo "$SDVER" | grep -oE '[0-9]+' | head -n1 || echo 0)
  if [ "${SD_NUM:-0}" -ge 244 ] 2>/dev/null; then
    ok "systemd $SD_NUM (>= 244)"
  else
    fail 08 "systemd too old ($SD_NUM)" "want >= 244 for clean cgroup v2 delegation" \
"Update your distro. systemd 244 shipped late 2019; any current LTS has it."
  fi
else
  fail 08 "systemctl not found" "systemd not installed or not the init" \
"You appear to be on a non-systemd Linux. The workshop CP5 step depends on
systemd-run. Switch to a systemd-based distro VM (Ubuntu/Debian/Fedora) or
use WSL2 + Ubuntu with systemd enabled."
fi

# ==========================================================================
# CHECK 09 — systemd-run --user --scope actually works
# ==========================================================================
bold "[09/14] systemd-run --user --scope"
echo "  why: this is exactly the command CP5 wraps the container with."
if command -v systemd-run >/dev/null 2>&1; then
  if systemd-run --user --scope --quiet true 2>/dev/null; then
    ok "systemd-run --user --scope works"
  else
    SCOPE_ERR=$(systemd-run --user --scope --quiet true 2>&1 || true)
    FIX="systemd-run --user failed with: $SCOPE_ERR
Common causes and fixes:
  - WSL2 without systemd:
      echo -e '[boot]\\nsystemd=true' | sudo tee /etc/wsl.conf
      then in PowerShell:  wsl --shutdown
      reopen Ubuntu, re-run this script
  - SSH session on a server without 'lingering' for your user:
      sudo loginctl enable-linger \$USER
      log out and back in
  - DBUS_SESSION_BUS_ADDRESS not set (raw ssh, no logind):
      logout and back in via a 'loginctl enable-linger \$USER' session"
    fail 09 "systemd-run --user --scope failed" "your user session can't create transient scopes" "$FIX"
  fi
else
  fail 09 "systemd-run not found" "systemd userspace tools missing" \
"Install systemd-run (it ships with systemd on every modern distro). On WSL2 enable systemd."
fi

# ==========================================================================
# CHECK 10 — Disk space in workdir
# ==========================================================================
bold "[10/14] Disk space in $WORKDIR"
echo "  why: Alpine rootfs ~5 MB, plus headroom for /tmp inside the container."
AVAIL_MB=$(df -Pm "$WORKDIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -ge 200 ]; then
  ok "$AVAIL_MB MB free in $WORKDIR"
else
  fail 10 "Only ${AVAIL_MB:-?} MB free" "want >= 200 MB for safety" \
"Free up disk in your home partition, or move the workdir:
  rm -rf ~/paradox-workshop
  mkdir -p /path/with/more/space/paradox-workshop
  ln -s /path/with/more/space/paradox-workshop ~/paradox-workshop"
fi

# ==========================================================================
# CHECK 11 — Internet reaches dl-cdn.alpinelinux.org
# ==========================================================================
bold "[11/14] Network reachability to Alpine CDN"
echo "  why: we fetch the rootfs from dl-cdn.alpinelinux.org."
if command -v curl >/dev/null 2>&1; then
  if curl -fsSL --max-time 8 -o /dev/null https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/ 2>/dev/null; then
    ok "dl-cdn.alpinelinux.org reachable over HTTPS"
  else
    fail 11 "Cannot reach dl-cdn.alpinelinux.org" "network or proxy is blocking the Alpine CDN" \
"If you're on a corporate or campus network, try:
  - tether to your phone hotspot and re-run
  - export HTTPS_PROXY=... if your network needs a proxy
  - or download the rootfs by hand (see repo README, 'Offline rootfs')"
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q --timeout=8 --tries=1 -O /dev/null https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/ 2>/dev/null; then
    ok "dl-cdn.alpinelinux.org reachable (via wget)"
  else
    fail 11 "Cannot reach dl-cdn.alpinelinux.org" "wget could not GET the CDN" \
"See network/proxy advice above."
  fi
else
  fail 11 "Neither curl nor wget" "no HTTP client installed" \
"Install one:
  sudo apt install -y curl     # Debian/Ubuntu
  sudo dnf install -y curl     # Fedora"
fi

# ==========================================================================
# CHECK 12 — Download + extract Alpine rootfs (idempotent)
# ==========================================================================
bold "[12/14] Alpine rootfs in $WORKDIR/rootfs"
echo "  why: this is the filesystem our mini-container pivots into."
ROOTFS_DIR="$WORKDIR/rootfs"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.3-x86_64.tar.gz" ;;
  aarch64|arm64) ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.3-aarch64.tar.gz" ;;
  *) ALPINE_URL=""; ;;
esac

if [ -d "$ROOTFS_DIR" ] && [ -x "$ROOTFS_DIR/bin/sh" ]; then
  ok "rootfs already extracted at $ROOTFS_DIR ($(du -sh "$ROOTFS_DIR" 2>/dev/null | cut -f1))"
elif [ -z "$ALPINE_URL" ]; then
  fail 12 "Unsupported CPU arch '$ARCH'" "no prebuilt Alpine minirootfs for your arch" \
"You're on an unusual arch. If you're on Apple Silicon under macOS, use a Linux VM
that's either x86_64 (via Rosetta/QEMU) or aarch64. If you're on a niche arch,
mail the instructor — we'll figure out a rootfs together."
else
  echo "  downloading $ALPINE_URL"
  ALPINE_TGZ="$WORKDIR/alpine-minirootfs.tar.gz"
  if curl -fsSL -o "$ALPINE_TGZ" "$ALPINE_URL" 2>/dev/null \
     || wget -qO "$ALPINE_TGZ" "$ALPINE_URL" 2>/dev/null; then
    mkdir -p "$ROOTFS_DIR"
    if tar -xzf "$ALPINE_TGZ" -C "$ROOTFS_DIR" 2>/dev/null; then
      ok "rootfs extracted ($(du -sh "$ROOTFS_DIR" | cut -f1))"
    else
      fail 12 "tar extract failed" "the downloaded tarball did not extract" \
"Delete $ALPINE_TGZ and re-run. If it keeps failing, your /tmp or home filesystem
may be out of space or read-only."
    fi
  else
    fail 12 "Download failed" "could not GET $ALPINE_URL" \
"Re-run after network fix (see check 11)."
  fi
fi

# ==========================================================================
# CHECK 13 — Full pivot_root smoke test inside a userns
# ==========================================================================
bold "[13/14] End-to-end pivot_root inside unprivileged userns"
echo "  why: this is what CP4 actually does. The only test that catches the"
echo "       'unshare -Ur passes but bind mount inside denied' failure mode."
if [ ! -x "$ROOTFS_DIR/bin/sh" ]; then
  fail 13 "Cannot run end-to-end test" "rootfs missing — check 12 must pass first" \
"Resolve check 12, then re-run."
else
  # Non-destructive: we run the full pivot, then exit. We capture stdout
  # and a sentinel to verify the pivot actually happened.
  set +e
  E2E_OUT=$(unshare \
      --user --map-root-user \
      --uts --pid --mount --fork --mount-proc \
      --net --ipc --cgroup \
      bash -c "
        set -e
        # 0. PATH order matters: standard sbin paths first (in case the
        #    caller's PATH is sparse), then the user's PATH (which has
        #    /usr/bin where util-linux mount/umount/pivot_root live),
        #    THEN klibc-utils at the very end. klibc must be last because
        #    it ships a minimal mount binary that lacks --make-rprivate;
        #    we only want klibc's pivot_root as a fallback, never its mount.
        export PATH=/usr/sbin:/sbin:\$PATH:/usr/lib/klibc/bin
        # 1. systemd marks / as MS_SHARED. pivot_root refuses when the new-root
        #    or its parent is shared, so de-shareify everything inside our
        #    private mount namespace first. Affects host nothing.
        mount --make-rprivate / 2>&1
        # 2. Make the new root a mount point.
        mount --bind '$ROOTFS_DIR' '$ROOTFS_DIR' 2>&1
        mount --make-private '$ROOTFS_DIR' 2>&1
        mkdir -p '$ROOTFS_DIR/.old_root'
        cd '$ROOTFS_DIR'
        pivot_root . .old_root 2>&1
        cd /
        # 3. bash cached /usr/bin/mount before pivot_root. Those paths don't
        #    exist in the Alpine rootfs. Flush the hash so PATH lookup re-runs
        #    against the new filesystem (Alpine's /bin/mount via busybox).
        hash -r 2>/dev/null || true
        mount -t proc proc /proc 2>&1
        umount -l /.old_root 2>&1 || true
        echo SENTINEL_PIVOT_OK
        cat /etc/os-release | head -1
      " 2>&1)
  E2E_RC=$?
  set -e
  if [ $E2E_RC -eq 0 ] && echo "$E2E_OUT" | grep -q SENTINEL_PIVOT_OK; then
    ok "full mount-bind + pivot_root + mount proc + umount old root succeeded"
  else
    fail 13 "End-to-end pivot test failed" "your kernel refuses one of the steps the workshop relies on" \
"Trace from the captured output (first lines):
$(echo "$E2E_OUT" | head -10 | sed 's/^/    /')

Most common cause: kernel < 5.10 or a security module (AppArmor/SELinux)
denying bind-mount inside a user namespace. Re-check items 03 and 05,
then re-run."
  fi
  # Clean up any stale .old_root that pivot+umount left behind on failure.
  rmdir "$ROOTFS_DIR/.old_root" 2>/dev/null || true
fi

# ==========================================================================
# CHECK 14 — Container can run a real command from the rootfs
# ==========================================================================
bold "[14/14] Run a real Alpine command inside the container"
echo "  why: confirms the rootfs is wired (PATH, /proc, /bin/sh, real binaries)."
if [ ! -x "$ROOTFS_DIR/bin/sh" ]; then
  fail 14 "Skipped" "needs check 12 to pass" ""
else
  set +e
  # Mirror check 13's inner script exactly, then exec Alpine binaries at the
  # end. Keeping the structures identical guarantees that any difference in
  # outcome is attributable to the rootfs binaries, not to a divergent setup.
  E2E2_OUT=$(unshare \
      --user --map-root-user \
      --uts --pid --mount --fork --mount-proc \
      --net --ipc --cgroup \
      bash -c "
        set -e
        # Same PATH layout as check 13 — see the comment there for why klibc
        # has to live at the END of PATH, not the front.
        export PATH=/usr/sbin:/sbin:\$PATH:/usr/lib/klibc/bin
        mount --make-rprivate / 2>&1
        mount --bind '$ROOTFS_DIR' '$ROOTFS_DIR' 2>&1
        mount --make-private '$ROOTFS_DIR' 2>&1
        mkdir -p '$ROOTFS_DIR/.old_root'
        cd '$ROOTFS_DIR'
        pivot_root . .old_root 2>&1
        cd /
        hash -r 2>/dev/null || true
        mount -t proc proc /proc 2>&1
        umount -l /.old_root 2>&1 || true
        rmdir /.old_root 2>/dev/null || true
        # If we got here, the namespace plumbing is sound. Now prove the
        # rootfs binaries execute.
        cat /etc/os-release | head -3
        echo SENTINEL_ALPINE_OK
        ps -ef | wc -l
      " 2>&1)
  E2E2_RC=$?
  set -e
  if [ $E2E2_RC -eq 0 ] && echo "$E2E2_OUT" | grep -q SENTINEL_ALPINE_OK; then
    PROC_COUNT=$(echo "$E2E2_OUT" | tail -n1)
    OS_LINE=$(echo "$E2E2_OUT" | grep -m1 -i 'NAME=' || echo "Alpine")
    ok "Alpine binary ran ($OS_LINE; $PROC_COUNT process(es) visible)"
  else
    fail 14 "Alpine command failed in the container" "rootfs binaries don't execute under our namespace stack" \
"Output:
$(echo "$E2E2_OUT" | head -10 | sed 's/^/    /')
If checks 13 passed but 14 failed, your Alpine extraction is incomplete.
Delete and re-extract:
  rm -rf $ROOTFS_DIR
  re-run this script"
  fi
  rmdir "$ROOTFS_DIR/.old_root" 2>/dev/null || true
fi

# ==========================================================================
# Summary
# ==========================================================================
hr
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "$(bold "All green — $PASS/$TOTAL passed.")"
  echo
  echo "You're ready. Bring this laptop on workshop day."
  echo "Re-run this script the night before to confirm nothing rotted."
  echo
  echo "Workdir: $WORKDIR"
  echo "Report:  $REPORT"
  hr
  exit 0
else
  red "$(bold "$FAIL check(s) failed, $PASS passed. Fix and re-run.")"
  echo
  bold "Fix checklist (in order):"
  for entry in "${FIXES[@]}"; do
    # Use parameter expansion, not `read`, so multi-line fixes survive.
    num="${entry%%|*}"
    rest="${entry#*|}"
    short="${rest%%|*}"
    fix="${rest#*|}"
    echo
    yellow "  [$num] $short"
    if [ -n "$fix" ]; then
      echo "$fix" | sed 's/^/      /'
    else
      echo "      (resolves automatically once the dependent checks pass)"
    fi
  done
  echo
  hr
  bold "What to do next"
  cat <<EOF
  1. Work through the checklist top-to-bottom. Some fixes (e.g. enabling
     systemd on WSL2) unblock multiple later checks; do them first.
  2. Re-run this script after each fix.
  3. Stuck? Open a thread on the workshop's GitHub Discussions and PASTE
     this entire file:
         $REPORT
     Don't paraphrase — paste it. We'll respond within a day.
  4. We will NOT debug fresh installs at the door on workshop day. Run
     this script now so you have days to fix things.
EOF
  hr
  exit 1
fi
