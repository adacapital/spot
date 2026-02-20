# --- PREVIEW | verify which keys built the funded base address ---
# (safe to paste; this writes only vkeys/addresses to /tmp)

set -euo pipefail

# 0) Put your known funded address here (from explorer)
FUNDED_ADDR="addr_test1qr6e5xmxlehl74xg5ujgte0jn2lfkc4n6fw7ukgc2y4z2a7rltve9ryn8zyvydc62zd4p0nrpedpgj6ggsfdna8xrd3qzv3qqc"

# 1) Derive verification keys from your signing keys
cardano-cli key verification-key \
  --signing-key-file ./preview/keys/payment.skey \
  --verification-key-file /tmp/preview_payment.vkey

cardano-cli key verification-key \
  --signing-key-file ./preview/keys/stake.skey \
  --verification-key-file /tmp/preview_stake.vkey

# 2) Build the BASE (payment+stake) address on PREVIEW (magic=2)
cardano-cli address build \
  --payment-verification-key-file /tmp/preview_payment.vkey \
  --stake-verification-key-file   /tmp/preview_stake.vkey \
  --testnet-magic 2 > /tmp/preview_built.addr

echo "Known funded addr:"
echo "$FUNDED_ADDR"
echo "Addr built from your two vkeys:"
cat /tmp/preview_built.addr

# Quick match check
if grep -qxF "$FUNDED_ADDR" /tmp/preview_built.addr; then
  echo "✅ MATCH: your payment.skey + stake.skey build the funded address."
else
  echo "❌ DIFFERENT: these skeys do NOT build the funded address."
fi

# 3) (Optional) Build the ENTERPRISE (payment-only) address for comparison
cardano-cli address build \
  --payment-verification-key-file /tmp/preview_payment.vkey \
  --testnet-magic 2 \
  --enterprise-address > /tmp/preview_enterprise.addr

echo "Enterprise address (payment-only):"
cat /tmp/preview_enterprise.addr

# 4) (Optional) Show hashes to compare with explorer data if needed
echo "Payment key hash:"
cardano-cli address key-hash \
  --payment-verification-key-file /tmp/preview_payment.vkey

echo "Stake key hash:"
cardano-cli stake-address key-hash \
  --stake-verification-key-file /tmp/preview_stake.vkey

# 5) (Optional) Build the stake address (useful to compare with explorer)
cardano-cli stake-address build \
  --stake-verification-key-file /tmp/preview_stake.vkey \
  --testnet-magic 2 > /tmp/preview_stake.addr

echo "Stake address:"
cat /tmp/preview_stake.addr

# 6) (Optional) If they match and you want to save your base addr alongside your keys:
# cp /tmp/preview_built.addr ./preview/keys/paymentwithstake.addr---------------------