#!/usr/bin/env bash
# CP1 — your first namespace: UTS (the hostname namespace)
#
# THE IDEA: a "namespace" is an isolated copy of one global thing. The UTS
# namespace isolates the hostname. Change it inside, and the host outside
# never notices.
#
# We need sudo here — for now. (CP3 shows how to drop it.)

set -e

echo "host's hostname, before:  $(hostname)"
echo

# unshare --uts = "give this command a fresh, private UTS namespace"
sudo unshare --uts bash -c '
  hostname mini-container          # rename the host... but only in here
  echo "inside the namespace:     $(hostname)"
  echo
  echo "you are now in a shell with its own hostname. type exit to leave."
  exec bash
'

echo
echo "back on the host. hostname is still:  $(hostname)"
echo "^ the rename never leaked out. that is a namespace."
