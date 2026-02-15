#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Namecheap DDNS Init (systemd timer)
#
# HOW TO RUN:
#   This script must be run as root because it installs files
#   under /opt and /etc/systemd.
#
#   Recommended:
#     sudo bash init_namecheap_ddns.sh
#
#   Alternative:
#     chmod +x init_namecheap_ddns.sh
#     sudo ./init_namecheap_ddns.sh
#
# WHAT THIS DOES:
#   - Creates /opt/ddns
#   - Creates /opt/ddns/namecheap.env (template, chmod 600)
#   - Installs /opt/ddns/namecheap-ddns.sh (updater)
#   - Installs systemd service + timer
#   - Enables and starts the timer
#
# REQUIRED (Namecheap side):
#   - Change the record to: "A + Dynamic DNS Record"
#   - Copy the Dynamic DNS password for that host
#
# NOTES:
#   - Edit /opt/ddns/namecheap.env after running this script
#   - This uses Namecheap Dynamic DNS endpoint:
#       https://dynamicdns.park-your-domain.com/update
# ============================================================

DDNS_DIR="/opt/ddns"
ENV_FILE="${DDNS_DIR}/namecheap.env"
SCRIPT_FILE="${DDNS_DIR}/namecheap-ddns.sh"
SERVICE_FILE="/etc/systemd/system/namecheap-ddns.service"
TIMER_FILE="/etc/systemd/system/namecheap-ddns.timer"
STATE_DIR="${DDNS_DIR}/state"

install -d -m 0755 "${DDNS_DIR}"
install -d -m 0755 "${STATE_DIR}"

# -------------------------
# 1) Create env template
# -------------------------
if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
# Namecheap DDNS config (Dynamic DNS password, per-host)
#
# IMPORTANT:
# - In Namecheap Advanced DNS, set the record to: "A + Dynamic DNS Record"
# - Copy the Dynamic DNS password for that host record
# - Do NOT commit this file to git.

# Zone / domain
NAMECHEAP_DOMAIN="adacapital.io"

# Hostname *within* the zone (no domain suffix)
# Example: "adact.preprod.relay1" for adact.preprod.relay1.adacapital.io
RECORD_HOST="adact.preprod.relay1"

# Dynamic DNS password (from Namecheap "A + Dynamic DNS Record")
NAMECHEAP_DDNS_PASSWORD="REPLACE_ME"

# TTL (seconds) - should match what you set in Namecheap
TTL="60"

# Public IP discovery endpoint (IPv4)
PUBLIC_IP_URL="https://ifconfig.me"

# Optional: set to 1 to force an update every run (normally 0)
FORCE_UPDATE="0"
EOF
  chmod 600 "${ENV_FILE}"
  echo "Created ${ENV_FILE} (template). Please edit it and set real values. (chmod 600 applied)"
else
  echo "Env file already exists: ${ENV_FILE} (leaving as-is)"
  chmod 600 "${ENV_FILE}"
fi

# -------------------------
# 2) Install DDNS updater
# -------------------------
cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/ddns/namecheap.env"
STATE_DIR="/opt/ddns/state"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

if [[ ! -f "${ENV_FILE}" ]]; then
  log "ERROR: Missing env file at ${ENV_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

required_vars=(
  NAMECHEAP_DOMAIN
  RECORD_HOST
  NAMECHEAP_DDNS_PASSWORD
  TTL
  PUBLIC_IP_URL
  FORCE_UPDATE
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" || "${!v:-}" == "REPLACE_ME" ]]; then
    log "ERROR: ${v} is not set correctly in ${ENV_FILE}"
    exit 1
  fi
done

if [[ ! -d "${STATE_DIR}" ]]; then
  log "ERROR: Missing state directory at ${STATE_DIR}"
  exit 1
fi

fqdn="${RECORD_HOST}.${NAMECHEAP_DOMAIN}"
state_file="${STATE_DIR}/${RECORD_HOST//\//_}.last_ip"

# 1) Determine current WAN IPv4
current_ip="$(curl -4 -sS --max-time 10 "${PUBLIC_IP_URL}" | tr -d '[:space:]')"
if [[ ! "${current_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  log "ERROR: Invalid IPv4 detected from ${PUBLIC_IP_URL}: '${current_ip}'"
  exit 1
fi

# 2) Compare with last known IP (local state)
last_ip=""
if [[ -f "${state_file}" ]]; then
  last_ip="$(cat "${state_file}" 2>/dev/null || true | tr -d '[:space:]')"
fi

if [[ "${FORCE_UPDATE}" != "1" && "${current_ip}" == "${last_ip}" ]]; then
  log "No change: ${fqdn} is still ${current_ip}. Skipping update."
  exit 0
fi

# 3) Call Namecheap Dynamic DNS endpoint
# Note: password here is the Dynamic DNS password for this host record
update_url="https://dynamicdns.park-your-domain.com/update?host=${RECORD_HOST}&domain=${NAMECHEAP_DOMAIN}&password=${NAMECHEAP_DDNS_PASSWORD}&ip=${current_ip}&ttl=${TTL}"

resp="$(curl -sS --max-time 15 "${update_url}" || true)"

# 4) Verify response indicates success
# Namecheap returns XML. Success typically includes:
#   <ErrCount>0</ErrCount> and <Done>true</Done>
if echo "${resp}" | grep -q "<ErrCount>0</ErrCount>" && echo "${resp}" | grep -qi "<Done>true</Done>"; then
  log "UPDATED: ${fqdn} -> ${current_ip}"
  echo -n "${current_ip}" > "${state_file}"
  chmod 600 "${state_file}"
  exit 0
fi

log "ERROR: Namecheap DDNS update failed for ${fqdn}. Response:"
# Redact password if it ever appears (usually it won't, but belt-and-braces)
echo "${resp}" | sed 's/password=[^&"]\+/password=REDACTED/g'
exit 2
EOF

chmod 755 "${SCRIPT_FILE}"
echo "Installed updater script: ${SCRIPT_FILE}"

# -------------------------
# 3) systemd service
# -------------------------
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Namecheap DDNS updater (Cardano relay)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_FILE}
User=root
Group=root

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DDNS_DIR}
EOF

echo "Installed systemd service: ${SERVICE_FILE}"

# -------------------------
# 4) systemd timer
# -------------------------
cat > "${TIMER_FILE}" <<'EOF'
[Unit]
Description=Run Namecheap DDNS updater every 5 minutes

[Timer]
OnBootSec=60s
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "Installed systemd timer: ${TIMER_FILE}"

# -------------------------
# 5) Enable + start
# -------------------------
systemctl daemon-reload
systemctl enable --now namecheap-ddns.timer

echo
echo "✅ Namecheap DDNS automation installed (Dynamic DNS password mode)."
echo
echo "Next steps:"
echo "1) Edit config:   sudo nano ${ENV_FILE}"
echo "2) One-off test:  sudo systemctl start namecheap-ddns.service"
echo "3) View logs:     sudo journalctl -u namecheap-ddns.service -n 100 --no-pager"
echo "4) Timer status:  systemctl list-timers | grep namecheap-ddns"
echo
echo "Reminder: In Namecheap Advanced DNS, set the record type to 'A + Dynamic DNS Record' and copy the DDNS password."
