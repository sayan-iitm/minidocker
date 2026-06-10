# CP5 — cgroups (a limit the kernel enforces)

**New idea:** namespaces control what a process can **see**; cgroups control what it
can **use**. Simplest demo: cap memory at 50 MB, try to grab 200 MB, watch the kernel
kill it.

```sh
bash run.sh
```

**Watch for:** the process exits with **137** — killed by `SIGKILL` from the kernel's
OOM killer. That's the 50 MB limit being enforced.

We let `systemd-run` create the cgroup for us. The by-hand version writes to
`/sys/fs/cgroup/...` directly — same idea, more typing — and lives in `docs/cgroups.md`.

This is the last building block. Next: `../mini-docker.sh` puts namespaces + pivot_root
+ a cgroup limit together into one small tool.
