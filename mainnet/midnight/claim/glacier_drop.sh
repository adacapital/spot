#!/usr/bin/env bash
# midnight-claim-cli.sh
#
# One-stop helper to sign a Midnight Glacier/Scavenger claim challenge with your Cardano **stake key**
# using `cardano-cli v10+`, verify the signature, and emit base64/hex plus a ready JSON payload to paste.
#
# USAGE
#   ./midnight-claim-cli.sh \
#     --stake-skey ./keys/stake.skey \
#     --stake-vkey ./keys/stake.vkey \
#     --origin-addr ./paymentwithstake.addr \
#     --challenge ./challenge.json \
#     --out ./out
#
# NOTES
# * Do **NOT** put your .skey files into a public repo. Keep them offline.
# * The script never transmits anything. It only reads files and writes outputs locally.
# * Works with Conway-era subcommands; falls back to legacy if needed.
# * For portals that want a single JSON POST, a `claim-submit.json` is generated for convenience.
#
# OUTPUTS (in --out):
#   signature.cbor     - raw signature
#   signature.b64      - base64 of signature (common portal format)
#   signature.hex      - hex of signature (sometimes requested)
#   derived.stake.hash - stake key hash (sanity check)
#   claim-submit.json  - convenience JSON bundle you can open/copy
#

set -euo pipefail

# ---------- helpers ----------
err()  { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO]  $*"; }

CLI=${CARDANO_CLI:-cardano-cli}

have() { command -v "$1" >/dev/null 2>&1; }

need_tools() {
  have "$CLI" || err "cardano-cli not found in PATH (or set CARDANO_CLI)."
  have jq      || err "jq is required."
  have base64  || err "base64 is required."
  have xxd     || info "xxd not found; hex output will be skipped."
}

cli_has_conway() {
  "$CLI" conway --help >/dev/null 2>&1
}

# ---------- args ----------
STAKE_SKEY=""
STAKE_VKEY=""
ORIGIN_ADDR_FILE_OR_STR=""
CHALLENGE_JSON=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stake-skey) STAKE_SKEY=${2:-}; shift 2;;
    --stake-vkey) STAKE_VKEY=${2:-}; shift 2;;
    --origin-addr) ORIGIN_ADDR_FILE_OR_STR=${2:-}; shift 2;;
    --challenge) CHALLENGE_JSON=${2:-}; shift 2;;
    --out) OUTDIR=${2:-}; shift 2;;
    -h|--help) sed -n '1,80p' "$0"; exit 0;;
    *) err "Unknown arg: $1";;
  esac
done

[[ -n "$STAKE_SKEY" && -f "$STAKE_SKEY" ]] || err "--stake-skey file missing"
[[ -n "$STAKE_VKEY" && -f "$STAKE_VKEY" ]] || err "--stake-vkey file missing"
[[ -n "$CHALLENGE_JSON" && -f "$CHALLENGE_JSON" ]] || err "--challenge file missing"
[[ -n "$OUTDIR" ]] || err "--out directory not provided"
mkdir -p "$OUTDIR"

need_tools

# Origin address can be a file or a literal
if [[ -f "$ORIGIN_ADDR_FILE_OR_STR" ]]; then
  ORIGIN_ADDR=$(<"$ORIGIN_ADDR_FILE_OR_STR")
else
  ORIGIN_ADDR="$ORIGIN_ADDR_FILE_OR_STR"
fi
[[ -n "$ORIGIN_ADDR" ]] || err "--origin-addr is empty"

# ---------- sanity checks ----------
info "Deriving stake key hash from vkey..."
if cli_has_conway; then
  "$CLI" conway stake-address key-hash \
    --stake-verification-key-file "$STAKE_VKEY" \
    > "$OUTDIR/derived.stake.hash"
else
  "$CLI" stake-address key-hash \
    --stake-verification-key-file "$STAKE_VKEY" \
    > "$OUTDIR/derived.stake.hash"
fi

STAKE_HASH=$(<"$OUTDIR/derived.stake.hash")
info "Stake key hash: $STAKE_HASH"

