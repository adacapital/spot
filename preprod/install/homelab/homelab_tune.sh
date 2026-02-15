#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Setting nofile limits..."
LIMITS_FILE="/etc/security/limits.conf"
LIMITS_BLOCK_START="# BEGIN HOMELAB-CARDANO"
LIMITS_BLOCK_END="# END HOMELAB-CARDANO"
LIMITS_BLOCK=$(cat <<'EOF'
# BEGIN HOMELAB-CARDANO
* soft nofile 1048576
* hard nofile 1048576
# END HOMELAB-CARDANO
EOF
)

if ! sudo grep -qF "$LIMITS_BLOCK_START" "$LIMITS_FILE"; then
  echo "$LIMITS_BLOCK" | sudo tee -a "$LIMITS_FILE" >/dev/null
  echo "  - Added limits block to $LIMITS_FILE"
else
  echo "  - Limits block already present, skipping"
fi

echo "[2/4] Writing sysctl tuning..."
SYSCTL_FILE="/etc/sysctl.d/99-homelab-cardano.conf"
sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
# Homelab baseline for Cardano / db-sync style workloads

# Reduce swapping (keep cache, avoid thrash)
vm.swappiness=10

# Network buffer ceilings (safe on modern kernels)
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.netdev_max_backlog=5000

# TCP buffer autotuning ranges
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF

echo "  - Wrote $SYSCTL_FILE"
echo "  - Applying sysctl..."
sudo sysctl --system >/dev/null

echo "[3/4] Enabling fstrim.timer if present..."
if systemctl list-unit-files | grep -q '^fstrim\.timer'; then
  sudo systemctl enable --now fstrim.timer >/dev/null
  echo "  - fstrim.timer enabled"
else
  echo "  - fstrim.timer not found (ok)"
fi

echo "[4/4] Done."
echo "NOTE: nofile limit applies to new sessions; for full effect, reboot is recommended."
