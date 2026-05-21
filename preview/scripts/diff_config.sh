#!/bin/bash
# Fetch IOG canonical preview config.json + diff against local BP and relay configs
# Run from /data or anywhere — outputs to /tmp/iog-preview-<timestamp>/

NOW=$(date +%Y%m%d_%H%M%S)
IOG_CONFIG_URL="https://book.play.dev.cardano.org/environments/preview/config.json"
TMP_DIR="/tmp/iog-preview-${NOW}"
mkdir -p "$TMP_DIR"

# 1. Download canonical IOG config
echo "=== Downloading IOG canonical config.json ==="
curl -s -o "$TMP_DIR/config.json" "$IOG_CONFIG_URL"
if [[ ! -s "$TMP_DIR/config.json" ]] || ! jq empty "$TMP_DIR/config.json" 2>/dev/null; then
    echo "✗ Download failed or invalid JSON. Aborting."
    exit 1
fi
echo "Saved to: $TMP_DIR/config.json ($(stat -c %s "$TMP_DIR/config.json") bytes)"
echo

# 2. Top-level keys comparison (what fields IOG has vs what you have)
for ROLE in bp relay; do
    LOCAL="/data/node.$ROLE/config/config.json"
    echo "=== Top-level key comparison: IOG vs $LOCAL ==="
    if [[ ! -f "$LOCAL" ]]; then
        echo "  (file not found, skipping)"
        continue
    fi
    echo "  Keys IOG has that you DON'T:"
    comm -23 <(jq -r 'keys[]' "$TMP_DIR/config.json" | sort) <(jq -r 'keys[]' "$LOCAL" | sort) | sed 's/^/    + /'
    echo "  Keys you have that IOG DOESN'T:"
    comm -13 <(jq -r 'keys[]' "$TMP_DIR/config.json" | sort) <(jq -r 'keys[]' "$LOCAL" | sort) | sed 's/^/    - /'
    echo
done

# 3. Genesis filename heads-up
echo "=== Genesis file references — DO NOT blindly overwrite these ==="
echo "IOG canonical uses:"
jq '{ByronGenesisFile, ShelleyGenesisFile, AlonzoGenesisFile, ConwayGenesisFile}' "$TMP_DIR/config.json"
echo "Your local uses the shortened forms (bgenesis.json, sgenesis.json, etc.) — keep yours,"
echo "OR rename your genesis files to match IOG defaults. Whichever you pick, the HASH must match."
echo

# 4. Full unified diffs (left = IOG canonical, right = your local)
for ROLE in bp relay; do
    LOCAL="/data/node.$ROLE/config/config.json"
    [[ ! -f "$LOCAL" ]] && continue
    DIFF_FILE="$TMP_DIR/diff-$ROLE.txt"
    echo "=== Full unified diff written to: $DIFF_FILE ==="
    diff -u "$TMP_DIR/config.json" "$LOCAL" > "$DIFF_FILE"
    wc -l "$DIFF_FILE"
done

echo
echo "Next steps:"
echo "  1. Review the structural diffs above (added/missing fields per role)"
echo "  2. Cat or open the full diff files for line-by-line review:"
echo "       cat $TMP_DIR/diff-bp.txt"
echo "       cat $TMP_DIR/diff-relay.txt"
echo "  3. Manually merge IOG changes forward in /data/node.bp/config/config.json"
echo "     and /data/node.relay/config/config.json, KEEPING your local customizations:"
echo "       - Shortened genesis filenames (bgenesis.json etc.)"
echo "       - Anything you may have tuned (specific socket paths, ports, etc.)"
echo "  4. After editing, validate with: jq empty /data/node.bp/config/config.json"
echo "  5. Backup your originals before saving:"
echo "       cp -p /data/node.bp/config/config.json /data/node.bp/config/config.json.${NOW}.bak"
echo "       cp -p /data/node.relay/config/config.json /data/node.relay/config/config.json.${NOW}.bak"
