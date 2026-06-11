# CP2 — PID + mount namespace (your own process list)

**New idea:** isolate the process table too. Your shell becomes **PID 1** and `ps`
shows only the handful of processes you started — not the host's hundreds.

```sh
bash run.sh
```

**Why three new flags for "one idea"?**

- `--pid` gives the private process-ID namespace.
- `--fork` is needed because a PID namespace only takes effect for _child_ processes.
- `--mount` + `--mount-proc` give a fresh `/proc` so `ps` reflects the new view
  (without it, `ps` would still read the host's `/proc`).

Still needs `sudo`. CP3 drops it.
