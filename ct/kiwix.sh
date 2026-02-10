#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: [YourGitHubUsername]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

# ============================================================================
# APP CONFIGURATION
# ============================================================================
# These values are sent to build.func and define default container resources.
# Users can customize these during installation via the interactive prompts.
# ============================================================================

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"  # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-1}"                        # CPU cores: 1-4 typical
var_ram="${var_ram:-512}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-4}"                      # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                     # OS: debian, ubuntu, alpine
var_version="${var_version:-12}"               # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"      # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

# ============================================================================
# INITIALIZATION - These are required in all CT scripts
# ============================================================================
header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

# ============================================================================
# UPDATE SCRIPT - Called when user selects "Update" from web interface
# ============================================================================
# This function is triggered by the web interface to update the application.
# It should:
#   1. Check if installation exists
#   2. Check for new GitHub releases
#   3. Stop running services
#   4. Backup critical data
#   5. Deploy new version
#   6. Run post-update commands (migrations, config updates, etc.)
#   7. Restore data if needed
#   8. Start services
#
# Exit with `exit` at the end to prevent container restart.
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
# ADVANCED SETTINGS - Custom configuration prompts
# ============================================================================
# This function is called during the "Advanced Settings" dialog.
# It allows users to configure app-specific settings before container creation.
# Alternative: Pass ZIM_DIR as environment variable or first argument to skip prompt.
# Example: ZIM_DIR=/mnt/zim bash -c "$(wget -qLO - https://github.com/.../kiwix.sh)"
# ============================================================================

function advanced_settings() {
  # Check if ZIM_DIR already set (via environment or command line)
  if [ -n "$ZIM_DIR" ] && [ -d "$ZIM_DIR" ]; then
    echo -e "${GN}[✓] Using ZIM directory from environment: ${ZIM_DIR}${CL}"
    return 0
  fi

  # Display information about ZIM archives
  echo -e "\n${BL}--- ${APP} ZIM Archive Configuration ---${CL}"
  echo -e "${YW}Kiwix requires ZIM archives to serve offline content.${CL}"
  echo -e "${YW}The directory you specify will be bind-mounted to /data in the container.${CL}"
  echo -e ""
  echo -e "${GN}Download ZIM archives from: https://library.kiwix.org${CL}"
  echo -e "${GN}Wikipedia mirrors: https://github.com/pirate/wikipedia-mirror${CL}"
  echo -e ""

  # Prompt for ZIM directory
  while true; do
    read -p "Enter the path to your ZIM archives directory: " ZIM_DIR

    # Validate directory exists
    if [ ! -d "$ZIM_DIR" ]; then
      echo -e "${RD}[!] Error: Directory '$ZIM_DIR' not found.${CL}"
      read -p "Try again? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
      fi
      continue
    fi

    # Check for .zim files (warning only)
    if ! ls "${ZIM_DIR}"/*.zim >/dev/null 2>&1; then
      echo -e "${YW}[!] Warning: No .zim files found in '$ZIM_DIR'.${CL}"
      echo -e "${YW}    You can add them later and restart the service.${CL}"
      read -p "Continue with this directory? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        continue
      fi
    fi

    # Directory is valid
    echo -e "${GN}[✓] Using directory: ${ZIM_DIR}${CL}"
    break
  done

  # Export for use in post-creation steps
  export ZIM_DIR
}

# Allow command-line argument override
if [ -n "$1" ]; then
  ZIM_DIR="$1"
  export ZIM_DIR
fi

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
# POST-CREATION CONFIGURATION
# ============================================================================
# Configure bind mount and start service
# ============================================================================

# Ensure ZIM_DIR was set (either from advanced_settings or environment variable)
if [ -z "$ZIM_DIR" ]; then
  msg_error "ZIM_DIR not configured. This should not happen."
  exit 1
fi

msg_info "Configuring Bind Mount to ${ZIM_DIR}"
# Note: ro=1 is omitted as it can cause 'Status 9' mount errors
# on certain Btrfs/ZFS configurations with unprivileged containers.
pct set $CTID -mp0 "$ZIM_DIR,mp=/data"
msg_ok "Directory ${ZIM_DIR} mounted to /data"

msg_info "Setting CPU Priority"
pct set $CTID -cpuunits 512
msg_ok "Set CPU Priority"

msg_info "Enabling Auto-start"
pct set $CTID --onboot 1
msg_ok "Enabled Auto-start"

# Get container IP for display
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e ""
echo -e "${INFO}${YW} Additional Information:${CL}"
echo -e "${TAB}${INFO} CTID: ${GN}${CTID}${CL}"
echo -e "${TAB}${INFO} Storage: Bind-mounted from ${ZIM_DIR}${CL}"
echo -e "${TAB}${INFO} Add .zim files to ${ZIM_DIR} and restart the service${CL}"
