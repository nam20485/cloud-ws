#!/bin/bash
set -e

# Argument 1: Parsec Download URL
PARSEC_URL=$1

echo "--- Starting Parsec Setup ---"

wget -q -O /tmp/parsec.deb "$PARSEC_URL"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y /tmp/parsec.deb

echo "--- Parsec Installation Complete ---"