# Optional: confirm challenge stake hash matches
if jq -e '.stake_key_hash' "$CHALLENGE_JSON" >/dev/null 2>&1; then
  CH_STAKE_HASH=$(jq -r '.stake_key_hash' "$CHALLENGE_JSON")
  if [[ "$CH_STAKE_HASH" != "null" && -n "$CH_STAKE_HASH" ]]; then
    [[ "$CH_STAKE_HASH" == "$STAKE_HASH" ]] || err "Challenge stake_key_hash ($CH_STAKE_HASH) != derived ($STAKE_HASH)"
    info "Challenge stake_key_hash matches derived stake hash."
  fi
fi

# Optional: confirm origin address matches
if jq -e '.origin_address' "$CHALLENGE_JSON" >/dev/null 2>&1; then
  CH_ORIGIN=$(jq -r '.origin_address' "$CHALLENGE_JSON")
  if [[ "$CH_ORIGIN" != "null" && -n "$CH_ORIGIN" ]]; then
    [[ "$CH_ORIGIN" == "$ORIGIN_ADDR" ]] || info "Note: challenge origin_address differs from provided --origin-addr"
  fi
fi

# ---------- sign ----------
info "Signing challenge with stake.skey..."
SIG_CBOR="$OUTDIR/signature.cbor"
if cli_has_conway; then
  "$CLI" conway key sign-message \
    --signing-key-file "$STAKE_SKEY" \
    --message-file "$CHALLENGE_JSON" \
    --out-file "$SIG_CBOR"
else
  "$CLI" key sign-message \
    --signing-key-file "$STAKE_SKEY" \
    --message-file "$CHALLENGE_JSON" \
    --out-file "$SIG_CBOR"
fi
info "Signature written: $SIG_CBOR"

# ---------- verify ----------
info "Verifying signature with stake.vkey..."
if cli_has_conway; then
  "$CLI" conway key verify-message \
    --verification-key-file "$STAKE_VKEY" \
    --message-file "$CHALLENGE_JSON" \
    --signature-file "$SIG_CBOR" >/dev/null
else
  "$CLI" key verify-message \
    --verification-key-file "$STAKE_VKEY" \
    --message-file "$CHALLENGE_JSON" \
    --signature-file "$SIG_CBOR" >/dev/null
fi
info "Signature verified OK."

# ---------- encodings ----------
info "Encoding signature to base64/hex..."
base64 -w0 "$SIG_CBOR" > "$OUTDIR/signature.b64"
if have xxd; then
  xxd -p -c 1000 "$SIG_CBOR" | tr -d '\n' > "$OUTDIR/signature.hex"
else
  info "Skipping hex output (xxd not present)."
fi

# ---------- bundle JSON ----------
info "Building convenience bundle JSON..."
CHALLENGE_CANON=$(jq -c '.' "$CHALLENGE_JSON")
SIG_B64=$(<"$OUTDIR/signature.b64")

cat > "$OUTDIR/claim-submit.json" <<JSON
{
  "origin_address": "${ORIGIN_ADDR}",
  "stake_key_hash": "${STAKE_HASH}",
  "challenge": ${CHALLENGE_CANON},
  "signature_b64": "${SIG_B64}"
}
JSON

info "Done. Files in: $OUTDIR"
ls -l "$OUTDIR"

cat <<'NEXT'

Next steps:
  1) Open the claim portal and select/paste the fields it requests.
     - Origin Address: use your payment-with-stake base address (NOT stake.addr).
     - Challenge JSON: paste as provided by portal (we saved a canonical copy).
     - Signature: use signature.b64 (unless the portal explicitly asks for hex).
  2) Save the portal's acceptance/claim ID and screenshot it.
  3) Keep these artifacts for later tranches (thaw/redemption).

Security tips:
  - Never upload .skey files anywhere.
  - Consider running this on an offline machine and sneaker-net the signature back.
  - If using a HW wallet, prefer the portal's native HW sign flow instead of .skey.

Troubleshooting:
  - If you see a mismatch on stake_key_hash, confirm you're using the correct stake.vkey.
  - If the portal rejects the signature, ensure you didn't edit challenge.json.
  - If your CLI lacks 'conway' subcommands, the legacy fallbacks in this script should work.

NEXT
