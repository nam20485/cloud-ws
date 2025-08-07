#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Argument 1: NICE DCV Download URL
DCV_URL=$1

echo "--- Starting NICE DCV Setup ---"

# Download and extract
wget -q -O /tmp/nice-dcv.tgz "$DCV_URL"
tar -xzf /tmp/nice-dcv.tgz -C /tmp
cd /tmp/nice-dcv-*/

# Install all .deb packages non-interactively
export DEBIAN_FRONTEND=noninteractive
apt-get install -y ./nice-*.deb

# Configure DCV for console capture
echo "Configuring NICE DCV for console session..."
cat << EOF > /etc/dcv/dcv.conf
[license]
[log]
[session-management]
create-session = true
[session-management/defaults]
[session-management/automatic-console-session]
[display]
owner = "root"
EOF

# Set a default password for the root user (CHANGE THIS IN A PRODUCTION ENVIRONMENT)
echo "root:YourSecurePassword" | chpasswd
echo "Set root password. PLEASE CHANGE THIS!"

# Enable and restart the DCV service
systemctl enable --now dcvserver
systemctl restart dcvserver

echo "--- NICE DCV Setup Complete ---"
