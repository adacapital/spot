#!/bin/bash

set -euo pipefail

# Ensure required native dependencies are installed
sudo apt-get update
sudo apt-get install -y protobuf-compiler pkg-config libssl-dev clang build-essential


# Configurable build directory
BUILD_DIR="/home/cardano/data/download/subkey-build"

echo "📦 Installing Rust (pinned to version 1.70.0 for Substrate compatibility)..."
if ! command -v rustup &> /dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
else
  echo "✅ rustup already installed"
fi

# Ensure correct Rust version for Substrate
rustup install 1.70.0
rustup override set 1.70.0
echo "✅ Using Rust version: $(rustc --version)"

# Clean build directory if exists
if [ -d "$BUILD_DIR" ]; then
  echo "🧹 Cleaning up existing build directory at $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "📥 Cloning Substrate repository into $BUILD_DIR"
git clone --depth=1 https://github.com/paritytech/substrate.git
cd substrate

echo "🛠️ Building only 'subkey' binary..."
cargo build --release --package subkey

echo "📤 Installing subkey to ~/.cargo/bin"
cp target/release/subkey ~/.cargo/bin/subkey

# Optional: verify binary
if [ -x ~/.cargo/bin/subkey ]; then
  echo "✅ 'subkey' successfully installed at: $(which subkey)"
else
  echo "❌ 'subkey' build or copy failed"
  exit 1
fi

echo "🧽 Cleaning up build directory..."
cd ~
# rm -rf "$BUILD_DIR"

echo "✅ All done!"
