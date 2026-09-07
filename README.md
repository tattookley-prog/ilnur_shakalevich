# ilnur_shakalevich

## PVE nested lab kernel-panic fault-injection scripts

Two standalone Bash scripts for authorized, destructive fault-injection
testing of a **disposable nested Proxmox VE lab host** (and its guests):

- [`pve-crash-with-reboot.sh`](pve-crash-with-reboot.sh) — kernel panic with
  an automatic reboot attempt.
- [`pve-crash-no-reboot.sh`](pve-crash-no-reboot.sh) — kernel panic without
  the automatic reboot timer.

See [`README-ru.md`](README-ru.md) (in Russian, as requested) for full
documentation, scope, safety checks and usage. Safe tests live in
[`tests/test_pve_crash_scripts.sh`](tests/test_pve_crash_scripts.sh).
