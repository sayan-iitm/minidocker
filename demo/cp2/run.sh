#!/usr/bin/env bash
# CP2 — two more namespaces: PID (process IDs) and mount (the filesystem tree)
#
# THE IDEA: inside a PID namespace, your shell becomes PID 1 and can only see
# its own processes. But `ps` reads /proc — so we also need a fresh /proc, which
# means a private mount namespace to mount it in.
#
# New flags vs CP1:
#   --pid          a private process-ID namespace
#   --mount        a private mount namespace (so we can remount /proc safely)
#   --fork         the new PID namespace only applies to CHILDREN, so fork one
#   --mount-proc   mount a fresh /proc that reflects the new PID namespace
#
# Still needs sudo. (Next checkpoint drops it.)

set -e

echo "on the host you can see hundreds of processes:"
ps aux | wc -l
echo

sudo unshare --uts --pid --mount --fork --mount-proc bash -c '
  hostname mini-container
  echo "inside, ps shows ONLY our own processes:"
  ps aux
  echo
  echo "notice our shell is PID 1. type exit to leave."
  exec bash
'

echo
echo "back on the host — all those processes are still there, untouched."
