#!/usr/bin/env bash
# Enable host Postgres to accept connections from Docker/Compose networks.

# Usage:
# 
# Broad allow (any DB/user from Docker networks):
# sudo bash enable-pg-docker.sh
# 
# Narrow allow (only your DB/user):
# DB_NAME=cardanobi-preview DB_USER=cardano sudo bash enable-pg-docker.sh
# 
# If your cluster uses md5 auth instead of scram:
# AUTH_METHOD=md5 sudo bash enable-pg-docker.sh


set -euo pipefail

# ---- Options (set via env) ----
: "${AUTH_METHOD:=scram-sha-256}"   # or md5 if your cluster uses md5
: "${PG_PORT:=5432}"                # Postgres port
# Optional: scope rule to specific DB/user (fallback is all/all)
: "${DB_NAME:=}"
: "${DB_USER:=}"

echo "Auth: ${AUTH_METHOD}  Port: ${PG_PORT}  Scope: ${DB_NAME:-all}/${DB_USER:-all}"

# ---- Discover ALL Docker subnets ----
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found; please install Docker." >&2
  exit 1
fi
mapfile -t SUBNETS < <(
  docker network ls -q |
    xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' |
    sed '/^$/d' | sort -u
)
if ((${#SUBNETS[@]}==0)); then
  SUBNETS=("172.17.0.0/16")  # sensible default
fi
echo "Docker subnets: ${SUBNETS[*]}"

# ---- Locate Postgres config files ----
HBA_FILE="$(sudo -u postgres psql -tAc "SHOW hba_file")"
CONF_FILE="$(sudo -u postgres psql -tAc "SHOW config_file")"
echo "pg_hba.conf: ${HBA_FILE}"
echo "postgresql.conf: ${CONF_FILE}"

# ---- Backup originals (once) ----
sudo cp -n "${HBA_FILE}" "${HBA_FILE}.bak" || true
sudo cp -n "${CONF_FILE}" "${CONF_FILE}.bak" || true

# ---- Ensure Postgres listens beyond localhost ----
# If listen_addresses isn't '*', set it to '*'.
if ! sudo grep -Eq "^[^#]*listen_addresses\s*=\s*'\*'" "${CONF_FILE}"; then
  if sudo grep -Eq "^[#[:space:]]*listen_addresses\s*=" "${CONF_FILE}"; then
    sudo sed -i -E "s/^[#[:space:]]*listen_addresses\s*=\s*'.*'/listen_addresses = '*'/g" "${CONF_FILE}"
  else
    echo "listen_addresses = '*'" | sudo tee -a "${CONF_FILE}" >/dev/null
  fi
  echo "Updated listen_addresses in ${CONF_FILE}"
fi

# ---- Add pg_hba rule(s) for each Docker subnet ----
for SN in "${SUBNETS[@]}"; do
  if [[ -n "$DB_NAME" && -n "$DB_USER" ]]; then
    RULE="host  ${DB_NAME}  ${DB_USER}  ${SN}  ${AUTH_METHOD}"
  else
    RULE="host  all  all  ${SN}  ${AUTH_METHOD}"
  fi

  if ! sudo grep -qE "[[:space:]]${SN//\./\\.}([[:space:]]|$)" "${HBA_FILE}"; then
    echo "${RULE}" | sudo tee -a "${HBA_FILE}" >/dev/null
    echo "Appended '${RULE}' to ${HBA_FILE}"
  else
    echo "pg_hba already has a rule for ${SN}"
  fi
done

# ---- Reload / Restart Postgres ----
sudo systemctl reload postgresql 2>/dev/null || \
sudo systemctl restart postgresql 2>/dev/null || \
sudo service postgresql restart
echo "Postgres reloaded/restarted."

# ---- UFW: allow each Docker subnet to the PG port ----
if command -v ufw >/dev/null 2>&1; then
  for SN in "${SUBNETS[@]}"; do
    sudo ufw allow from "${SN}" to any port "${PG_PORT}" proto tcp || true
  done
  echo "UFW rules ensured for: ${SUBNETS[*]} -> ${PG_PORT}/tcp"
else
  echo "ufw not found; skipping firewall changes."
fi

# ---- Show listening sockets ----
echo "Listening sockets:"
ss -lntp | grep ":${PG_PORT}" || true
