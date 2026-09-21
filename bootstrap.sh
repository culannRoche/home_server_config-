	##	SERVER SETUP SCRIPT	##

# This script is designed to setup a Debian server that containerises services using docker

# It is designed to be executed on a fresh Debian install with the ssh server and standard system utilities options

#!/usr/bin/env bash

# This creates a safe environment for execution, stopping if any error is encoutnered
set -euo pipefail
IFS=$'\n\t'
if [[ "$EUID" -ne 0 ]]; then
  echo "Error: This script must be run as root."
  exit 1
fi

# The script will not wait for prompt screens
export DEBIAN_FRONTEND=noninteractive

# Installing packages
apt-get update
apt-get upgrade -y

apt-get install -y --no-install-recommends \
	git \
	docker.io \
	docker-compose-v2 \
	smartmontools \
	lm-sensors\ 
	unattended-upgrades \
	htop \
	ncdu

# Configuring packages
systemctl enable --now docker

sensors-detect --auto > /dev/null
systemctl restart systemd-modules-load.service || true

sed -i -E 's/^DEVICESCAN.*/DEVICESCAN -a -s (S\/..\/..\/.\/02|L\/..\/6\/03)/' /etc/smartd.conf
systemctl enable --now smartmontools

cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades-custom
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

apt-get autoremove -y
apt-get clean

# Modify logind.conf to ignore the lid switch
sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf

# Changes log management settings to limit size of log files for efficiency
# Docker log management
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

# systemd log management
if grep -q "^#\?SystemMaxUse=" /etc/systemd/journald.conf; then
  # Replaces existing '#SystemMaxUse=' or 'SystemMaxUse=' line idempotently
  sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
else
  # Appends if line does not exist in the file
  echo "SystemMaxUse=500M" >> /etc/systemd/journald.conf
fi
systemctl restart systemd-journald

# Set up directory for containers and assigns ownership to the user executing the script
TARGET_USER="${SUDO_USER:-$USER}"
mkdir -p /opt/containers
if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" /opt/containers
  chmod 755 /opt/containers
fi

# This must run last, it activates the new configs
systemctl restart systemd-logind
