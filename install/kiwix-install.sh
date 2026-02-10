#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# DEPENDENCIES
# =============================================================================
# Kiwix-tools binaries are statically compiled and have minimal dependencies.
# Only libharfbuzz0b and fontconfig are needed for rendering.

msg_info "Installing Dependencies"
$STD apt-get install -y \
  libharfbuzz0b \
  fontconfig
msg_ok "Installed Dependencies"

# =============================================================================
# DOWNLOAD & DEPLOY APPLICATION
# =============================================================================
# Kiwix distributes pre-built binaries for Linux x86_64 and aarch64.
# We'll download from GitHub releases and install to /usr/local/bin.

msg_info "Downloading Kiwix-Tools"
fetch_and_deploy_gh_release "kiwix" "kiwix/kiwix-tools" "prebuild" "latest" "/tmp" "kiwix-tools_linux-x86_64-*.tar.gz"
msg_ok "Downloaded Kiwix-Tools"

msg_info "Installing Kiwix Binaries"
cd /tmp/kiwix-tools_linux-*
cp kiwix-* /usr/local/bin/
chmod +x /usr/local/bin/kiwix-*
cd /tmp
rm -rf kiwix-tools_linux-*
msg_ok "Installed Kiwix Binaries"

# =============================================================================
# CREATE SYSTEMD SERVICE
# =============================================================================
# The service will serve all .zim files from /data (bind-mounted from host).
# Port 8080 is used by default.

msg_info "Creating Kiwix Service"
cat <<'EOF' >/etc/systemd/system/kiwix-serve.service
[Unit]
Description=Kiwix ZIM Server
After=network.target

[Service]
Type=simple
# Use shell expansion to serve all .zim files in /data
ExecStart=/bin/sh -c 'exec /usr/local/bin/kiwix-serve --port 8080 /data/*.zim'
Restart=always
RestartSec=10
Nice=15

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now kiwix-serve
msg_ok "Created Kiwix Service"

# =============================================================================
# CLEANUP & FINALIZATION
# =============================================================================

motd_ssh
customize
cleanup_lxc
