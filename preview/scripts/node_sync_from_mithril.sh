# 1. Install mithril-client (just the binary; we don't need the full Mithril stack)
cd /tmp
wget https://github.com/input-output-hk/mithril/releases/download/2617.0/mithril-2617.0-linux-x64.tar.gz
tar xf mithril-2617.0-linux-x64.tar.gz
sudo cp mithril-client /usr/local/bin/
mithril-client --version    # should print 0.x.y

# 2. Configure for preview
export AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
export GENESIS_VERIFICATION_KEY=$(curl -s https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey)

# 3. See what snapshots are available (just to inspect — pick the latest digest)
mithril-client cardano-db snapshot list | head -20

# 4. Stop services, move bad DBs aside
sudo systemctl stop run.bp run.relay
NOW=$(date +%Y%m%d_%H%M%S)
sudo mv /data/node.bp/db    /data/node.bp/db.fork-${NOW}.bak
sudo mv /data/node.relay/db /data/node.relay/db.fork-${NOW}.bak

# 5. Download Mithril snapshot into the relay's directory
#    (uses "latest" alias — picks the most recent signed snapshot)
cd /data/node.relay
sudo -E mithril-client cardano-db download latest --download-dir /data/node.relay
# Note: -E preserves the AGGREGATOR_ENDPOINT/GENESIS_VERIFICATION_KEY env vars under sudo
# The snapshot extracts to /data/node.relay/db/ — verify:
sudo ls -la /data/node.relay/db/ | head
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
