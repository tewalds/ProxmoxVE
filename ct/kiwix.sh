#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

# ============================================================================
# APP CONFIGURATION
# ============================================================================
# These values are sent to build.func and define default container resources.
# Users can customize these during installation via the interactive prompts.
# ============================================================================

export LC_ALL=C  # Disable Perl locale warnings.
export DEBIAN_FRONTEND=noninteractive
export DISABLE_LOCALE="y"

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"  # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-1}"                        # CPU cores: 1-4 typical
var_ram="${var_ram:-512}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-4}"                      # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                     # OS: debian, ubuntu, alpine
var_version="${var_version:-12}"               # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"      # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

# ============================================================================
# INITIALIZATION
# ============================================================================
header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

# ============================================================================
# UPDATE SCRIPT
# ============================================================================

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Step 1: Verify installation exists
  if [[ ! -f /usr/local/bin/kiwix-serve ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Step 2: Check if update is available
  if check_for_gh_release "kiwix" "kiwix/kiwix-tools"; then

    # Step 3: Stop services before update
    msg_info "Stopping Service"
    systemctl stop kiwix-serve
    msg_ok "Stopped Service"

    # Step 4: No data backup needed for Kiwix (ZIM files are external)

    # Step 5: Download and deploy new version
    fetch_and_deploy_gh_release "kiwix" "kiwix/kiwix-tools" "prebuild" "latest" "/tmp" "kiwix-tools_linux-x86_64-*.tar.gz"

    # Step 6: Install the new binaries
    msg_info "Installing Updated Binaries"
    cd /tmp/kiwix-tools_linux-*
    cp kiwix-* /usr/local/bin/
    chmod +x /usr/local/bin/kiwix-*
    cd /tmp
    rm -rf kiwix-tools_linux-*
    msg_ok "Installed Updated Binaries"

    # Step 7: No data restore needed

    # Step 8: Restart service with new version
    msg_info "Starting Service"
    systemctl start kiwix-serve
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# ============================================================================
# MAIN EXECUTION - Container creation flow
# ============================================================================
# These are called by build.func and handle the full installation process:
#   1. start              - Initialize container creation
#   2. build_container    - Execute the install script inside container
#   3. description        - Display completion info and access details
# ============================================================================

start
build_container

# ============================================================================
# POST-CREATION: ZIM DIRECTORY CONFIGURATION
# ============================================================================

echo -e "\n${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${BL}  ${APP} ZIM Archive Configuration${CL}"
echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
echo -e "${YW}Kiwix requires a directory containing ZIM archive files.${CL}"
echo -e "${YW}This directory will be bind-mounted to ${BGN}/data${CL}${YW} in the container.${CL}\n"
echo -e "${GN}Download ZIM archives from:${CL}"
echo -e "  ${GN}• https://library.kiwix.org${CL}"
echo -e "  ${GN}• https://download.kiwix.org/zim/${CL}\n"

# Allow environment variable override (for automation)
if [ -z "${ZIM_DIR:-}" ]; then
  while true; do
    read -p "Enter the full path to your ZIM archives directory: " ZIM_DIR

    # Trim whitespace
    ZIM_DIR=$(echo "$ZIM_DIR" | xargs)

    if [ -z "$ZIM_DIR" ]; then
      echo -e "${RD}[!] Path cannot be empty.${CL}\n"
      continue
    fi

    if [ ! -d "$ZIM_DIR" ]; then
      echo -e "${RD}[!] Error: Directory '$ZIM_DIR' does not exist.${CL}"
      read -p "Try again? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        msg_error "ZIM directory required for Kiwix"
        exit 1
      fi
      continue
    fi

    # Check for .zim files (warning only, not blocking)
    if ! ls "${ZIM_DIR}"/*.zim >/dev/null 2>&1; then
      echo -e "\n${YW}[!] Warning: No .zim files found in '$ZIM_DIR'${CL}"
      echo -e "${YW}    Kiwix will not serve any content until you add .zim files.${CL}"
      echo -e "${YW}    You can add them later and restart the service.${CL}\n"
      read -p "Continue with this directory? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        continue
      fi
    fi

    echo -e "\n${GN}[✓] Using directory: ${ZIM_DIR}${CL}\n"
    break
  done
else
  echo -e "${GN}[✓] Using ZIM_DIR from environment: ${ZIM_DIR}${CL}\n"
fi

# ============================================================================
# CONFIGURE BIND MOUNT
# ============================================================================

msg_info "Configuring Bind Mount to ${ZIM_DIR}"
# Note: ro=1 is omitted as it can cause 'Status 9' mount errors
# on certain Btrfs/ZFS configurations with unprivileged containers.
pct set $CTID -mp0 "$ZIM_DIR,mp=/data"
msg_ok "Directory ${ZIM_DIR} mounted to /data"

msg_info "Setting Container Options"
pct set $CTID -cpuunits 512
pct set $CTID --onboot 1
msg_ok "Container Options Set"

# ============================================================================
# COMPLETION
# ============================================================================

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

msg_ok "Completed successfully!\n"
echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${GN}  ${APP} Setup Complete!${CL}"
echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
echo -e "${TAB}${GATEWAY}${BGN}Web Interface:${CL} ${BL}http://${IP}:8080${CL}"
echo -e "${TAB}${INFO}${BGN}Container ID:${CL} ${GN}${CTID}${CL}"
echo -e "${TAB}${INFO}${BGN}ZIM Directory:${CL} ${ZIM_DIR} ${DGN}→${CL} ${BGN}/data${CL}"
echo -e "\n${TAB}${CY}To add more .zim files:${CL}"
echo -e "${TAB}  1. Copy them to ${YW}${ZIM_DIR}${CL}"
echo -e "${TAB}  2. Restart service: ${YW}pct exec ${CTID} -- systemctl restart kiwix-serve${CL}\n"
