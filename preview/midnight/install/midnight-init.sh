#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
BASE_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
SPOT_DIR="$(realpath "$(dirname "$BASE_DIR")")"
UTILS_PATH="$SPOT_DIR/scripts"
CONF_PATH="$SCRIPT_DIR/config"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "BASE_DIR: $BASE_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "UTILS_PATH: $UTILS_PATH"
echo "CONF_PATH: $CONF_PATH"
echo

# exit 1

# importing utility functions
source $UTILS_PATH/utils.sh

echo "MIDNIGHT-INIT STARTING..."
echo

sudo apt update
sudo apt install -y ufw iptables-persistent

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 3001/tcp # Cardano relay node 
sudo ufw allow 6001/tcp # Additional Cardano relay node

# Allow Ogmios
sudo ufw allow 1337/tcp

# Allow Kupo
sudo ufw allow 1442/tcp

# Allow Postgres-db-sync
sudo ufw allow 5432/tcp

# Enable UFW
sudo ufw --force enable

# Ensure UFW is enabled on boot
sudo sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf

# Create systemd override directory for UFW if it doesn't exist
sudo mkdir -p /etc/systemd/system/ufw.service.d

# Create override.conf to enforce UFW enablement
echo -e "[Service]\nExecStart=\nExecStart=/lib/ufw/ufw-init start\nExecStartPost=/usr/sbin/ufw --force enable\nExecStartPost=/bin/bash -c 'sleep 10 && /usr/sbin/ufw --force enable'" | sudo tee /etc/systemd/system/ufw.service.d/override.conf

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Restart UFW service
sudo systemctl restart ufw

# Save iptables rules to ensure persistence
sudo iptables-save | sudo tee /etc/iptables/rules.v4
sudo ip6tables-save | sudo tee /etc/iptables/rules.v6
sudo netfilter-persistent save

# Enable UFW and netfilter-persistent services to start on boot
sudo systemctl enable ufw
sudo systemctl enable netfilter-persistent
sudo systemctl restart netfilter-persistent

# Prevent Docker from overriding UFW rules
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo bash -c 'cat > /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStartPre=/bin/bash -c "/usr/sbin/ufw --force enable || true"
ExecStartPre=/bin/sleep 10
ExecStart=
ExecStart=/usr/bin/dockerd --iptables=false -H fd:// --containerd=/run/containerd/containerd.sock
EOF'

# Reload systemd and restart Docker to apply changes
sudo systemctl daemon-reload
sudo systemctl restart docker

# Confirm UFW and Docker status
sudo systemctl status ufw
sudo systemctl status docker

# Confirm that iptables rules are still in place
sudo ufw status verbose

echo "Make sure to add ports 1337 & 1442 to your NSG & Egress rules too!"

