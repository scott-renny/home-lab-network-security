# IR-002 — Wazuh Agent Queue Flooding

**Date:** 2026-06-19 to 2026-06-21
**Severity:** High
**Status:** Resolved
**System:** homelabserver — Wazuh Agent

---

## Summary

The Wazuh agent entered a crash loop due to event queue saturation. High-volume Suricata EVE JSON log ingestion exceeded the default queue size of 8192 events, causing the agent to drop events and repeatedly restart.

---

## Timeline

| Time | Event |
|---|---|
| Jun 19 08:00 | First "agent event queue is full" alert in Wazuh dashboard |
| Jun 19 08:01 | "Systemd: Service exited due to a failure" — agent crash #1 |
| Jun 19–21 | Repeating pattern every 5–15 minutes — 10+ crash cycles |
| Jun 21 | Root cause identified: EVE JSON log volume |
| Jun 21 | Queue size increased, `only-future-events` added — resolved |

---

## Detection

Wazuh dashboard showed a dense cluster of repeating lifecycle alerts:

![IR-002 — Wazuh agent queue flooding alerts](../screenshots/14-ir002-wazuh-queue-flood.png)

```
Agent event queue is full. Events may be lost.
Systemd: Service exited due to a failure.
Agent event queue finished. Flushed the agent configuration.
```

Rule IDs observed: 100, 535, 4759, 700, 516 — all agent lifecycle events.

---

## Root Cause

Two contributing factors:

**1. Suricata EVE JSON volume**

Suricata in NFQ/IPS mode logs every packet decision to `/var/log/suricata/eve.json`. With iptables NFQUEUE rules processing all inter-VLAN traffic, this file received thousands of entries per minute. The Wazuh agent was tailing it and flooding the internal event queue.

**2. Default queue size too small**

Default Wazuh agent queue: **8192 events**. With EVE JSON volume plus normal system logs, the queue saturated in under 60 seconds.

---

## Impact

- Wazuh agent crash-looped every 5–15 minutes
- Security events lost during crash/restart windows
- Dashboard flooded with lifecycle noise, masking real alerts

---

## Response

**Step 1 — Identify highest-volume log source:**

```bash
sudo grep -A2 "<localfile>" /var/ossec/etc/ossec.conf | grep "location"
sudo tail -f /var/ossec/logs/ossec.log | grep -v "^$"
```

EVE JSON confirmed as primary source.

**Step 2 — Add `only-future-events` to EVE JSON localfile:**

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/suricata/eve.json</location>
  <only-future-events>yes</only-future-events>
</localfile>
```

**Step 3 — Increase agent queue size:**

```bash
sudo nano /var/ossec/etc/internal_options.conf
# Add: agent.queue_size=16384
```

**Step 4 — Restart and verify:**

```bash
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent
```

---

## Remediation

Rate-limit Suricata EVE output in `/etc/suricata/suricata.yaml` — keep only security-relevant event types:

```yaml
outputs:
  - eve-log:
      enabled: yes
      filename: eve.json
      types:
        - alert
        - drop
        # - flow    # disabled — too high volume
        # - http    # disabled — too high volume
        # - dns     # disabled — too high volume
```

This reduces EVE JSON volume by 80–90% while keeping all security-relevant events.

---

## Lessons Learned

1. IPS mode generates orders of magnitude more log volume than IDS mode — plan for this before enabling NFQUEUE
2. Default Wazuh queue is sized for general use, not high-throughput security monitoring — tune early
3. `only-future-events` must be set for high-volume sources — without it, every agent restart replays the entire log file
4. Alert fatigue is a security control failure — noise reduction is not cosmetic

---

## Security+ Mapping

- **D4.1 Security Monitoring** — SIEM tuning, alert fatigue, log management
- **D4.4 Incident Response** — detection, root cause, remediation
