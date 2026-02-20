#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Namecheap DDNS Init (systemd timer) — multi-host
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
#   - Creates /opt/ddns/hosts.d/ directory
#   - Creates a template .env per host (chmod 600)
#   - Installs /opt/ddns/namecheap-ddns.sh (updater — loops all hosts)
#   - Installs systemd service + timer
#   - Enables and starts the timer
#
# ONE INSTANCE PER MACHINE:
#   All hostnames served from the same machine share the same
#   public IP, so one DDNS service handles them all. Just add
#   one .env per hostname in /opt/ddns/hosts.d/.
#
# REQUIRED (Namecheap side, per host):
#   - Change the record to: "A + Dynamic DNS Record"
#   - Copy the Dynamic DNS password for that host
#
# NOTES:
#   - One .env file per hostname in /opt/ddns/hosts.d/
#   - Edit each .env after running this script
#   - This uses Namecheap Dynamic DNS endpoint:
#       https://dynamicdns.park-your-domain.com/update
# ============================================================

DDNS_DIR="/opt/ddns"
HOSTS_DIR="${DDNS_DIR}/hosts.d"
SCRIPT_FILE="${DDNS_DIR}/namecheap-ddns.sh"
SERVICE_FILE="/etc/systemd/system/namecheap-ddns.service"
TIMER_FILE="/etc/systemd/system/namecheap-ddns.timer"
STATE_DIR="${DDNS_DIR}/state"

install -d -m 0755 "${DDNS_DIR}"
install -d -m 0755 "${HOSTS_DIR}"
install -d -m 0755 "${STATE_DIR}"

