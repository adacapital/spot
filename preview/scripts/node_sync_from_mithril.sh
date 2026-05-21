#!/bin/bash
# Bootstrap a Cardano preview node from a Mithril snapshot.
# Use this when you've been offline across a hard fork and your DB is on a
# stale chain that public peers can't reconcile (historicity cutoff).
#
# This script populates BOTH /data/node.relay/db and /data/node.bp/db from
# the latest Mithril snapshot (including ancillary ledger state for fast boot).
#
# Trust model: Mithril certificate verifies the immutable chain via stake-based
# threshold signatures. The "ancillary" ledger state files are signed by IOG
# keys (not the stake-based Mithril certificate). See:
#   https://mithril.network/doc/manual/getting-started/network-configurations

# 1. Install mithril-client (just the binary; we don't need the full Mithril stack)
cd /tmp
wget https://github.com/input-output-hk/mithril/releases/download/2617.0/mithril-2617.0-linux-x64.tar.gz
tar xf mithril-2617.0-linux-x64.tar.gz
sudo cp mithril-client /usr/local/bin/
mithril-client --version    # should print 0.x.y

# 2. Configure for preview (pre-release-preview is the mithril infra for preview testnet)
export AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
export GENESIS_VERIFICATION_KEY=$(curl -s https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey)
# ANCILLARY key is needed for --include-ancillary (fast boot — ships ledger state).
# Without it, cardano-node would have to replay every block from genesis on first start.
export ANCILLARY_VERIFICATION_KEY=$(curl -s https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/ancillary.vkey)

# 3. See what snapshots are available (just to inspect — pick the latest digest)
mithril-client cardano-db snapshot list | head -20

# 4. Stop services, move bad DBs aside
sudo systemctl stop run.bp run.relay
NOW=$(date +%Y%m%d_%H%M%S)
sudo mv /data/node.bp/db    /data/node.bp/db.fork-${NOW}.bak
sudo mv /data/node.relay/db /data/node.relay/db.fork-${NOW}.bak

# 5. Download Mithril snapshot into the relay's directory
#    --include-ancillary brings the ledger state too so the node doesn't replay from genesis.
#    Uses "latest" alias — picks the most recent signed snapshot.
cd /data/node.relay
sudo -E mithril-client cardano-db download latest \
    --download-dir /data/node.relay \
    --include-ancillary
# Note: -E preserves the AGGREGATOR_ENDPOINT/GENESIS_VERIFICATION_KEY/ANCILLARY_VERIFICATION_KEY env vars under sudo.
# The snapshot extracts to /data/node.relay/db/ — verify:
sudo ls -la /data/node.relay/db/
# Expect: immutable/ ledger/ volatile/  — ledger/ presence confirms ancillary was included
sudo du -sh /data/node.relay/db/{immutable,ledger,volatile} 2>/dev/null
sudo chown -R cardano:cardano /data/node.relay/db

# 6. Mirror the same snapshot to the BP (faster than running mithril-client twice)
sudo cp -a /data/node.relay/db /data/node.bp/db
sudo chown -R cardano:cardano /data/node.bp/db

# 7. Start services — relay first
sudo systemctl start run.relay
journalctl -u run.relay -f
# Watch for:
#   - "Replayed block: slot N out of M, Progress: 99.xx%" (replaying the snapshot)
#   - Then chain extension messages, NOT HistoricityError
# Ctrl-C when it's clearly climbing fresh blocks past the snapshot tip

# 8. Start BP
sudo systemctl start run.bp
journalctl -u run.bp -f
# Should sync to relay in a couple minutes (local connection)
