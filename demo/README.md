# demo/ — the live build, one idea at a time

We build a container the same way you'd peel an onion: one layer per checkpoint.
Each folder adds **exactly one new idea** to the last one. Run them in order.

| Step | Folder | New idea | Needs root? |
| --- | --- | --- | --- |
| 1 | `cp1/` | A **UTS namespace** — your own hostname | yes (`sudo`) |
| 2 | `cp2/` | A **PID + mount namespace** — your own process list and `/proc` | yes (`sudo`) |
| 3 | `cp3/` | A **user namespace** — be "root" inside, a normal user outside (drops `sudo`) | no |
| 4 | `cp4/` | **`pivot_root`** — your own root filesystem (real Alpine) | no |
| 5 | `cp5/` | **cgroups** — a memory limit the kernel enforces | no |
| — | `../mini-docker.sh` | Everything above, tied into one ~100-line tool | no |

## How to run any step

```sh
bash demo/cp1/run.sh        # or cp2, cp3, ...
```

Each `run.sh` is short and commented — read it before you run it, that's the point.
When you're inside a container shell, type `exit` to come back out.

## Before you start

`cp4` and the final `mini-docker.sh` need an Alpine root filesystem. The pre-flight
script already put one at `~/paradox-workshop/rootfs`. If it's missing, run
`pre-flight.sh` from the repo root first.

## The mental model

A "container" isn't one feature — it's a handful of kernel **namespaces**
(isolated views of one global thing: hostnames, processes, mounts, users…) plus
**cgroups** (limits on what those processes can use). That's it. Docker adds images,
networking, and security hardening on top — but the core is what we build here.
