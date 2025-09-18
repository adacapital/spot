#!/usr/bin/env bash
# Midnight Node Monitor (boxed TUI) — UTF-8 default, clean quit, robust key discovery
set -Euo pipefail

# put this just after the trap setup
if [[ -n "${DEBUG:-}" ]]; then
  exec 2>tui-debug.log
  set -x
fi

on_err() {
  local ec=$? ln=${BASH_LINENO[0]} cmd=${BASH_COMMAND:-}
  tput sgr0; tput cnorm
  printf '\n\nERROR (exit %d) at line %s: %s\n' "$ec" "$ln" "$cmd" >&2
  echo "Tip: run with DEBUG=1 or check tui.err.log for details." >&2
  [[ -n "${DEBUG:-}" ]] && read -n1 -s -p "Press any key to close..." || true
}
trap on_err ERR


# If you want a persistent error log:
exec 3>tui.err.log
# sprinkle `>&3` on places you want extra logs (optional)

# ---------- config ----------
LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:9944}"
PUBLIC_RPC="${PUBLIC_RPC:-https://rpc.testnet-02.midnight.network/}"
CONTAINER="${CONTAINER:-midnight}"
REFRESH_SEC="${REFRESH_SEC:-1}"
HEAVY_EVERY="${HEAVY_EVERY:-2}"   # do RPC every 2 ticks
PROM_EVERY="${PROM_EVERY:-5}"     # do Prom scrape every 5 ticks
RES_EVERY_SEC="${RES_EVERY_SEC:-60}"   # refresh CPU/MEM/DB/disk every 60s

RPC_PORT="${RPC_PORT:-9944}"

# Optional hints
KS_PATH="${KS_PATH:-}"                         # host keystore dir (files are public keys)
SIDECHAIN_PUBKEY="${SIDECHAIN_PUBKEY:-}"       # 0x03.. (33-byte compressed secp256k1)
NODE_DB_PATH="${NODE_DB_PATH:-/node/chain/chains/testnet-02/paritydb/full}"

# Local registration JSON cache/override (any of these if present)
REG_FILES=(
  "./midnight-registration.json"
  "./partner-chains-public-keys.json"
  "./registration.json"
  "./.midnight-registration.cache.json"
)
# ----------------------------

have(){ command -v "$1" >/dev/null 2>&1; }
for b in curl jq tput docker; do have "$b" || { echo "Missing $b"; exit 1; }; done

# ===== Borders (UTF-8 default, fallback if not supported) =====
USE_UTF8="${USE_UTF8:-1}"
CH=$(locale charmap 2>/dev/null || echo ASCII)
if [[ "$USE_UTF8" == "1" && "$CH" == "UTF-8" ]]; then
  TL='┌'; TR='┐'; BL='└'; BR='┘'; H='─'; V='│'
else
  TL='+'; TR='+'; BL='+'; BR='+'; H='-'; V='|'
fi

# Colors
B=$(tput bold); N=$(tput sgr0)
C1=$(tput setaf 6); C2=$(tput setaf 2); C3=$(tput setaf 3); C4=$(tput setaf 5)
CR=$(tput setaf 1); CW=$(tput setaf 7); G=$(tput setaf 8); CD=$(tput setaf 4)

# Layout offsets
OX=2; OY=1

