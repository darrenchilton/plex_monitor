#!/bin/bash

# Set explicit PATH for LaunchDaemon environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Auto-deploy script for plex_monitor
# Checks GitHub for updates and deploys them automatically

REPO_DIR="/Users/plex/plex_monitor"
SCRIPT_SOURCE="$REPO_DIR/scripts/plex_monitor.sh"
SCRIPT_DEST="/Users/plex/plex_monitor.sh"
PLIST_PATH="/Library/LaunchDaemons/com.user.plexmonitor.plist"
LOG_FILE="/Users/plex/Library/Logs/auto_deploy.log"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Change to repo directory
cd "$REPO_DIR" || {
    log_message "ERROR: Could not access repository at $REPO_DIR"
    exit 1
}

# Fetch latest changes from GitHub
/usr/bin/git fetch origin main &>/dev/null

# Check if there are updates
LOCAL=$(/usr/bin/git rev-parse HEAD)
REMOTE=$(/usr/bin/git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    # No updates - exit silently (no log spam)
    exit 0
fi

log_message "Updates detected! Local: ${LOCAL:0:7}, Remote: ${REMOTE:0:7}"

# Pull the changes
if ! /usr/bin/git pull origin main &>/dev/null; then
    log_message "ERROR: Git pull failed"
    exit 1
fi

log_message "Successfully pulled changes from GitHub"

# Verify the script exists and is readable
if [ ! -r "$SCRIPT_SOURCE" ]; then
    log_message "ERROR: Cannot read $SCRIPT_SOURCE"
    exit 1
fi

# Stop the monitor
log_message "Stopping plex_monitor service..."
if ! /usr/bin/sudo /bin/launchctl unload "$PLIST_PATH" 2>/dev/null; then
    log_message "WARNING: Could not unload service (may not be running)"
fi

# Copy updated script
if ! /bin/cp "$SCRIPT_SOURCE" "$SCRIPT_DEST"; then
    log_message "ERROR: Failed to copy script to $SCRIPT_DEST"
    exit 1
fi

# Set permissions
/usr/sbin/chown plex:staff "$SCRIPT_DEST"
/bin/chmod 755 "$SCRIPT_DEST"

log_message "Script deployed successfully"

# Restart the monitor
log_message "Starting plex_monitor service..."
if /usr/bin/sudo /bin/launchctl load "$PLIST_PATH"; then
    log_message "Service restarted successfully"
    log_message "Deployment complete! Commit: ${REMOTE:0:7}"
else
    log_message "ERROR: Failed to start service"
    exit 1
fi
# testing auto deply 2
