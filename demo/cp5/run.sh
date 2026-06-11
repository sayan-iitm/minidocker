#!/usr/bin/env bash
# CP5 — cgroups: a limit the kernel actually enforces
#
# THE IDEA: namespaces control what a process can SEE. cgroups control what it
# can USE — CPU, memory, number of processes. Here's the simplest possible demo:
# cap memory at 50 MB, then try to grab 200 MB. The kernel kills it. Done.
#
# We use systemd-run to make the cgroup for us (--user --scope = run it here, as
# us, in the foreground). Doing cgroups by hand means writing to /sys/fs/cgroup —
# see docs/cgroups.md if you're curious; it's the same idea, more typing.
#
# Two limits, not one:
#   MemoryMax=50M      cap RAM at 50 MB
#   MemorySwapMax=0    AND forbid swap
# Why both? MemoryMax caps RAM only. When our process grows past 50 MB the kernel
# reclaims by paging that memory out to SWAP — so on any machine with a swapfile
# the allocation just succeeds quietly and nothing gets killed. Denying swap too
# means there is nowhere for the memory to go, so the cgroup OOM killer fires.
#
# No namespaces, no rootfs here — just the limit, on its own, so you can see it work.

set -e

if ! command -v systemd-run >/dev/null 2>&1; then
  echo "systemd-run not found — this demo needs systemd (the pre-flight checks for it)."
  exit 1
fi

echo "Starting a process capped at MemoryMax=50M, MemorySwapMax=0, asking it to allocate 200M..."
echo

# `|| status=$?` so the script keeps going after the process is killed.
systemd-run --user --scope --quiet -p MemoryMax=50M -p MemorySwapMax=0 -- \
  bash -c '
    echo "inside the cgroup. trying to allocate ~200 MB of memory..."
    junk=$(head -c 200000000 /dev/zero | tr "\0" "x")   # build a ~200MB string
    echo "allocated it all — the limit did NOT hold (unexpected!)"
  ' || status=$?

echo
if [ "${status:-0}" -eq 137 ]; then
  echo "exit 137 = killed by SIGKILL. The kernel's OOM killer enforced the 50M cap."
  echo "^ that is a cgroup doing its job. namespaces isolate; cgroups limit."
elif [ "${status:-0}" -ne 0 ]; then
  echo "exit ${status} — the process was killed before it finished. The cgroup limit"
  echo "held (137 is the usual code for an OOM SIGKILL). namespaces isolate; cgroups limit."
else
  echo "exit 0 — it allocated everything, so the cap didn't bite."
  echo "if MemorySwapMax isn't honoured your kernel may lack swap accounting; otherwise"
  echo "check that the memory controller is delegated (the pre-flight reports this)."
fi
