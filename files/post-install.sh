#!/bin/bash

# Proxmox VE Post-Install Helper Script

set -e

echo -e "\033[1;32mStarting Proxmox VE Post-Install Helper Script...\033[0m"

# Detect Proxmox VE version
PVE_VERSION=$(pveversion | awk -F'/' '{print $2}' | cut -d'-' -f1)

# === Functions ===

setup_repos_8() {
    echo -e "\n\033[1;32mConfiguring repositories for Proxmox VE 8 (Bookworm)...\033[0m"

    # Debian repos
    cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF

    # Disable enterprise repo
    if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
        sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list
    fi

    # Add no-subscription repo
    cat > /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

    # Add disabled pvetest repo
    cat > /etc/apt/sources.list.d/pvetest.list <<EOF
# deb http://download.proxmox.com/debian/pve bookworm pvetest
EOF
}

setup_repos_9() {
    echo -e "\n\033[1;32mConfiguring repositories for Proxmox VE 9 (Trixie)...\033[0m"

    SOURCES_DIR="/etc/apt/sources.list.d"

    # Disable enterprise repo if exists
    if [ -f "$SOURCES_DIR/pve-enterprise.sources" ]; then
        sed -i 's/^Enabled: yes/Enabled: no/' "$SOURCES_DIR/pve-enterprise.sources"
    fi

    # Add no-subscription repo
    cat > "$SOURCES_DIR/pve-no-subscription.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-release-9.x.gpg
Enabled: yes
EOF

    # Add disabled pvetest repo
    cat > "$SOURCES_DIR/pvetest.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pvetest
Signed-By: /usr/share/keyrings/proxmox-release-9.x.gpg
Enabled: no
EOF
}

# Subscription nag fix
disable_subscription_nag() {
    echo -e "\n\033[1;32mDisabling subscription nag...\033[0m"

    JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [ -f "$JS_FILE" ]; then
        sed -i.bak "s/data.status !== 'Active'/false/" "$JS_FILE"
    fi

    # Re-apply on package updates
    HOOK_DIR="/etc/apt/apt.conf.d"
    HOOK_FILE="$HOOK_DIR/99-pve-nag-fix"
    mkdir -p "$HOOK_DIR"
    cat > "$HOOK_FILE" <<'EOF'
DPkg::Post-Invoke { "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then sed -i \"s/data.status !== 'Active'/false/\" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi"; };
EOF
}

# HA service handling
handle_ha_services() {
    echo -e "\n\033[1;32mHandling HA services...\033[0m"

    if systemctl is-enabled --quiet pve-ha-lrm && systemctl is-enabled --quiet pve-ha-crm; then
        if whiptail --yesno "HA services are active. Do you want to disable them to save resources?" 8 60; then
            systemctl disable --now pve-ha-lrm pve-ha-crm
            if whiptail --yesno "Do you also want to disable Corosync (cluster service)?" 8 60; then
                systemctl disable --now corosync
            fi
        fi
    else
        if whiptail --yesno "HA services are not active. Do you want to enable them?" 8 60; then
            systemctl enable --now pve-ha-lrm pve-ha-crm
        fi
    fi
}

# Firewall setup
setup_firewall() {
    echo -e "\n\033[1;32mConfiguring Proxmox Firewall rules...\033[0m"

    FIREWALL_CONF="/etc/pve/firewall/cluster.fw"

    if [ ! -f "$FIREWALL_CONF" ]; then
        echo "[OPTIONS]" > "$FIREWALL_CONF"
        echo "enable: 1" >> "$FIREWALL_CONF"
        echo "" >> "$FIREWALL_CONF"
        echo "[RULES]" >> "$FIREWALL_CONF"
        echo "Created new datacenter firewall config."
    fi

    # Always required: WebUI
    if ! grep -q "IN ACCEPT -p tcp -dport 8006" "$FIREWALL_CONF"; then
        echo "IN ACCEPT -p tcp -dport 8006" >> "$FIREWALL_CONF"
        echo "Added rule: Allow WebUI (8006/tcp)"
    fi

    # Ask about SSH
    if whiptail --yesno "Allow SSH (22/tcp) through firewall?" 8 60; then
        if ! grep -q "IN ACCEPT -p tcp -dport 22" "$FIREWALL_CONF"; then
            echo "IN ACCEPT -p tcp -dport 22" >> "$FIREWALL_CONF"
            echo "Added rule: Allow SSH (22/tcp)"
        fi
    else
        echo "Skipped SSH firewall rule."
    fi

    # Ask about ICMP (ping)
    if whiptail --yesno "Allow ICMP (ping) through firewall?" 8 60; then
        if ! grep -q "IN ACCEPT -p icmp" "$FIREWALL_CONF"; then
            echo "IN ACCEPT -p icmp" >> "$FIREWALL_CONF"
            echo "Added rule: Allow ICMP (ping)"
        fi
    else
        echo "Skipped ICMP firewall rule."
    fi

    echo -e "\033[1;32mFirewall configuration complete.\033[0m"
}

# === Main ===

if [[ "$PVE_VERSION" =~ ^8 ]]; then
    setup_repos_8
elif [[ "$PVE_VERSION" =~ ^9 ]]; then
    setup_repos_9
else
    echo "Unsupported Proxmox version: $PVE_VERSION"
    exit 1
fi

disable_subscription_nag
handle_ha_services
setup_firewall   # <--- firewall prompts run here

echo -e "\n\033[1;32mUpdating system...\033[0m"
apt update && apt -y dist-upgrade

echo -e "\n\033[1;32mAll done! Run this on every node, then reboot. Clear browser cache before logging back in.\033[0m"
