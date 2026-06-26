#!/usr/bin/env bash
# =============================================================================
# vlan-setup.sh
# Creates 802.1q VLAN subinterfaces on a wireless NIC (Linux kernel 8021q)
#
# Usage: sudo bash vlan-setup.sh
# Tested on: Ubuntu 22.04 LTS, wlp2s0 wireless interface
#
# IMPORTANT: Edit PARENT_IFACE below to match your wireless interface name.
#            Run `ip link show` to find it — look for the wlp* or wlan* entry.
# =============================================================================
 
set -euo pipefail
 
# ── Configuration ─────────────────────────────────────────────────────────────
PARENT_IFACE="wlp2s0"          # Your wireless NIC — change this if needed
 
# VLAN definitions: "ID:NAME:IP_PREFIX"
VLANS=(
  "10:vlan10_secure_lab:10.10.10.1/24"
  "15:vlan15_vip_vault:10.10.15.1/24"
  "20:vlan20_smart_sandbox:10.10.20.1/24"
)
# ──────────────────────────────────────────────────────────────────────────────
 
# Colour output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
 
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
 
# Must run as root
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash $0"
 
# ── Step 1: Load 8021q kernel module ──────────────────────────────────────────
log "Loading 802.1q kernel module..."
modprobe 8021q || err "Failed to load 8021q module"
lsmod | grep -q 8021q && log "8021q module loaded ✓" || err "8021q not loaded"
 
# ── Step 2: Verify parent interface exists ────────────────────────────────────
ip link show "$PARENT_IFACE" > /dev/null 2>&1 \
  || err "Interface $PARENT_IFACE not found. Edit PARENT_IFACE in this script."
 
log "Parent interface: $PARENT_IFACE ✓"
 
# ── Step 3: Create VLAN subinterfaces ─────────────────────────────────────────
for entry in "${VLANS[@]}"; do
  IFS=':' read -r vlan_id vlan_name ip_prefix <<< "$entry"
  iface="${PARENT_IFACE}.${vlan_id}"
 
  if ip link show "$iface" > /dev/null 2>&1; then
    warn "Interface $iface already exists — skipping creation"
  else
    log "Creating $iface (VLAN ID $vlan_id)..."
    ip link add link "$PARENT_IFACE" name "$iface" type vlan id "$vlan_id"
  fi
 
  log "Bringing $iface up..."
  ip link set dev "$iface" up
 
  # Assign IP if not already assigned
  if ip addr show "$iface" | grep -q "$ip_prefix"; then
    warn "IP $ip_prefix already assigned to $iface — skipping"
  else
    log "Assigning $ip_prefix to $iface..."
    ip addr add "$ip_prefix" dev "$iface"
  fi
 
  log "$iface ready: $ip_prefix ✓"
done
 
# ── Step 4: Enable IP forwarding ──────────────────────────────────────────────
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf \
  || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
log "IP forwarding enabled ✓"
 
# ── Step 5: Load NAT module ───────────────────────────────────────────────────
log "Loading ipt_MASQUERADE module..."
modprobe ipt_MASQUERADE
log "ipt_MASQUERADE loaded ✓"
 
# ── Step 6: Verify ────────────────────────────────────────────────────────────
echo ""
log "=== Verification ==="
ip link show | grep -E "wlp2s0\.|${PARENT_IFACE}\."
echo ""
ip addr show | grep -E "inet.*wlp2s0\."
echo ""
log "Setup complete. VLANs are active until next reboot."
warn "To make VLANs persistent across reboots, run: sudo bash persist-vlans.sh"
