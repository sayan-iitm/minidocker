#!/usr/bin/env bash
# CP3 — the user namespace: drop sudo, become "root" inside
#
# THE IDEA: a user namespace lets an ordinary user be uid 0 (root) INSIDE the
# namespace, while still being their normal unprivileged self outside. This is
# the trick that makes "rootless" containers (Podman, rootless Docker) possible.
#
# New flags vs CP2:
#   --user            a private user namespace
#   --map-root-user   map your real uid to root (0) inside the namespace
#
# Notice: NO sudo on the line below. We get "root" for free, safely.

set -e

echo "outside, you are just:    $(id -un) (uid $(id -u))"
echo

unshare --user --map-root-user \
        --uts --pid --mount --fork --mount-proc \
  bash -c '
    echo "inside, id says:          $(id)"
    echo "^ uid=0(root) — but only in here. we never used sudo."
    echo
    hostname mini-container
    ps aux
    echo
    echo "own hostname, own process list, root powers. type exit to leave."
    exec bash
  '

echo
echo "back outside — still just $(id -un), no extra powers gained on the host."
