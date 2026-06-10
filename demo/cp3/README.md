# CP3 — user namespace (drop sudo, be root inside)

**New idea:** a user namespace maps your ordinary user to **root (uid 0) inside**,
while you stay a normal unprivileged user **outside**. No more `sudo`.

```sh
bash run.sh
```

**Watch for:** the command has no `sudo`, yet `id` inside reports `uid=0(root)`.
Outside, you're still your normal self with no new powers. This is the foundation
of "rootless" containers.

> If this errors on Ubuntu 24.04+, it's the AppArmor user-namespace restriction —
> the pre-flight prints the one-line fix.