# -------------------------
# 1) Create env templates
# -------------------------
# Migrate legacy single env file if present
LEGACY_ENV="${DDNS_DIR}/namecheap.env"
if [[ -f "${LEGACY_ENV}" ]]; then
  echo "Found legacy env file: ${LEGACY_ENV}"
  # Extract RECORD_HOST to derive new filename
  legacy_host="$(grep -oP '(?<=^RECORD_HOST=")[^"]+' "${LEGACY_ENV}" 2>/dev/null || true)"
  if [[ -n "${legacy_host}" && "${legacy_host}" != "REPLACE_ME" ]]; then
    new_name="${HOSTS_DIR}/${legacy_host}.env"
    if [[ ! -f "${new_name}" ]]; then
      mv "${LEGACY_ENV}" "${new_name}"
      chmod 600 "${new_name}"
      echo "  -> Migrated to ${new_name}"
    else
      echo "  -> ${new_name} already exists; legacy file left in place."
    fi
  else
    echo "  -> RECORD_HOST not set in legacy file; skipping migration."
  fi
fi

create_host_env() {
  local record_host="$1"
  local description="$2"
  local env_file="${HOSTS_DIR}/${record_host}.env"

  if [[ -f "${env_file}" ]]; then
    echo "Host env already exists: ${env_file} (leaving as-is)"
    chmod 600 "${env_file}"
    return
  fi

  cat > "${env_file}" <<EOF
# Namecheap DDNS config — ${description}
#
# IMPORTANT:
# - In Namecheap Advanced DNS, set the record to: "A + Dynamic DNS Record"
# - Copy the Dynamic DNS password for that host record
# - Do NOT commit this file to git.

# Zone / domain
NAMECHEAP_DOMAIN="adacapital.io"

# Hostname *within* the zone (no domain suffix)
# "${record_host}" -> ${record_host}.adacapital.io
RECORD_HOST="${record_host}"

# Dynamic DNS password (from Namecheap "A + Dynamic DNS Record")
NAMECHEAP_DDNS_PASSWORD="REPLACE_ME"

# TTL (seconds) - should match what you set in Namecheap
TTL="60"

# Public IP discovery endpoint (IPv4)
PUBLIC_IP_URL="https://ifconfig.me"

# Optional: set to 1 to force an update every run (normally 0)
FORCE_UPDATE="0"
EOF
  chmod 600 "${env_file}"
  echo "Created ${env_file} (template). Please edit and set NAMECHEAP_DDNS_PASSWORD."
}

# Create env files for each host on this machine
create_host_env "adact.preview.relay1" "Preview relay1"
create_host_env "@"                    "adacapital.io (apex domain)"

# -------------------------
# 2) Install DDNS updater
# -------------------------
cat > "${SCRIPT_FILE}" <<'UPDATER'
#!/usr/bin/env bash
set -euo pipefail

HOSTS_DIR="/opt/ddns/hosts.d"
STATE_DIR="/opt/ddns/state"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

required_vars=(
  NAMECHEAP_DOMAIN
  RECORD_HOST
  NAMECHEAP_DDNS_PASSWORD
  TTL
  PUBLIC_IP_URL
  FORCE_UPDATE
)

# Fetch WAN IP once (shared across all hosts — same public IP)
current_ip="$(curl -4 -sS --max-time 10 "https://ifconfig.me" | tr -d '[:space:]')"
if [[ ! "${current_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  log "ERROR: Invalid IPv4 from ifconfig.me: '${current_ip}'"
  exit 1
fi
log "WAN IP: ${current_ip}"

env_files=("${HOSTS_DIR}"/*.env)
if [[ ! -e "${env_files[0]}" ]]; then
  log "ERROR: No .env files found in ${HOSTS_DIR}"
  exit 1
fi

errors=0

for env_file in "${env_files[@]}"; do
  # Reset vars for each host
  NAMECHEAP_DOMAIN="" RECORD_HOST="" NAMECHEAP_DDNS_PASSWORD=""
  TTL="" PUBLIC_IP_URL="" FORCE_UPDATE=""

  # shellcheck source=/dev/null
  source "${env_file}"

  # Validate
  skip=0
  for v in "${required_vars[@]}"; do
    if [[ -z "${!v:-}" || "${!v:-}" == "REPLACE_ME" ]]; then
      log "SKIP: ${v} not set in ${env_file}"
      skip=1
      break
    fi
  done
  (( skip )) && continue

  if [[ "${RECORD_HOST}" == "@" ]]; then
    fqdn="${NAMECHEAP_DOMAIN}"
  else
    fqdn="${RECORD_HOST}.${NAMECHEAP_DOMAIN}"
  fi
  state_file="${STATE_DIR}/${RECORD_HOST//\//_}.last_ip"

  # Compare with last known IP
  last_ip=""
  if [[ -f "${state_file}" ]]; then
    last_ip="$(cat "${state_file}" 2>/dev/null | tr -d '[:space:]' || true)"
  fi

  if [[ "${FORCE_UPDATE}" != "1" && "${current_ip}" == "${last_ip}" ]]; then
    log "No change: ${fqdn} is still ${current_ip}. Skipping."
    continue
  fi

  # Call Namecheap Dynamic DNS endpoint
  update_url="https://dynamicdns.park-your-domain.com/update?host=${RECORD_HOST}&domain=${NAMECHEAP_DOMAIN}&password=${NAMECHEAP_DDNS_PASSWORD}&ip=${current_ip}&ttl=${TTL}"
  resp="$(curl -sS --max-time 15 "${update_url}" || true)"

  if echo "${resp}" | grep -q "<ErrCount>0</ErrCount>" && echo "${resp}" | grep -qi "<Done>true</Done>"; then
    log "UPDATED: ${fqdn} -> ${current_ip}"
    echo -n "${current_ip}" > "${state_file}"
    chmod 600 "${state_file}"
  else
    log "ERROR: Update failed for ${fqdn}. Response:"
    echo "${resp}" | sed 's/password=[^&"]\+/password=REDACTED/g'
    (( errors++ ))
  fi
done

if (( errors > 0 )); then
  log "Finished with ${errors} error(s)."
  exit 2
fi

log "All hosts up to date."
UPDATER

chmod 755 "${SCRIPT_FILE}"
echo "Installed updater script: ${SCRIPT_FILE}"

# -------------------------
# 3) systemd service
# -------------------------
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Namecheap DDNS updater (multi-host)
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
echo "Namecheap DDNS automation installed (multi-host)."
echo
echo "Host env files:"
for f in "${HOSTS_DIR}"/*.env; do
  [[ -e "$f" ]] && echo "  $f"
done
echo
echo "Next steps:"
echo "1) Edit each env file:  sudo nano ${HOSTS_DIR}/<name>.env"
echo "2) One-off test:        sudo systemctl start namecheap-ddns.service"
echo "3) View logs:           sudo journalctl -u namecheap-ddns.service -n 100 --no-pager"
echo "4) Timer status:        systemctl list-timers | grep namecheap-ddns"
echo
echo "To add more hosts later:"
echo "  sudo cp ${HOSTS_DIR}/adact.preview.relay1.env ${HOSTS_DIR}/new-host.env"
echo "  sudo nano ${HOSTS_DIR}/new-host.env"
echo
echo "Reminder: In Namecheap Advanced DNS, set each record to 'A + Dynamic DNS Record'."
