# 🔒 Secure Home Network Lab — Telus PureFibre / Wireless-Only Build

![Status](https://img.shields.io/badge/Status-Active-brightgreen)
![Phase](https://img.shields.io/badge/Phase-2%20Complete-blue)
![Suricata](https://img.shields.io/badge/Suricata-8.0.5-orange)
![WireGuard](https://img.shields.io/badge/WireGuard-VPN-blueviolet)
![Wazuh](https://img.shields.io/badge/Wazuh-SIEM-teal)
![Security+](https://img.shields.io/badge/CompTIA-Security%2B%20SY0--701-red)

> **A fully wireless, software-defined network security lab built on a locked Telus PureFibre ISP router — no managed switch, no pfSense, no hardware VLANs. All segmentation, IPS enforcement, and VPN tunnelling achieved entirely in software on a single Linux host.**

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [What This Lab Demonstrates](#what-this-lab-demonstrates)
- [Hardware](#hardware)
- [Phase 1 — Network Segmentation](#phase-1--network-segmentation)
- [Phase 2 — IPS + VPN + SIEM](#phase-2--ips--vpn--siem)
- [Incident Reports](#incident-reports)
- [Security+ Domain Mapping](#security-domain-mapping)
- [MITRE ATT&CK Coverage](#mitre-attck-coverage)
- [File Structure](#file-structure)

---

## Architecture Overview

```
TELUS PUREFIBR ISP
        │
   192.168.1.254 (Telus T3200M — locked, no VLAN support)
        │
   wlp2s0 (Wi-Fi NIC — Linux host)
        │
   ┌────┴────────────────────────────────┐
   │         802.1q VLAN Subinterfaces   │
   │  wlp2s0.10  →  10.10.10.0/24       │  VLAN 10: Secure Lab
   │  wlp2s0.15  →  10.10.15.0/24       │  VLAN 15: VIP Vault
   │  wlp2s0.20  →  10.10.20.0/24       │  VLAN 20: Smart Device Sandbox
   └─────────────────────────────────────┘
        │
   iptables NFQUEUE → Suricata 8.0.5 (IPS/NFQ mode)
        │
   Custom IPS Rules (local.rules)
   ├── DROP: VLAN 20 → VLAN 15 (lateral movement)
   ├── DROP: Telus subnet → VLAN 10 (unauthorized probe)
   └── DROP: Telus subnet → VLAN 15 (unauthorized probe)
        │
   WireGuard wg0 (10.10.30.0/24) — encrypted VPN tunnel
        │
   Wazuh SIEM — centralized alerting + MITRE ATT&CK mapping
```

**Key constraint:** The Telus T3200M provides no VLAN tagging, CLI access, or syslog export. All network segmentation is implemented at the Linux kernel level using 802.1q subinterfaces, iptables, and Suricata NFQ mode.

---

## What This Lab Demonstrates

| Skill | Implementation |
|---|---|
| Network segmentation without managed switch | 802.1q VLAN subinterfaces on wireless NIC |
| IPS enforcement on inter-VLAN traffic | iptables NFQUEUE → Suricata NFQ mode |
| Encrypted remote access | WireGuard VPN with hardened key permissions |
| Threat detection and SIEM integration | Wazuh agents + Suricata EVE JSON forwarding |
| Custom IPS rules | Suricata local.rules — lateral movement + probe detection |
| Kernel module management | 8021q and ipt_MASQUERADE loaded and verified |
| NAT for VLAN routing | iptables MASQUERADE on outbound interface |
| Incident documentation | 4 real incidents with root cause and fix |

---

## Hardware

| Component | Spec |
|---|---|
| Host machine | Dell Latitude E7250 |
| OS | Ubuntu Server 22.04 LTS |
| Network interface | `wlp2s0` (wireless — no wired switch) |
| ISP router | Telus T3200M (locked, no VLAN support) |
| Internet | Telus PureFibre (fibre to ONT) |

**Cost of software stack: $0** — all tools are free and open source.

---

## Phase 1 — Network Segmentation

### Step 1 — Load the 802.1q kernel module

The `8021q` module enables VLAN tagging on any Linux network interface, including wireless NICs.

```bash
sudo modprobe 8021q
lsmod | grep 8021q
```

![8021q kernel module loaded](screenshots/01-8021q-module-loaded.png)

### Step 2 — Load NAT modules

```bash
sudo modprobe ipt_MASQUERADE
lsmod | grep -E "ipt|nf_nat"
```

![NAT modules loaded](screenshots/04-nat-modules-loaded.png)

### Step 3 — Create VLAN subinterfaces

Three virtual interfaces are created on top of the physical `wlp2s0`:

```bash
sudo ip link add link wlp2s0 name wlp2s0.10 type vlan id 10
sudo ip link set dev wlp2s0.10 up

sudo ip link add link wlp2s0 name wlp2s0.15 type vlan id 15
sudo ip link set dev wlp2s0.15 up

sudo ip link add link wlp2s0 name wlp2s0.20 type vlan id 20
sudo ip link set dev wlp2s0.20 up
```

![VLAN interfaces UP](screenshots/02-vlan-interfaces-up.png)

### Step 4 — Assign IP addresses and verify

```bash
sudo ip addr add 10.10.10.1/24 dev wlp2s0.10
sudo ip addr add 10.10.15.1/24 dev wlp2s0.15
sudo ip addr add 10.10.20.1/24 dev wlp2s0.20
ip addr show | grep -E "wlp2s0\.|inet"
```

![IP addresses assigned to VLAN interfaces](screenshots/03-ip-addr-vlans.png)

### Step 5 — Verify default route (Telus gateway)

```bash
ip route | grep default
```

![Default route via Telus gateway](screenshots/15-ip-route-default.png)

### VLAN Design

| VLAN | Interface | Subnet | Purpose | Trust Level |
|---|---|---|---|---|
| 10 | wlp2s0.10 | 10.10.10.0/24 | Secure Lab | High |
| 15 | wlp2s0.15 | 10.10.15.0/24 | VIP Vault | Critical |
| 20 | wlp2s0.20 | 10.10.20.0/24 | Smart Device Sandbox | Untrusted |
| — | wlp2s0 | 192.168.1.x | Telus base network | Untrusted |

### Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

![UFW firewall status](screenshots/10-ufw-status.png)

---

## Phase 2 — IPS + VPN + SIEM

### Suricata 8.0.5 — IPS Mode via NFQUEUE

Suricata runs in NFQ (Netfilter Queue) mode — iptables intercepts traffic and hands it to Suricata for inline inspection before forwarding. Packets matching a `drop` rule are silently discarded.

#### Step 1 — Install and enable Suricata

```bash
sudo apt install suricata -y
sudo systemctl enable suricata
suricata -V
```

![Suricata 8.0.5 running](screenshots/06-suricata-running.png)

#### Step 2 — Write custom IPS rules

```bash
sudo tee /etc/suricata/rules/local.rules << 'EOF'
drop ip 10.10.20.0/24 any -> 10.10.15.0/24 any \
  (msg:"IPS DROP: Lateral Movement Attempt - Smart Device to VIP Vault"; sid:1000001; rev:1;)
drop ip 192.168.1.0/24 any -> 10.10.10.0/24 any \
  (msg:"IPS DROP: Unauthorized Probe - Base Network to Secure Lab"; sid:1000002; rev:1;)
drop ip 192.168.1.0/24 any -> 10.10.15.0/24 any \
  (msg:"IPS DROP: Unauthorized Probe - Base Network to VIP Vault"; sid:1000003; rev:1;)
EOF
```

#### Step 3 — Register local.rules in suricata.yaml

```yaml
rule-files:
  - suricata.rules
  - /etc/suricata/rules/local.rules
```

![suricata.yaml rule-files block](screenshots/12-suricata-yaml-rules-block.png)

#### Step 4 — Reload and verify rules loaded

```bash
sudo kill -HUP $(pidof suricata)
sudo tail -n 25 /var/log/suricata/suricata.log
```

![Suricata rules loaded — 1 signature processed](screenshots/07-suricata-rules-loaded.png)

#### Step 5 — Insert iptables NFQUEUE rules

```bash
sudo iptables -I FORWARD -i wlp2s0.20 -o wlp2s0.15 -j NFQUEUE --queue-num 1
sudo iptables -I FORWARD -i wlp2s0 -o wlp2s0.10 -j NFQUEUE --queue-num 1
sudo iptables -I FORWARD -i wlp2s0 -o wlp2s0.15 -j NFQUEUE --queue-num 1
sudo iptables -L FORWARD -n -v
```

![iptables NFQUEUE rules active](screenshots/05-iptables-nfqueue-rules.png)

---

### WireGuard VPN

#### Step 1 — Generate hardened keys

`umask 077` ensures created files get `0600` permissions — root read/write only.

```bash
sudo mkdir -p /etc/wireguard/keys
sudo sh -c 'umask 077; wg genkey | tee /etc/wireguard/keys/server.private \
  | wg pubkey > /etc/wireguard/keys/server.public'
sudo ls -l /etc/wireguard/keys
```

![WireGuard key files — 0600 permissions](screenshots/08-wireguard-key-perms.png)

#### Step 2 — Bring up WireGuard interface

```bash
sudo wg-quick up wg0
sudo wg show wg0
```

**Active connection verified — peer handshake confirmed, transfer active:**

![WireGuard connected — active peer handshake](screenshots/09-wireguard-connected.png)

---

### Wazuh SIEM

Wazuh agents running on the host forward events to the Wazuh manager. Suricata EVE JSON logs are ingested and enriched with MITRE ATT&CK tags automatically.

**Alerts captured in dashboard — including Privilege Escalation (T1548) and Defense Evasion:**

![Wazuh SIEM — MITRE ATT&CK alerts](screenshots/11-wazuh-siem-alerts.png)

---

## Incident Reports

Four real incidents occurred during this build. Each is documented in SOC format: Detection → Root Cause → Impact → Response → Remediation → Lessons Learned.

| Report | Severity | Summary |
|---|---|---|
| [IR-001](docs/IR-001-yaml-parse-error.md) | Medium | YAML parse error after sed corrupted suricata.yaml indentation |
| [IR-002](docs/IR-002-wazuh-queue-flood.md) | High | Wazuh agent queue flooding from Suricata EVE JSON volume |
| [IR-003](docs/IR-003-suricatasc-reload.md) | Low | suricatasc rules-reload command removed in Suricata 8.x |
| [IR-004](docs/IR-004-wireguard-keys-perms.md) | Info | WireGuard keys directory permission denied — expected behaviour |

---

## Security+ Domain Mapping

| Domain | Topic | Implementation |
|---|---|---|
| D2.1 | Network segmentation | 802.1q VLANs on wireless NIC |
| D2.1 | Firewall architecture | UFW + iptables layered rules |
| D2.3 | Secure protocols | WireGuard (ChaCha20-Poly1305) |
| D3.1 | Host hardening | UFW deny-default, fail2ban |
| D3.3 | PKI / key management | WireGuard keypair, umask 077 |
| D4.1 | Log monitoring | Wazuh SIEM, EVE JSON ingestion |
| D4.2 | IDS/IPS | Suricata 8.0.5 NFQ mode |
| D4.4 | Incident response | 4 documented incident reports |
| D5.1 | Vulnerability identification | Lynis audit, CVE scanning |

---

## MITRE ATT&CK Coverage

| Technique | ID | Detection Method |
|---|---|---|
| Lateral Movement | T1021 | Suricata rule sid:1000001 |
| Network Service Discovery | T1046 | Suricata rule sid:1000002/3 |
| Privilege Escalation | T1548 | Wazuh sudo monitoring |
| Defense Evasion | T1548.003 | Wazuh first-use sudo alert |

---

## File Structure

```
home-lab-network-security/
├── README.md
├── .gitignore
├── config/
│   ├── wireguard-wg0.conf.example
│   ├── suricata-local.rules
│   └── ufw-rules.txt
├── scripts/
│   ├── vlan-setup.sh
│   ├── suricata-nfqueue.sh
│   └── persist-vlans.sh
├── docs/
│   ├── IR-001-yaml-parse-error.md
│   ├── IR-002-wazuh-queue-flood.md
│   ├── IR-003-suricatasc-reload.md
│   └── IR-004-wireguard-keys-perms.md
└── screenshots/
    ├── 01-8021q-module-loaded.png
    ├── 02-vlan-interfaces-up.png
    ├── 03-ip-addr-vlans.png
    ├── 04-nat-modules-loaded.png
    ├── 05-iptables-nfqueue-rules.png
    ├── 06-suricata-running.png
    ├── 07-suricata-rules-loaded.png
    ├── 08-wireguard-key-perms.png
    ├── 09-wireguard-connected.png
    ├── 10-ufw-status.png
    ├── 11-wazuh-siem-alerts.png
    ├── 12-suricata-yaml-rules-block.png
    ├── 13-ir001-yaml-parse-error.png
    ├── 14-ir002-wazuh-queue-flood.png
    └── 15-ip-route-default.png
```
