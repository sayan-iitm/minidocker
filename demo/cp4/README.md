# CP4 — pivot_root (your own root filesystem)

**New idea:** give the container its **own `/`** — a real Alpine Linux filesystem —
and make the host's files unreachable.

```sh
bash run.sh
# needs the Alpine rootfs from the pre-flight, at ~/paradox-workshop/rootfs
```

**Watch for:** inside, `cat /etc/os-release` says Alpine, and `ls /` shows Alpine's
directories — not the host's. You're in a different filesystem entirely.

**The three gotchas (all commented in `run.sh`):**

1. `mount --make-rprivate /` — `pivot_root` refuses while `/` is "shared" (systemd's default).
2. `mount --bind . .` — `pivot_root` requires the new root to be a mount point.
3. `hash -r` — bash cached old command paths; flush them or the next `mount` "vanishes".

This is `chroot` done properly: `chroot` only changes the view, `pivot_root` swaps the
root mount and then we `umount` the old one so there's no way back.
