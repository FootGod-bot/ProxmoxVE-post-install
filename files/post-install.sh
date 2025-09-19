#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteckster | MickLesk (CanbiZ)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

header_info() {
  clear
  cat <<"EOF"
    ____ _    ________   ____             __     ____           __        ____
   / __ \ |  / / ____/  / __ \____  _____/ /_   /  _/___  _____/ /_____ _/ / /
  / /_/ / | / / __/    / /_/ / __ \/ ___/ __/   / // __ \/ ___/ __/ __ `/ / /
 / ____/| |/ / /___   / ____/ /_/ (__  ) /_   _/ // / / (__  ) /_/ /_/ / / /
/_/     |___/_____/  /_/    \____/____/\__/  /___/_/ /_/____/\__/\__,_/_/_/

EOF
}

RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

set -euo pipefail
shopt -s inherit_errexit nullglob

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

get_pve_version() {
  local pve_ver
  pve_ver="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
  echo "$pve_ver"
}

get_pve_major_minor() {
  local ver="$1"
  local major minor
  IFS='.' read -r major minor _ <<<"$ver"
  echo "$major $minor"
}

component_exists_in_sources() {
  local component="$1"
  grep -h -E "^[^#]*Components:[^#]*\b${component}\b" /etc/apt/sources.list.d/*.sources 2>/dev/null | grep -q .
}

main() {
  header_info
  echo -e "\nThis script will Perform Post Install Routines.\n"
  while true; do
    read -p "Start the Proxmox VE Post Install Script (y/n)? " yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*)
      clear
      exit
      ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  local PVE_VERSION PVE_MAJOR PVE_MINOR
  PVE_VERSION="$(get_pve_version)"
  read -r PVE_MAJOR PVE_MINOR <<<"$(get_pve_major_minor "$PVE_VERSION")"

  if [[ "$PVE_MAJOR" == "8" ]]; then
    if ((PVE_MINOR < 0 || PVE_MINOR > 9)); then
      msg_error "Unsupported Proxmox 8 version"
      exit 1
    fi
    start_routines_8
  elif [[ "$PVE_MAJOR" == "9" ]]; then
    if ((PVE_MINOR != 0)); then
      msg_error "Only Proxmox 9.0 is currently supported"
      exit 1
    fi
    start_routines_9
  else
    msg_error "Unsupported Proxmox VE major version: $PVE_MAJOR"
    echo -e "Supported: 8.0–8.9.x and 9.0"
    exit 1
  fi
}

# -------------------------------
# Firewall helper function
# -------------------------------
firewall_setup() {
  FIREWALL_CONF="/etc/pve/firewall/cluster.fw"
  if [ ! -f "$FIREWALL_CONF" ]; then
    echo "[OPTIONS]" > "$FIREWALL_CONF"
    echo "enable: 1" >> "$FIREWALL_CONF"
    echo "" >> "$FIREWALL_CONF"
    echo "[RULES]" >> "$FIREWALL_CONF"
  fi

  # Required: Allow 8006
  grep -q "IN ACCEPT -p tcp -dport 8006" "$FIREWALL_CONF" || \
      echo "IN ACCEPT -p tcp -dport 8006" >> "$FIREWALL_CONF"

  # Optional SSH and ICMP
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "FIREWALL" \
    --checklist "Select additional firewall rules to enable (required: 8006 already enabled):" 12 60 2 \
    "SSH" "Allow SSH port 22" OFF \
    "PING" "Allow ICMP/ping" OFF 3>&2 2>&1 1>&3)

  for rule in $CHOICE; do
    case $rule in
      \"SSH\") grep -q "IN ACCEPT -p tcp -dport 22" "$FIREWALL_CONF" || echo "IN ACCEPT -p tcp -dport 22" >> "$FIREWALL_CONF" ;;
      \"PING\") grep -q "IN ACCEPT -p icmp" "$FIREWALL_CONF" || echo "IN ACCEPT -p icmp" >> "$FIREWALL_CONF" ;;
    esac
  done

  msg_ok "Firewall rules applied"
}

# -------------------------------
# Post routines common
# -------------------------------
post_routines_common() {
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUBSCRIPTION NAG" --menu "This will disable the nag message reminding you to purchase a subscription every time you log in to the web interface.\n \nDisable subscription nag?" 14 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
    msg_info "Disabling subscription nag"
    mkdir -p /usr/local/bin
    cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
EOF
    chmod 755 /usr/local/bin/pve-remove-nag.sh
    cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
    chmod 644 /etc/apt/apt.conf.d/no-nag-script
    msg_ok "Disabled subscription nag (Delete browser cache)"
    ;;
  no)
    msg_error "Selected no to Disabling subscription nag"
    rm /etc/apt/apt.conf.d/no-nag-script 2>/dev/null
    ;;
  esac

  # Firewall setup
  firewall_setup

  # Ask about HA services
  if ! systemctl is-active --quiet pve-ha-lrm; then
    CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" --menu "Enable high availability?" 10 58 2 \
      "yes" " " \
      "no" " " 3>&2 2>&1 1>&3)
    case $CHOICE in
    yes)
      msg_info "Enabling high availability"
      systemctl enable -q --now pve-ha-lrm
      systemctl enable -q --now pve-ha-crm
      systemctl enable -q --now corosync
      msg_ok "Enabled high availability"
      ;;
    no) msg_error "Selected no to Enabling high availability" ;;
    esac
  fi

  # Update Proxmox
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "UPDATE" --menu "\nUpdate Proxmox VE now?" 11 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    msg_info "Updating Proxmox VE (Patience)"
    apt update &>/dev/null || msg_error "apt update failed"
    apt -y dist-upgrade &>/dev/null || msg_error "apt dist-upgrade failed"
    msg_ok "Updated Proxmox VE"
    ;;
  no) msg_error "Selected no to Updating Proxmox VE" ;;
  esac

  # Final reboot reminder
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "REBOOT" --menu "\nReboot Proxmox VE now? (recommended)" 11 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    msg_info "Rebooting Proxmox VE"
    sleep 2
    msg_ok "Completed Post Install Routines"
    reboot
    ;;
  no)
    msg_error "Selected no to Rebooting Proxmox VE (Reboot recommended)"
    msg_ok "Completed Post Install Routines"
    ;;
  esac
}

# -------------------------------
# Placeholder routines for 8.x / 9.0
# -------------------------------
start_routines_8() {
  header_info
  # Original 8.x routines here...
  post_routines_common
}

start_routines_9() {
  header_info
  # Original 9.0 routines here...
  post_routines_common
}

main
