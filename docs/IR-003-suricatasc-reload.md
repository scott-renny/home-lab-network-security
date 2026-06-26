# IR-003 — suricatasc Unknown Command on Rules Reload

**Date:** 2026-06-21
**Severity:** Low
**Status:** Resolved
**System:** homelabserver — Suricata 8.0.5

---

## Summary

Attempt to reload Suricata rules using `suricatasc -c rules-reload` failed with `UnknownCommand("rules-reload")`. The command was removed in Suricata 8.x. Rules were successfully reloaded using `kill -HUP`.

---

## Detection

```bash
$ sudo suricatasc -c rules-reload
Error: UnknownCommand("rules-reload")
```

---

## Root Cause

The `rules-reload` command was removed in Suricata 8.x. Community guides written for Suricata 6.x commonly reference it.

| Method | Version | Notes |
|---|---|---|
| `suricatasc -c rules-reload` | ≤ 6.x | Removed in 8.x |
| `suricatasc -c ruleset-reload-nonblocking` | 7.x+ | Non-blocking |
| `kill -HUP $(pidof suricata)` | All | Reliable, POSIX-standard |
| `systemctl reload suricata` | All (systemd) | Sends HUP via systemd |

---

## Impact

- ~2-minute window where rules were written to disk but not active in the running engine
- No live traffic on the affected VLAN segments at time of failure — no security impact

---

## Response

```bash
sudo kill -HUP $(pidof suricata)
sudo tail -n 25 /var/log/suricata/suricata.log
```

Rules confirmed loaded — engine restarted cleanly:

```
Notice: suricata: Signal Received. Stopping engine.
Info: detect: 2 rule files processed. 1 rules successfully loaded
Info: detect: 1 signatures processed
Notice: threads: Threads created -> RX: 1 W: 4 TX: 1. Engine started.
```

---

## Remediation

Correct reload command for Suricata 8.x:

```bash
# Non-blocking reload (engine keeps running)
sudo suricatasc -c ruleset-reload-nonblocking

# Always works across all versions
sudo kill -HUP $(pidof suricata)

# Verify rules loaded
sudo tail -f /var/log/suricata/suricata.log | grep -i "rule\|detect\|signature"
```

---

## Lessons Learned

1. Security tool CLIs change significantly between major versions — verify against `man suricatasc`, not community tutorials
2. `kill -HUP` works on any Unix daemon that supports graceful reload — use it when in doubt
3. Read the logs — the restart log immediately confirmed the HUP method worked

---

## Security+ Mapping

- **D4.2 IDS/IPS** — operational management of IPS systems
- **D4.4 Incident Response** — rapid diagnosis, workaround, permanent fix
