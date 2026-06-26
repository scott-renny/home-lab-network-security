# IR-001 — YAML Parse Error After sed Rule Injection

**Date:** 2026-06-21
**Severity:** Medium
**Status:** Resolved
**System:** homelabserver — Suricata 8.0.5

---

## Summary

A `sed` command used to inject a new rule file path into `/etc/suricata/suricata.yaml` corrupted the YAML indentation at line 3325, causing Suricata to fail configuration parsing on all subsequent reloads.

---

## Timeline

| Time | Event |
|---|---|
| 05:42:58 | Suricata running normally, 0 rules loaded |
| 05:43:xx | `sed` command executed to add `local.rules` to `rule-files` block |
| 05:44:02 | `kill -HUP` sent — Suricata received signal, stopped engine |
| 05:45:42 | Suricata restarted — YAML parse error at line 3325 |
| 05:45:42 | Warning: `/var/lib/suricata/rules/suricata.rules` not found |
| 05:45:42 | 1 signature loaded from `local.rules` despite warning |

---

## Detection

Running the Suricata config test revealed the error:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml -v
```

![IR-001 — YAML parse error output](../screenshots/13-ir001-yaml-parse-error.png)

```
Error: conf-yaml-loader: Failed to parse configuration file
at line 3325: did not find expected '-' indicator
```

---

## Root Cause

The `sed` command replaced the existing `suricata.rules` entry rather than appending after it. YAML list items require exact two-space indentation — the substitution produced inconsistent whitespace that broke the parser.

**Before (correct):**
```yaml
rule-files:
  - suricata.rules
```

**After sed (broken):**
```yaml
rule-files:
  - /etc/suricata/rules/local.rules
```

The `rule-files` block after manual fix:

![suricata.yaml rule-files block — correctly structured](../screenshots/12-suricata-yaml-rules-block.png)

---

## Impact

- Suricata unable to validate or reload configuration
- Custom IPS rules partially loaded — enforcement gap during incident window (~63 seconds)
- `suricatasc` and `systemctl reload` both failed

---

## Response

1. Opened `/etc/suricata/suricata.yaml` in `nano`, navigated to line 3325 with `Ctrl+_`
2. Manually corrected the `rule-files:` block to include both entries with proper indentation
3. Validated the fix before restarting:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml -v
```

4. Restarted and confirmed 2 rule files processed, 1 signature loaded.

---

## Remediation

Never use `sed` to modify YAML files. Use Python:

```bash
sudo python3 -c "
import yaml
with open('/etc/suricata/suricata.yaml', 'r') as f:
    config = yaml.safe_load(f)
if '/etc/suricata/rules/local.rules' not in config.get('rule-files', []):
    config['rule-files'].append('/etc/suricata/rules/local.rules')
with open('/etc/suricata/suricata.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
"
```

Always test config before any reload:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml
echo "Exit: $?"   # 0 = valid
```

---

## Lessons Learned

1. `suricata -T` validates config without stopping the running engine — always run it before restart
2. YAML is whitespace-sensitive — `sed` is not YAML-aware and will silently corrupt structure
3. Real incidents are portfolio assets — this failure demonstrates config management discipline

---

## Security+ Mapping

- **D4.4 Incident Response** — detection, containment, root cause, remediation
- **D3.1 Configuration Management** — YAML integrity, pre-change testing
