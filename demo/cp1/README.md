# CP1 — UTS namespace (your own hostname)

**New idea:** one namespace = one isolated view of one global thing. Here: the hostname.

```sh
bash run.sh
```

**Watch for:** you rename the host to `mini-container` *inside*, but when you `exit`
the host's real hostname is untouched. The change never escaped the namespace.

Needs `sudo` for now — CP3 fixes that.
