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
# No namespaces, no rootfs here — just the limit, on its own, so you can see it work.

set -e

if ! command -v systemd-run >/dev/null 2>&1; then
  echo "systemd-run not found — this demo needs systemd (the pre-flight checks for it)."
  exit 1
fi

echo "Starting a process capped at MemoryMax=50M, asking it to allocate 200M..."
echo

# `|| true` so the script keeps going after the process is killed.
systemd-run --user --scope --quiet -p MemoryMax=50M -- \
  bash -c '
    echo "inside the cgroup. trying to allocate ~200 MB of memory..."
    junk=$(head -c 200000000 /dev/zero | tr "\0" "x")   # build a ~200MB string
    echo "allocated it all — the limit did NOT hold (unexpected!)"
  ' || status=$?

echo
if [ "${status:-0}" -eq 137 ]; then
  echo "exit 137 = killed by SIGKILL. The kernel's OOM killer enforced the 50M cap."
  echo "^ that is a cgroup doing its job. namespaces isolate; cgroups limit."
else
  echo "exit status: ${status:-0}  (137 would mean the OOM kill we expected)"
  echo "if it wasn't killed, your cgroup memory controller may not be delegated"
  echo "to the user — the pre-flight reports this."
fi
