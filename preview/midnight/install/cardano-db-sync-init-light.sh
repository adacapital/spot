#!/bin/bash
# this is to install cardano-db-sync without building it from source but getting it pre-built from another box
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT_DIR2="$(realpath "$(dirname "$PARENT_DIR")")"
PARENT_DIR3="$(realpath "$(dirname "$PARENT_DIR2")")"
BASE_DIR="$(realpath "$(dirname "$PARENT_DIR3")")"
SPOT_DIR=$PARENT_DIR2
UTILS_PATH="$SPOT_DIR/scripts"
CONF_PATH="$SCRIPT_DIR/config"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "BASE_DIR: $BASE_DIR"
echo "PARENT_DIR: $PARENT_DIR"
echo "PARENT_DIR2: $PARENT_DIR2"
echo "PARENT_DIR3: $PARENT_DIR3"
echo "SPOT_DIR: $SPOT_DIR"
echo "UTILS_PATH: $UTILS_PATH"
echo "CONF_PATH: $CONF_PATH"
echo

# exit 1

# importing utility functions
source $UTILS_PATH/utils.sh

echo "CARDANO-DB-SYNC-INIT-LIGHT STARTING..."

echo '---------------- secp256k1 dependency ----------------'
ISSECP256K1=$(ldconfig -p | grep secp256k1 | wc -l)

if [[ $ISSECP256K1 -eq 0 ]];then
    echo "secp256k1 lib not found, installing..."
    mkdir -p ~/download
    cd ~/download
    git clone https://github.com/bitcoin-core/secp256k1.git
    cd secp256k1
    git checkout acf5c55
    ./autogen.sh
    ./configure --enable-module-schnorrsig --enable-experimental
    make
    make check
    sudo make install
else
    echo "secp256k1 lib found, no installation required."
fi

echo '---------------- libblst dependency ----------------'
ISLIBBLST=$(ldconfig -p | grep libblst | wc -l)

if [[ $ISLIBBLST -eq 0 ]];then
    echo "libblst lib not found, installing..."
    mkdir -p ~/download
    cd ~/download
    git clone https://github.com/supranational/blst
    cd blst
    git checkout 3dd0f80
    ./build.sh

    cat > libblst.pc << EOF
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libblst
Description: Multilingual BLS12-381 signature library
URL: https://github.com/supranational/blst
Version: 0.3.10
Cflags: -I\${includedir}
Libs: -L\${libdir} -lblst
EOF

    sudo cp libblst.pc /usr/local/lib/pkgconfig/
    sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp  /usr/local/include/
    sudo cp libblst.a /usr/local/lib
    sudo chmod 644 \
        /usr/local/lib/libblst.* \
        /usr/local/include/{blst.*,blst_aux.h}
else
    echo "secp256k1 lib found, no installation required."
fi

echo
echo '---------------- NOT Building cardano-db-sync with cabal :) ----------------'
INSTALL_PATH=$BASE_DIR
INSTALL_PATH=$(prompt_input_default INSTALL_PATH $INSTALL_PATH)

PGPASS_PATH=$CONF_PATH/pgpass-cardanobi-preview
PGPASS_PATH=$(prompt_input_default PGPASS_PATH $PGPASS_PATH)

LATESTTAG=$(curl -s https://api.github.com/repos/IntersectMBO/cardano-db-sync/releases/latest | jq -r .tag_name)
LATESTTAG=$(prompt_input_default CHECKOUT_TAG $LATESTTAG)

echo
echo "Details of your cardano-db-sync build:"
echo "INSTALL_PATH: $INSTALL_PATH"
echo "PGPASS_PATH: $PGPASS_PATH"
echo "LATESTTAG: $LATESTTAG"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
echo "Getting the source code.."
mkdir -p $INSTALL_PATH
cd $INSTALL_PATH
git clone https://github.com/IntersectMBO/cardano-db-sync
cd cardano-db-sync

echo
echo "Creating the DB..."
PGPASSFILE=$PGPASS_PATH scripts/postgresql-setup.sh --createdb

git fetch --all --tags
# git checkout "tags/$LATESTTAG"
git checkout tags/$LATESTTAG

# echo "with-compiler: ghc-8.10.7" >> cabal.project.local
echo "with-compiler: ghc-9.6.3" >> cabal.project.local

echo
git describe --tags

echo
if ! promptyn "At this point you will move the binary from another box? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
sudo apt install pkg-config libpq-dev

#Moving schema migration files to our work directory
mkdir -p $INSTALL_PATH/cardanobi-db-sync
cp $INSTALL_PATH/cardano-db-sync/schema/*  $INSTALL_PATH/cardanobi-db-sync/schema

#Config files setup
cd $INSTALL_PATH/cardanobi-db-sync
mkdir -p configs
cd configs
mkdir -p preview
curl --remote-name-all --output-dir preview \
    https://book.world.dev.cardano.org/environments/preview/config.json \
    https://book.world.dev.cardano.org/environments/preview/db-sync-config.json \
    https://book.world.dev.cardano.org/environments/preview/submit-api-config.json \
    https://book.world.dev.cardano.org/environments/preview/topology.json \
    https://book.world.dev.cardano.org/environments/preview/byron-genesis.json \
    https://book.world.dev.cardano.org/environments/preview/shelley-genesis.json \
    https://book.world.dev.cardano.org/environments/preview/alonzo-genesis.json \
    https://book.world.dev.cardano.org/environments/preview/conway-genesis.json

#todo - replace NodeConfigFile with correct value in db-sync-config.json