hex2dec(){ local h="${1#0x}"; [[ "$h" =~ ^[0-9A-Fa-f]+$ ]] || { echo ""; return; }; echo $((16#$h)); }
shorten(){ local s="$1" n="${2:-32}"; [[ ${#s} -le $((n+3)) ]] && echo "$s" || echo "${s:0:n}..."; }
is_hex(){ [[ "$1" =~ ^0x[0-9A-Fa-f]+$ ]]; }
is_sidekey(){ [[ "$1" =~ ^0x0[23][0-9A-Fa-f]{64}$ ]]; }         # 33-byte secp256k1 (02/03 + 32 bytes)
is_32b_hex(){ [[ "$1" =~ ^0x[0-9A-Fa-f]{64}$ ]]; }              # 32-byte (sr25519/ed25519)

rpc(){
  local url="$1" method="$2" params="${3:-[]}"
  curl -sS --max-time 4 -H 'content-type: application/json' \
       --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
       "$url"
}
rval(){ jq -r "$1" 2>/dev/null || true; }

container_started_at(){ docker inspect "$CONTAINER" -f '{{.State.StartedAt}}' 2>/dev/null || true; }
container_stats(){ docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}' "$CONTAINER" 2>/dev/null || true; }
node_volume_mountpoint(){
  docker inspect "$CONTAINER" --format '{{json .Mounts}}' 2>/dev/null \
    | jq -r '.[] | select(.Destination=="/node" or .Destination=="/data") | .Source' | head -n1
}
db_size_h(){
  docker exec "$CONTAINER" sh -lc 'du -sh '"$NODE_DB_PATH"' 2>/dev/null | awk "{print \$1}"' 2>/dev/null || echo "n/a"
}

# ----- Prometheus (9615) -----
# sum a single metric across all label sets
prom_sum(){
  local metric="$1"
  curl -sS --max-time 2 "http://127.0.0.1:9615/metrics" \
   | awk -v m="^"$(printf '%s' "$metric" | sed 's/[][^$.*/]/\\&/g')"([{$]|$)" '
      $0 ~ m && $1 !~ /^#/ { v=$NF; if (v ~ /^[0-9.]+$/) { sum+=v; found=1 } }
      END { if (found) printf "%.0f\n", sum }
   ' || true
}

blocks_authored(){
  local v
  for m in \
    substrate_proposer_block_constructed_total \
    substrate_proposer_block_constructed_count \
    substrate_proposer_block_constructed \
    substrate_blocks_authored_total \
    substrate_blocks_authored_count \
    substrate_blocks_authored \
    aura_proposer_slots_successful_total \
    aura_proposer_slot_success_total
  do
    v="$(prom_sum "$m")"
    [[ -n "${v:-}" ]] && { echo "$v"; return; }
  done
  echo "n/a"
}


# ----- Chain info -----
node_name(){    rpc "$LOCAL_RPC" system_name        | rval '.result'; }
node_version(){ rpc "$LOCAL_RPC" system_version     | rval '.result'; }
node_peer_id(){ rpc "$LOCAL_RPC" system_localPeerId | rval '.result'; }
node_role(){    rpc "$LOCAL_RPC" system_nodeRoles   | rval '.result[0]'; }
best_block_local(){ local h n; h="$(rpc "$LOCAL_RPC" chain_getHead | rval '.result')"; [[ -n "$h" && "$h" != "null" ]] || { echo ""; return; }; n="$(rpc "$LOCAL_RPC" chain_getHeader "[\"$h\"]" | rval '.result.number')"; [[ -n "$n" && "$n" != "null" ]] || { echo ""; return; }; hex2dec "$n"; }
finalized_block_local(){ local h n; h="$(rpc "$LOCAL_RPC" chain_getFinalizedHead | rval '.result')"; [[ -n "$h" && "$h" != "null" ]] || { echo ""; return; }; n="$(rpc "$LOCAL_RPC" chain_getHeader "[\"$h\"]" | rval '.result.number')"; [[ -n "$n" && "$n" != "null" ]] || { echo ""; return; }; hex2dec "$n"; }
best_block_public(){ local h n; h="$(rpc "$PUBLIC_RPC" chain_getHead | rval '.result')"; [[ -n "$h" && "$h" != "null" ]] || { echo ""; return; }; n="$(rpc "$PUBLIC_RPC" chain_getHeader "[\"$h\"]" | rval '.result.number')"; [[ -n "$n" && "$n" != "null" ]] || { echo ""; return; }; hex2dec "$n"; }
epoch_main(){ rpc "$LOCAL_RPC" sidechain_getStatus | rval '.result.mainchain.epoch'; }
epoch_side(){ rpc "$LOCAL_RPC" sidechain_getStatus | rval '.result.sidechain.epoch'; }

# ----- Registration & keys -----
first_existing_file(){ for f in "$@"; do [[ -s "$f" ]] && { echo "$f"; return; }; done; echo ""; }
load_local_reg_json(){ local f; f="$(first_existing_file "${REG_FILES[@]}")"; [[ -n "$f" ]] && cat "$f" || echo ""; }

# stdin JSON (object) → print "AURA SIDE GRANDPA" (flat keys)
extract_keys_from_json(){
  jq -r '
    [
      .auraPubKey       // .aura_pub_key       // "",
      .sidechainPubKey  // .sidechain_pub_key  // "",
      .grandpaPubKey    // .grandpa_pub_key    // ""
    ] | @tsv
  ' 2>/dev/null | head -n1 || true
}


current_side_epoch(){ epoch_side || echo ""; }

ariadne_get_for_epoch(){ # prints full JSON result (or empty)
  local ep="$1"
  rpc "$LOCAL_RPC" sidechain_getAriadneParameters "[$ep]" | rval '.'  # return entire response
}

# reads JSON from stdin, returns 1st object matching sidechainPubKey
find_registration_json(){
  local k="$1"
  jq -c --arg k "$k" '
    .. | objects
    | select( has("sidechainPubKey") or has("sidechain_pub_key") )
    | select( (.sidechainPubKey // .sidechain_pub_key) == $k )
  ' 2>/dev/null | head -n1 || true
}

# Print any 0x… keys found in keystore directory (filenames OR file contents)
scan_keystore_files(){
  local p="$1"; [[ -d "$p" ]] || return 0
  # keys from filenames
  (cd "$p" && ls -1 2>/dev/null | sed -n 's/^\(0x[0-9A-Fa-f]\+\).*$/\1/p')
  # keys from file contents (first 256 bytes)
  while IFS= read -r -d '' f; do
    head -c 256 "$f" 2>/dev/null \
      | tr -d '\r\n\t ' \
      | grep -oE '0x[0-9A-Fa-f]{66,68}|0x[0-9A-Fa-f]{64}' || true
  done < <(find "$p" -maxdepth 1 -type f -print0 2>/dev/null)
}

classify_from_keystore(){
  local p="$1"; local aura="" side="" gran="" k
  while read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$k" =~ ^0x0[23][0-9A-Fa-f]{64}$ ]]; then
      # 33-byte compressed secp256k1 → sidechain key
      side="$k"
    elif [[ "$k" =~ ^0x[0-9A-Fa-f]{64}$ ]]; then
      # 32-byte → aura/grandpa candidates
      if [[ -z "$aura" ]]; then aura="$k"
      elif [[ -z "$gran" ]]; then gran="$k"
      fi
    fi
  done < <(scan_keystore_files "$p")
  echo "$aura" "$side" "$gran"
}
# true if our sidechain key appears in getRegistrations
reg_status_registered(){
  local k="$1"; [[ -z "$k" ]] && { echo ""; return; }
  rpc "$LOCAL_RPC" sidechain_getRegistrations \
  | jq -e --arg k_low "$(echo "$k" | tr 'A-Z' 'a-z')" '
      [ .. | objects
        | select(has("sidechainPubKey") or has("sidechain_pub_key"))
        | (.sidechainPubKey // .sidechain_pub_key | ascii_downcase)
      ] | index($k_low) != null
    ' >/dev/null 2>&1 && echo "Registered" || echo ""
}

# true if our sidechain key appears in current epoch candidateRegistrations
reg_status_candidate(){
  local k="$1" ep js
  [[ -z "$k" ]] && { echo ""; return; }
  ep="$(epoch_side)"; [[ -z "$ep" || "$ep" == "null" ]] && { echo ""; return; }
  js="$(rpc "$LOCAL_RPC" sidechain_getAriadneParameters "[$ep]")"
  echo "$js" \
  | jq -e --arg k_low "$(echo "$k" | tr 'A-Z' 'a-z')" '
      ( .result.candidateRegistrations // .result.registrations // [] | tostring | ascii_downcase )
      | contains($k_low)
    ' >/dev/null 2>&1 && echo "Candidate" || echo ""
}

# in current committee? try side + main epoch to be safe
in_committee_current(){
  local k="$1"; [[ -z "$k" ]] && { echo ""; return; }
  local es em js
  es="$(epoch_side)"; em="$(epoch_main)"
  for ep in "$es" "$em"; do
    [[ -z "$ep" || "$ep" == "null" ]] && continue
    js="$(rpc "$LOCAL_RPC" sidechain_getEpochCommittee "[$ep]")"
    echo "$js" \
    | jq -e --arg k_low "$(echo "$k" | tr 'A-Z' 'a-z')" '
        tostring | ascii_downcase | contains($k_low)
      ' >/dev/null 2>&1 && { echo "yes"; return; }
  done
  echo ""
}


discover_keys(){  # sets globals: AURA_KEY SIDE_KEY GRANDPA_KEY STATUS
  AURA_KEY=""; SIDE_KEY=""; GRANDPA_KEY=""; STATUS=""

  # 1) local registration json
  local localjs; localjs="$(load_local_reg_json)"
  if [[ -n "$localjs" ]]; then
    local line; line="$(printf '%s' "$localjs" | extract_keys_from_json || true)"
    if [[ -n "$line" ]]; then
      AURA_KEY="$(awk '{print $1}' <<<"$line")"
      SIDE_KEY="$(awk '{print $2}' <<<"$line")"
      GRANDPA_KEY="$(awk '{print $3}' <<<"$line")"
    fi
  fi

  # 2) keystore (filenames)
  if [[ -z "${KS_PATH:-}" ]]; then
    for p in \
      "$PWD/data/chains/partner_chains_template/keystore" \
      "/home/cardano/data/midnight-node-docker2/data/chains/partner_chains_template/keystore" \
      "$PWD/data/chains/testnet-02/keystore" \
      "$PWD/data/chains/keystore"
    do [[ -d "$p" ]] && { KS_PATH="$p"; break; }; done
  fi
  if [[ -n "${KS_PATH:-}" && ( -z "$AURA_KEY" || -z "$SIDE_KEY" || -z "$GRANDPA_KEY" ) ]]; then
    read -r aura_guess side_guess gran_guess <<<"$(classify_from_keystore "$KS_PATH")"
    [[ -z "$SIDE_KEY" && -n "$side_guess" ]] && SIDE_KEY="$side_guess"
    # we'll refine aura vs gran after we fetch registration
    [[ -z "$AURA_KEY" && -n "$aura_guess" ]] && AURA_KEY="$aura_guess"
    [[ -z "$GRANDPA_KEY" && -n "$gran_guess" ]] && GRANDPA_KEY="$gran_guess"
  fi

  # Sidechain pubkey hint from env overrides
  [[ -z "$SIDE_KEY" && -n "${SIDECHAIN_PUBKEY:-}" ]] && SIDE_KEY="$SIDECHAIN_PUBKEY"

  # 3) RPC: Registered / Candidate and authoritative aura/grandpa from registration object
  if [[ -n "$SIDE_KEY" ]]; then
    local st; st="$(reg_status_registered "$SIDE_KEY")"
    if [[ "$st" == "Registered" ]]; then
      STATUS="Registered"
      # try to extract keys from full registrations JSON
      local regjs; regjs="$(rpc "$LOCAL_RPC" sidechain_getRegistrations)"
      local obj; obj="$(find_registration_json "$SIDE_KEY" <<<"$regjs")"
      if [[ -n "$obj" ]]; then
        local a g s
        a="$(jq -r '.auraPubKey? // .aura_pub_key? // empty' <<<"$obj")"
        g="$(jq -r '.grandpaPubKey? // .grandpa_pub_key? // empty' <<<"$obj")"
        s="$(jq -r '.sidechainPubKey? // .sidechain_pub_key? // empty' <<<"$obj")"
        [[ -n "$a" ]] && AURA_KEY="$a"
        [[ -n "$g" ]] && GRANDPA_KEY="$g"
        [[ -n "$s" ]] && SIDE_KEY="$s"
        printf '%s\n' "$obj" > .midnight-registration.cache.json 2>/dev/null || true
      fi
      return
    fi
    # else check candidate
    st="$(reg_status_candidate "$SIDE_KEY")"
    if [[ "$st" == "Candidate" ]]; then
      STATUS="Candidate"
      local ep js o
      ep="$(current_side_epoch)"; js="$(ariadne_get_for_epoch "$ep")"
      o="$(printf '%s' "$js" | find_registration_json "$SIDE_KEY")"
      if [[ -n "$o" ]]; then
        local a g s
        a="$(jq -r '.auraPubKey? // .aura_pub_key? // empty' <<<"$o")"
        g="$(jq -r '.grandpaPubKey? // .grandpa_pub_key? // empty' <<<"$o")"
        s="$(jq -r '.sidechainPubKey? // .sidechain_pub_key? // empty' <<<"$o")"
        [[ -n "$a" ]] && AURA_KEY="$a"
        [[ -n "$g" ]] && GRANDPA_KEY="$g"
        [[ -n "$s" ]] && SIDE_KEY="$s"
        printf '%s\n' "$o" > .midnight-registration.cache.json 2>/dev/null || true
      fi
      return
    fi
  fi

  STATUS=""
}

# UI helpers
goto(){ tput cup $((OY+$1)) $((OX+$2)); }
draw_box(){
  local cols=$(tput cols) rows=$(tput lines)
  tput clear
  tput cup 0 0; printf "%s" "$TL"; printf "%0.s$H" $(seq 1 $((cols-2))); printf "%s" "$TR"
  for ((r=1; r<rows-1; r++)); do
    tput cup $r 0;  printf "%s" "$V"
    tput cup $r $((cols-1)); printf "%s" "$V"
  done
  tput cup $((rows-1)) 0; printf "%s" "$BL"; printf "%0.s$H" $(seq 1 $((cols-2))); printf "%s" "$BR"
}
hr_at(){ local row="$1"; tput cup $((OY+row)) $((OX-2)); printf "%0.s$H" $(seq 1 $(( $(tput cols) - 2 ))); }

cleanup(){ tput sgr0; tput cnorm; tput clear; tput cup 0 0; }
trap cleanup EXIT INT TERM
tput civis
draw_box

# Header & labels
goto 0 1; printf " %b● Midnight Node Monitor%b  (%s %s  %s)" "$CD$B" "$N" "$(node_name || echo Midnight)" "$(node_version || echo ?)" "$(node_role || echo ?)"
hr_at 1
goto 2 0;  printf "%bUptime:%b "     "$C1$B" "$N"
goto 3 0;  printf "%bStart Time:%b " "$C1$B" "$N"
hr_at 4
goto 5 0;  printf "%bNode Key:%b "   "$C4$B" "$N"
goto 6 0;  printf "%bRPC Port:%b "   "$C4$B" "$N"
hr_at 7
goto 8 0;  printf "%bKeys:%b" "$B" "$N"
goto 9 2;  printf "aura_pub_key     : "
goto 10 2; printf "sidechain_pub_key: "
goto 11 2; printf "grandpa_pub_key  : "
hr_at 12
goto 13 0; printf "Historic Blocks : "
goto 14 0; printf "Blocks Authored : "

goto 16 0; printf "Epoch (main/side): "
hr_at 17
goto 18 0; printf "Latest Block    : "
goto 19 0; printf "Finalized Block : "
goto 20 0; printf "Sync            : "
goto 21 0; printf "Peers           : "
hr_at 22
goto 23 0; printf "CPU  : "
goto 24 0; printf "MEM  : "
goto 25 0; printf "Disk : "
hr_at 26
goto 27 0; printf "%s[q] Quit%s" "$G" "$N"

STARTED_AT="$(container_started_at)"
HISTORIC_BASE=""
discover_keys   # initial try

i=0
AUTH="$(blocks_authored 2>/dev/null || true)"   # initial value so we can print before first prom tick
PEER="$(node_peer_id 2>/dev/null || true)"  
LAST_RES_TS=0   # 0 = force a first update immediately; set to $(date +%s) to delay 60s


while true; do
  # tick (or keypress)
  read -rsn1 -t "$REFRESH_SEC" key || true
  [[ "${key:-}" == "q" ]] && break

  # counters → gates
  ((++i))
  do_heavy=$(( i % HEAVY_EVERY == 0 ))
  do_prom=$(( i % PROM_EVERY == 0 ))

  # === UPTIME: always update every tick ===
  if [[ -n "${STARTED_AT:-}" ]]; then
    SEC_START=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s); UP=$(( NOW - SEC_START ))
    d=$((UP/86400)); h=$(( (UP%86400)/3600 )); m=$(( (UP%3600)/60 )); s=$((UP%60))
    goto 2 9;  printf "%-30s" "$(printf "%s%dd %02d:%02d:%02d%s" "$B" "$d" "$h" "$m" "$s" "$N")"
    goto 3 12; printf "%-30s" "$(date -d "@$SEC_START" "+%F %T" 2>/dev/null || echo "$STARTED_AT")"
  else
    goto 2 9;  printf "%-30s" "n/a"
    goto 3 12; printf "%-30s" "n/a"
  fi

  # === PROMETHEUS: update Blocks Authored less often ===
  if (( do_prom )); then
    AUTH="$(blocks_authored 2>/dev/null || true)"
    goto 14 18; printf "%-12s" "${AUTH:-n/a}"
  fi

  # === HEAVY RPC: update the rest less often ===
  if (( do_heavy )); then
    # Identity (cached but refreshable)
    PEER="$(node_peer_id 2>/dev/null || echo "${PEER:-}")"
    goto 5 10; printf "%-40s" "$(shorten "${PEER:-?}" 32)"
    goto 6 10; printf "%-10s" "$RPC_PORT"

    # Keys (refresh if missing; may use RPC)
    if [[ -z "${SIDE_KEY:-}" || -z "${AURA_KEY:-}" || -z "${GRANDPA_KEY:-}" ]]; then
      discover_keys
    fi

    # Status: Active (committee or authored>0) > Registered > Candidate
    STATUS=""
    # helper: int?
    is_int(){ [[ "$1" =~ ^[0-9]+$ ]]; }
    if [[ -n "${SIDE_KEY:-}" ]]; then
      if [[ "$(in_committee_current "$SIDE_KEY")" == "yes" ]] || ( is_int "${AUTH:-0}" && (( AUTH > 0 )) ); then
        STATUS="Active"
      elif [[ "$(reg_status_registered "$SIDE_KEY")" == "Registered" ]]; then
        STATUS="Registered"
      elif [[ "$(reg_status_candidate "$SIDE_KEY")" == "Candidate" ]]; then
        STATUS="Candidate"
      fi
    fi

    side_line="${SIDE_KEY:-n/a}"
    case "$STATUS" in
      Active)     side_line="$side_line  ${C2}[★ Active]${N}" ;;
      Registered) side_line="$side_line  ${C2}[✓ Registered]${N}" ;;
      Candidate)  side_line="$side_line  ${C3}[⟳ Candidate]${N}" ;;
    esac

    goto 9  22; printf "%-64s" "${AURA_KEY:-n/a}"
    goto 10 22; printf "%-64s" "$(printf "%b" "$side_line")"
    goto 11 22; printf "%-64s" "${GRANDPA_KEY:-n/a}"

    # Epochs
    EM="$(epoch_main)"; ES="$(epoch_side)"
    goto 16 21; printf "%-20s" "${EM:-?}/${ES:-?}"

    # Blocks & sync
    BLOC="$(best_block_local)"; FLOC="$(finalized_block_local)"; BPUB="$(best_block_public)"
    if [[ -z "${HISTORIC_BASE:-}" && "${FLOC:-}" =~ ^[0-9]+$ ]]; then HISTORIC_BASE="$FLOC"; fi
    HISTORIC=$(( ${FLOC:-0} - ${HISTORIC_BASE:-0} ))
    goto 13 18; printf "%-12s" "$HISTORIC"
    goto 18 19; printf "%-12s" "${BLOC:-?}"
    goto 19 19; printf "%-12s" "${FLOC:-?}"

    SYNC="n/a"
    if [[ "${BLOC:-}" =~ ^[0-9]+$ && "${BPUB:-}" =~ ^[0-9]+$ && "$BPUB" -gt 0 ]]; then
      if have bc; then SYNC="$(echo "scale=2; 100 * $BLOC / $BPUB" | bc)%"
      else SYNC="$(( 100 * BLOC / BPUB ))%"; fi
    fi
    goto 20 19; printf "%-10s" "$SYNC"

    # Peers
    PEERS="$(rpc "$LOCAL_RPC" system_health | rval '.result.peers')"
    goto 21 19; printf "%-6s" "${PEERS:-0}"
  fi

  # === RESOURCES: every RES_EVERY_SEC seconds ===
  # Use NOW from the uptime section when available, otherwise compute now.
  _now_res="${NOW:-$(date +%s)}"
  if (( _now_res - LAST_RES_TS >= RES_EVERY_SEC )); then
    STATS="$(container_stats)"; CPU="n/a"; MEM="n/a"
    if [[ -n "$STATS" ]]; then IFS='|' read -r CPU MEM MEMP <<<"$STATS"; fi
    goto 23 7;  printf "%-12s" "$CPU"
    goto 24 7;  printf "%-22s" "$MEM"

    MP="$(node_volume_mountpoint)"; DBSZ="$(db_size_h)"
    if [[ -n "$MP" && -d "$MP" ]]; then
      read -r FS SZ USED AVAIL USEP MNT <<<"$(df -h "$MP" | awk 'NR==2{print $1,$2,$3,$4,$5,$6}')"
      goto 25 7; printf "%-60s" "${USEP:-?} of ${SZ:-?} (free ${AVAIL:-?})  |  DB: ${DBSZ}"
    else
      goto 25 7; printf "%-60s" "DB: ${DBSZ}"
    fi
    LAST_RES_TS="$_now_res"
  fi

done

