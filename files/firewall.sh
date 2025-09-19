#!/usr/bin/env bash
# Proxmox VE Firewall Rule Setup
# Adds required and optional firewall rules
# Compatible with Proxmox VE 8/9

set -euo pipefail

# Function to add a firewall rule safely
add_rule() {
    local rule="$1"
    if ! pve-firewall status &>/dev/null; then
        echo "Proxmox firewall is not enabled. Enabling..."
        pve-firewall enable
    fi
    echo "Adding firewall rule: $rule"
    pve-firewall allow "$rule"
}

# Ensure the firewall is enabled
if ! pve-firewall status &>/dev/null; then
    echo "Enabling Proxmox firewall..."
    pve-firewall enable
fi

echo "Configuring required firewall rules..."
# Required: allow web GUI
add_rule "8006/tcp"

# Optional: enable ICMP ping
read -rp "Enable ICMP Ping? (y/n) " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    add_rule "icmp"
else
    echo "Ping not enabled"
fi

# Optional: enable SSH
read -rp "Enable SSH (port 22)? (y/n) " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    add_rule "22/tcp"
else
    echo "SSH not enabled"
fi

echo "Firewall rules configured successfully."
echo "You may verify rules with: pve-firewall status"
