#!/usr/bin/env bash
# Proxmox VE Firewall Rule Setup
# Adds required and optional firewall rules

set -euo pipefail

# Function to add a firewall rule safely
add_rule() {
    local rule_type="$1"
    local port_or_icmp="$2"
    echo "Adding firewall rule: $rule_type $port_or_icmp"
    pve-firewall local allow "$port_or_icmp"
}

# Ensure the firewall is enabled
if ! pve-firewall status &>/dev/null; then
    echo "Enabling Proxmox firewall..."
    pve-firewall enable
fi

# Required: allow port 8006
add_rule "tcp" "8006"

# Optional: enable ping
read -rp "Enable ICMP Ping? (y/n) " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    add_rule "icmp" ""
else
    echo "Ping not enabled"
fi

# Optional: enable SSH
read -rp "Enable SSH (port 22)? (y/n) " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    add_rule "tcp" "22"
else
    echo "SSH not enabled"
fi

echo "Firewall rules configured successfully."
