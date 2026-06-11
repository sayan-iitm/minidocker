# Appendix: cgroups by hand

> **You do not need this for the workshop.** CP5 and `mini-docker.sh` use
> `systemd-run`, which creates the cgroup and applies the limit for you. This page
> is for the curious — it shows what `systemd-run` does under the hood, by writing
> to `/sys/fs/cgroup` directly.

## The idea

A **cgroup** ("control group") is a directory in a special filesystem mounted at
`/sys/fs/cgroup`. You put a process into a cgroup, write a limit into a file in that
directory, and the kernel enforces it. That's the whole mechanism — files and
directories.

Modern distros use **cgroups v2** (a single unified tree). Everything below assumes v2.
Check with:

```sh
stat -fc %T /sys/fs/cgroup          # "cgroup2fs" means v2 — what you want
```

## Why the workshop doesn't do this live

Three things make the by-hand path fragile live, which is why we let
`systemd-run` handle it:

1. **Delegation.** As a non-root user you can only create cgroups inside the subtree
   systemd _delegated_ to your login session, and only use controllers it handed you.
2. **The "no internal processes" rule.** A cgroup can't both contain processes _and_
   hand controllers to its children. You have to nest carefully.
3. **It's v2-only and the file names differ from the old v1** (`memory.max`, not
   `memory.limit_in_bytes`), so half-remembered v1 recipes fail confusingly.

`systemd-run` knows all of this. Still — here's the manual version.

## The manual recipe (rootless, cgroups v2)

```sh
# 1. The subtree systemd delegated to your user session. This is where an
#    unprivileged user is allowed to create cgroups.
U=$(id -u)
BASE="/sys/fs/cgroup/user.slice/user-$U.slice/user@$U.service"

# 2. See which controllers you were given. You can only use these.
cat "$BASE/cgroup.controllers"          # e.g. "memory pids cpu"

# 3. Hand the memory + pids controllers down to child cgroups.
#    (If this errors with EBUSY, see the "no internal processes" note below.)
echo "+memory +pids" > "$BASE/cgroup.subtree_control"

# 4. Create a cgroup for our container.
mkdir -p "$BASE/minidocker"

# 5. Write the limits — just numbers into files.
echo 100M > "$BASE/minidocker/memory.max"   # hard memory cap
echo 64   > "$BASE/minidocker/pids.max"      # max number of processes

# 6. Move a shell into the cgroup. Every child it spawns inherits the limits.
echo $$ > "$BASE/minidocker/cgroup.procs"

# ...now anything you run here is capped. Try the memory test from CP5:
junk=$(head -c 200000000 /dev/zero | tr '\0' 'x')   # gets OOM-killed at 100M
```

### Cleanup

A cgroup directory can only be removed once it holds no processes. Move your shell back
out, then `rmdir`:

```sh
echo $$ > "$BASE/cgroup.procs"          # move ourselves back to the parent
rmdir "$BASE/minidocker"                # remove the now-empty cgroup
```

## The "no internal processes" rule (step 3 gotcha)

cgroups v2 forbids a cgroup from _both_ having processes sitting directly in it _and_
enabling controllers for its children. Your login shell usually lives directly in
`user@$U.service`, so `echo "+memory" > .../cgroup.subtree_control` can fail with
`EBUSY`.

The fix is to nest: make a leaf cgroup for your shell and the container as _siblings_,
so the parent has no direct processes:

```sh
mkdir -p "$BASE/shell" "$BASE/minidocker"
echo $$ > "$BASE/shell/cgroup.procs"        # get our shell out of the parent
echo "+memory +pids" > "$BASE/cgroup.subtree_control"   # now this succeeds
echo 100M > "$BASE/minidocker/memory.max"
# ...then launch the container into $BASE/minidocker as before.
```

This nesting is exactly the kind of bookkeeping `systemd-run` does for you — which is
why the workshop uses it and keeps this page as an appendix.

## See also

- `demo/cp5/run.sh` — the `systemd-run` version (what you actually run in the workshop).
- `man 7 cgroups` — the kernel's own reference.
- `/sys/fs/cgroup/.../cgroup.events`, `memory.current`, `memory.peak` — files worth
  `cat`-ing to watch a cgroup live.
