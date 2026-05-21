#!/bin/bash
# Pre-flight check for mainnet relays before running update_node_binaries.sh.
# Verifies, per relay, that:
#   1. The per-host SSH key exists at ~/.ssh/adact-mainnet-<relayname>
#   2. SSH connectivity to the relay works
#   3. NOPASSWD sudoers is configured for systemctl on run.relay
#
# The third check is the critical one — without NOPASSWD, the update script's
# `sudo -n systemctl stop run.relay` calls fail silently and the relay keeps
# running the old binary. See HOMELAB.md and the 2026-05-20 CHANGELOG entry
# for the historical context behind why this check exists.
#
# Run on the mainnet BP. Reads pool_topology to discover relay list.

NOW=$(date +"%Y%m%d_%H%M%S")
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE="$ROOT_PATH/pool_topology"

echo "PREFLIGHT RELAY SUDOERS CHECK"
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "ROOT_PATH:  $ROOT_PATH"
echo "TOPO_FILE:  $TOPO_FILE"
echo

# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

# Read topology
read ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
if [[ "$ERROR" != "none" ]]; then
    echo "ERROR: $ERROR"
    exit 1
fi
if (( cnt == 0 )); then
    echo "No relays listed in $TOPO_FILE. Nothing to check."
    exit 0
fi
if (( cnt % 3 != 0 )); then
    echo "ERROR: RELAYS list length ($cnt) not divisible by 3. pool_topology/get_topo mismatch."
    exit 1
fi

let cnt1="$cnt/3"
RELAY_IPS=(   "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt1}" )

echo "Discovered $cnt1 relay(s):"
for (( i=0; i<cnt1; i++ )); do
    echo "  [$i] ${RELAY_NAMES[$i]} @ ${RELAY_IPS[$i]}"
done
echo

# Pre-flight checks
SSH_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"
FAILED=0

for (( i=0; i<cnt1; i++ )); do
    ip="${RELAY_IPS[$i]}"
    name="${RELAY_NAMES[$i]}"
    key="$HOME/.ssh/adact-mainnet-${name}"
    echo "=== $name ($ip) ==="

    # 1. SSH key file exists
    if [[ ! -f "$key" ]]; then
        echo "  ✗ SSH key missing at $key"
        FAILED=$((FAILED+1))
        echo
        continue
    fi
    echo "  ✓ SSH key found: $key"

    # 2. SSH connectivity
    if ! ssh $SSH_OPTS -i "$key" "cardano@${ip}" "echo ok >/dev/null" 2>/dev/null; then
        echo "  ✗ SSH connectivity to cardano@${ip} failed (key, network, or host-key issue)"
        FAILED=$((FAILED+1))
        echo
        continue
    fi
    echo "  ✓ SSH connectivity ok"

    # 3. NOPASSWD sudoers for systemctl on run.relay
    sudo_out=$(ssh $SSH_OPTS -i "$key" "cardano@${ip}" 'sudo -n systemctl is-active run.relay 2>&1; echo "__rc=$?"')
    if echo "$sudo_out" | grep -q 'password is required'; then
        echo "  ✗ NOPASSWD sudoers NOT configured"
        echo "    Install /etc/sudoers.d/cardano-systemctl on this relay — see HOMELAB.md or preprod_migration_runbook.md Step 7b for the procedure"
        FAILED=$((FAILED+1))
    elif echo "$sudo_out" | grep -q '__rc=0'; then
        relay_state=$(echo "$sudo_out" | head -1)
        echo "  ✓ NOPASSWD sudoers configured; run.relay is currently: $relay_state"
    else
        echo "  ? Unexpected sudo response — inspect manually:"
        echo "$sudo_out" | sed 's/^/      /'
        FAILED=$((FAILED+1))
    fi
    echo
done

echo "============================================================"
if (( FAILED == 0 )); then
    echo "✓ All $cnt1 relay(s) passed pre-flight. Safe to run update_node_binaries.sh."
    exit 0
else
    echo "✗ $FAILED of $cnt1 relay(s) failed pre-flight. Fix issues above before running update_node_binaries.sh."
    exit 1
fi
