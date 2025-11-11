#!/bin/bash
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Configuration
PLEX_USER="plex"
PLEX_HOME="/Users/$PLEX_USER"
LOG_FILE="/Users/$PLEX_USER/Library/Logs/plex_monitor.log"
LOG_DIR="$(dirname "$LOG_FILE")"
QUEUE_FILE="/Users/$PLEX_USER/Library/Logs/airtable_queue.json"
RESTART_HISTORY_FILE="/Users/$PLEX_USER/Library/Logs/restart_history.json"
MAX_RETRIES=2
CHECK_INTERVAL=300
NETWORK_RESTART_ATTEMPTS=3
NETWORK_RESTART_WINDOW=3600  # 1 hour window for rate limiting
MAX_RESTARTS_PER_WINDOW=3
NETWORK_RECOVERY_TIMEOUT=30  # seconds to wait for network recovery
REBOOT_HISTORY_FILE="/Users/$PLEX_USER/Library/Logs/reboot_history.json"
MAX_REBOOT_ATTEMPTS=1
REBOOT_CYCLE_PAUSE=86400  
DAILY_RESET_HOUR=0        # Reset attempts at midnight

# Speed Test Configuration
SPEED_TEST_HOUR=2         # Run speed test at 2am
SPEED_TEST_TIMEZONE='America/New_York'  # EST
SPEED_TEST_LOG="/Users/$PLEX_USER/Library/Logs/network_speeds.log"
SPEED_TEST_HISTORY_FILE="/Users/$PLEX_USER/Library/Logs/speed_test_history.json"
SPEED_TEST_RETRY_DELAY=3600  # 1 hour between retries
MAX_SPEED_TEST_ATTEMPTS=4

# Load tokens from environment file
ENV_FILE="${PLEX_HOME}/.plex_monitor_env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    log_message "Error: Environment file not found at $ENV_FILE"
    exit 1
fi

# Verify required environment variables
if [[ -z "$PLEX_TOKEN" ]] || [[ -z "$AIRTABLE_TOKEN" ]] || [[ -z "$AIRTABLE_BASE" ]]; then
    log_message "Error: Required environment variables not set"
    exit 1
fi

# Test endpoints for network connectivity
declare -a NETWORK_TEST_ENDPOINTS=(
    "1.1.1.1"         # Cloudflare
    "8.8.8.8"         # Google
    "208.67.222.222"  # OpenDNS
    "9.9.9.9"         # Quad9
)

# Initialize logging
init_logging() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chown "$PLEX_USER" "$LOG_DIR"
    fi
    if [[ ! -f "$LOG_FILE" ]]; then
        sudo touch "$LOG_FILE"
        sudo chown "$PLEX_USER" "$LOG_FILE"
    fi
}

# Function to log messages with rotation
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Rotate log if it exceeds 10MB
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE") -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
        sudo chown "$PLEX_USER" "$LOG_FILE"
    fi
    
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# Initialize queue
init_queue() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "[]" > "$QUEUE_FILE"
        sudo chown "$PLEX_USER" "$QUEUE_FILE"
        sudo chmod 644 "$QUEUE_FILE"
    fi
}

# Function to add event to queue
queue_event() {
    local event_type="$1"
    local message="$2"
    local timestamp=$(TZ='America/New_York' date '+%Y-%m-%d %H:%M:%S')
    
    local new_event="{\"event_type\":\"${event_type}\",\"message\":\"${message}\",\"timestamp\":\"${timestamp}\"}"
    
    local current_queue=$(cat "$QUEUE_FILE")
    
    if [ "$current_queue" = "[]" ]; then
        echo "[${new_event}]" > "$QUEUE_FILE"
    else
        echo "${current_queue%]}, ${new_event}]" > "$QUEUE_FILE"
    fi
    
    log_message "Event queued: $event_type - $message"
}

# Function to process queue
process_queue() {
    if ! check_network; then
        log_message "Network down, skipping queue processing"
        return 1
    fi
    
    if [ ! -s "$QUEUE_FILE" ] || [ "$(cat "$QUEUE_FILE")" = "[]" ]; then
        return 0
    fi
    
    log_message "Processing Airtable event queue..."
    
    local temp_file=$(mktemp)
    echo "[]" > "$temp_file"
    
    while IFS= read -r event; do
        [[ "$event" != *"event_type"* ]] && continue
        
        local event_type=$(echo "$event" | sed -n 's/.*"event_type":"\([^"]*\)".*/\1/p')
        local message=$(echo "$event" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
        local timestamp=$(echo "$event" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
        
        local json_data="{\"fields\": {\"Name\": \"${event_type}\", \"Time\": \"${timestamp}\", \"Message\": \"${message}\", \"Script\": \"plex_monitor.sh\"}}"
        
        response=$(curl --write-out '%{http_code}' --silent --output /dev/null -X POST \
            "https://api.airtable.com/v0/${AIRTABLE_BASE}/Server%20Reboots" \
            -H "Authorization: Bearer ${AIRTABLE_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$json_data")
        
        if [ "$response" = "200" ] || [ "$response" = "201" ]; then
            log_message "Successfully processed queued event: $event_type"
        else
            if [ "$(cat "$temp_file")" = "[]" ]; then
                echo "[${event}]" > "$temp_file"
            else
                echo "$(cat "$temp_file" | sed 's/]//'), ${event}]" > "$temp_file"
            fi
        fi
    done < <(grep -o '{[^}]*}' "$QUEUE_FILE")
    
    mv "$temp_file" "$QUEUE_FILE"
    sudo chown "$PLEX_USER" "$QUEUE_FILE"
    
    return 0
}

# Function to log to Airtable
log_to_airtable() {
    local event_type="$1"
    local message="$2"
    
    queue_event "$event_type" "$message"
    
    if check_network; then
        process_queue
    fi
}

# Enhanced network testing function
check_network() {
    local success=false
    
    for endpoint in "${NETWORK_TEST_ENDPOINTS[@]}"; do
        if ping -c 1 -W 2 "$endpoint" > /dev/null 2>&1; then
            success=true
            break
        fi
    done
    
    if ! $success; then
        if nc -zw1 google.com 443 2>/dev/null || nc -zw1 cloudflare.com 443 2>/dev/null; then
            success=true
        fi
    fi
    
    $success
}

# Function to check if Plex is updating
check_plex_updating() {
    # Check for Plex update process
    if pgrep -f "Plex Media Server Updater" > /dev/null; then
        return 0  # updating
    fi
    
    # Check for update artifacts
    local update_lockfile="/Users/$PLEX_USER/Library/Application Support/Plex Media Server/Updates/updateLock"
    if [[ -f "$update_lockfile" ]]; then
        # Check if the lock file is less than 30 minutes old
        if [[ $(( $(date +%s) - $(stat -f %m "$update_lockfile") )) -lt 1800 ]]; then
            return 0  # updating
        fi
    fi
    
    return 1  # not updating
}

# Function to check if Plex is running with update awareness
check_plex() {
    # First check if Plex is updating
    if check_plex_updating; then
        log_message "Plex update in progress - waiting before health check"
        log_to_airtable "Plex Update" "Update in progress - monitoring paused"
        # Wait for update to complete (up to 15 minutes)
        for ((i=1; i<=30; i++)); do
            sleep 30  # Check every 30 seconds
            if ! check_plex_updating; then
                log_message "Plex update completed - resuming normal monitoring"
                break
            fi
        done
        # Give additional grace period after update
        sleep 60
    fi
    
    # Then check if Plex is running
    if pgrep -f "Plex Media Server" > /dev/null; then
        return 0
    else
        # Double check it's not updating before reporting as down
        if check_plex_updating; then
            return 0
        fi
        return 1
    fi
}

# Function to check streams
check_streams() {
    local streams=$(curl -s "http://localhost:32400/status/sessions?X-Plex-Token=$PLEX_TOKEN" | grep -c "<Video")
    log_message "Active streams: $streams"
}

# Function to get active stream count (returns number)
check_active_streams() {
    local streams=$(curl -s "http://localhost:32400/status/sessions?X-Plex-Token=$PLEX_TOKEN" | grep -c "<Video")
    echo "$streams"
}

# Function to restart Plex with update awareness
restart_plex() {
    # Don't restart if updating
    if check_plex_updating; then
        log_message "Skipping restart - Plex update in progress"
        return 0
    fi
    
    local message="Attempting to restart Plex Media Server..."
    log_message "$message"
    log_to_airtable "Plex Restart" "$message"
    
    killall "Plex Media Server" 2>/dev/null
    sleep 10  # Increased wait time
    open -a "Plex Media Server"
    sleep 15  # Increased post-start wait time
    
    # Verify startup
    if pgrep -f "Plex Media Server" > /dev/null; then
        log_message "Plex Media Server restart successful"
        return 0
    else
        log_message "Plex Media Server restart may have failed"
        return 1
    fi
}

# Function to restart network
restart_network() {
    local message="Attempting to restart network services..."
    log_message "$message"
    log_to_airtable "Network Restart" "$message"
    
    # Try soft reset first
    networksetup -setnetworkserviceenabled Wi-Fi off
    sleep 1
    networksetup -setnetworkserviceenabled Wi-Fi on
    sleep 3
    
    # Check if that worked
    if check_network; then
        local success_msg="Network restored after soft reset"
        log_message "$success_msg"
        log_to_airtable "Network Restart Success" "$success_msg"
        return 0
    fi
    
    # Try DNS flush
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
    sleep 2
    
    if check_network; then
        local success_msg="Network restored after DNS flush"
        log_message "$success_msg"
        log_to_airtable "Network Restart Success" "$success_msg"
        return 0
    fi
    
    # Hard reset as last resort
    sudo ifconfig en0 down
    sleep 2
    sudo ifconfig en0 up
    
    # Wait for interface to stabilize
    local start_time=$(date +%s)
    while ! check_network; do
        if [ $(($(date +%s) - start_time)) -gt $NETWORK_RECOVERY_TIMEOUT ]; then
            log_message "Network recovery timed out"
            return 1
        fi
        sleep 2
    done
    
    log_message "Network restored after hard reset"
    log_to_airtable "Network Restart Success" "Network restored after hard reset"
    return 0
}

# Function to reboot computer
reboot_computer() {
    local reboot_info=$(update_reboot_history)
    local attempts=$(echo "$reboot_info" | cut -d: -f1)
    local cycle=$(echo "$reboot_info" | cut -d: -f2)
    
    local message="Initiating system reboot (Attempt $attempts of $MAX_REBOOT_ATTEMPTS, Cycle $cycle)"
    log_message "$message"
    log_to_airtable "System Reboot" "$message"
    
    if [[ "$attempts" -eq "$MAX_REBOOT_ATTEMPTS" ]]; then
        if [[ "$cycle" -eq 1 ]]; then
            message="Maximum reboot attempts reached for first cycle. Pausing for 8 hours."
            log_message "$message"
            log_to_airtable "Reboot Cycle" "$message"
            sleep "$REBOOT_CYCLE_PAUSE"
        elif [[ "$cycle" -eq 2 ]]; then
            message="Maximum reboot attempts reached for second cycle. Waiting until next day."
            log_message "$message"
            log_to_airtable "Reboot Cycle" "$message"
            
            # Calculate time until next reset
            local current_hour=$(date +%H)
            local hours_until_reset=$(( (24 - current_hour + DAILY_RESET_HOUR) % 24 ))
            local seconds_until_reset=$((hours_until_reset * 3600))
            
            sleep "$seconds_until_reset"
            return 1
        fi
    fi
    
    sleep 2
    sudo shutdown -r now
}

# Initialize reboot history file
init_reboot_history() {
    if [[ ! -f "$REBOOT_HISTORY_FILE" ]]; then
        echo '{"last_reboot": null, "attempts": 0, "cycle": 1, "last_cycle_start": null}' > "$REBOOT_HISTORY_FILE"
        sudo chown "$PLEX_USER" "$REBOOT_HISTORY_FILE"
        sudo chmod 644 "$REBOOT_HISTORY_FILE"
    fi
}

# Get current reboot cycle information
get_reboot_info() {
    if [[ ! -f "$REBOOT_HISTORY_FILE" ]]; then
        init_reboot_history
    fi
    cat "$REBOOT_HISTORY_FILE"
}

# Update reboot history
update_reboot_history() {
    local current_time=$(date +%s)
    local reboot_info=$(get_reboot_info)
    
    local attempts=$(echo "$reboot_info" | grep -o '"attempts": *[0-9]*' | grep -o '[0-9]*$')
    local cycle=$(echo "$reboot_info" | grep -o '"cycle": *[0-9]*' | grep -o '[0-9]*$')
    local last_cycle_start=$(echo "$reboot_info" | grep -o '"last_cycle_start": *[0-9]*' | grep -o '[0-9]*$')
    
    # Check if we need to reset based on time
    if [[ -n "$last_cycle_start" ]]; then
        local current_hour=$(date +%H)
        # Strip leading zeros to avoid octal interpretation
        current_hour=$((10#$current_hour))
        local last_cycle_date=$(date -r "$last_cycle_start" +%Y%m%d)
        local current_date=$(date +%Y%m%d)
        
        # Reset if it's a new day and we're at the reset hour
        if [[ "$current_date" > "$last_cycle_date" ]] && [[ "$current_hour" -eq "$DAILY_RESET_HOUR" ]]; then
            attempts=0
            cycle=1
            last_cycle_start=$current_time
        fi
    else
        last_cycle_start=$current_time
    fi
    
    # Increment attempt counter
    attempts=$((attempts + 1))
    
    # If we've reached max attempts, increment cycle and reset attempts
    if [[ "$attempts" -gt "$MAX_REBOOT_ATTEMPTS" ]]; then
        attempts=1
        cycle=$((cycle + 1))
        last_cycle_start=$current_time
    fi
    
    # Write updated info
    echo "{\"last_reboot\": $current_time, \"attempts\": $attempts, \"cycle\": $cycle, \"last_cycle_start\": $last_cycle_start}" > "$REBOOT_HISTORY_FILE"
    
    # Return the current attempt and cycle numbers
    echo "$attempts:$cycle"
}

# ============================================================================
# SPEED TEST FUNCTIONS
# ============================================================================

# Initialize speed test history file
init_speed_test_history() {
    if [[ ! -f "$SPEED_TEST_HISTORY_FILE" ]]; then
        echo '{"last_test_date": null, "attempts_today": 0, "last_attempt_time": null}' > "$SPEED_TEST_HISTORY_FILE"
        sudo chown "$PLEX_USER" "$SPEED_TEST_HISTORY_FILE"
        sudo chmod 644 "$SPEED_TEST_HISTORY_FILE"
    fi
    
    # Create speed test log file if it doesn't exist
    if [[ ! -f "$SPEED_TEST_LOG" ]]; then
        sudo touch "$SPEED_TEST_LOG"
        sudo chown "$PLEX_USER" "$SPEED_TEST_LOG"
    fi
}

# Get current speed test history
get_speed_test_info() {
    if [[ ! -f "$SPEED_TEST_HISTORY_FILE" ]]; then
        init_speed_test_history
    fi
    cat "$SPEED_TEST_HISTORY_FILE"
}

# Update speed test history
update_speed_test_history() {
    local test_completed="$1"  # "success" or "failed"
    local current_time=$(date +%s)
    local current_date=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d')
    local speed_info=$(get_speed_test_info)
    
    local last_test_date=$(echo "$speed_info" | grep -o '"last_test_date": *"[^"]*"' | cut -d'"' -f4)
    local attempts_today=$(echo "$speed_info" | grep -o '"attempts_today": *[0-9]*' | grep -o '[0-9]*$')
    
    # Reset attempts if it's a new day
    if [[ "$last_test_date" != "$current_date" ]]; then
        attempts_today=0
    fi
    
    # Increment attempts
    attempts_today=$((attempts_today + 1))
    
    # Update last_test_date on any attempt to track the current day properly
    # This ensures date-based resets work correctly
    last_test_date="$current_date"
    
    # Write updated info
    echo "{\"last_test_date\": \"${last_test_date}\", \"attempts_today\": ${attempts_today}, \"last_attempt_time\": ${current_time}}" > "$SPEED_TEST_HISTORY_FILE"
    
    echo "$attempts_today"
}

# Check if we should run the speed test
should_run_speed_test() {
    local current_hour=$(TZ="$SPEED_TEST_TIMEZONE" date '+%H')
    local current_minute=$(TZ="$SPEED_TEST_TIMEZONE" date '+%M')
    local current_date=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d')
    
    # Strip leading zeros to avoid octal interpretation (08, 09 cause errors)
    current_hour=$((10#$current_hour))
    
    # Additional check: look for today's entry in the speed log file
    # This is a more reliable check than the JSON history file
    if [[ -f "$SPEED_TEST_LOG" ]]; then
        if grep -q "^${current_date}.*Speed Test:.*Mbps" "$SPEED_TEST_LOG"; then
            # Already have a successful test today - skip silently
            return 1
        fi
    fi
    
    # Get speed test history
    local speed_info=$(get_speed_test_info)
    local last_test_date=$(echo "$speed_info" | grep -o '"last_test_date": *"[^"]*"' | cut -d'"' -f4)
    local attempts_today=$(echo "$speed_info" | grep -o '"attempts_today": *[0-9]*' | grep -o '[0-9]*$')
    local last_attempt_time=$(echo "$speed_info" | grep -o '"last_attempt_time": *[0-9]*' | grep -o '[0-9]*$')
    
    # Reset attempts_today if it's a new day
    # This prevents using stale attempt counts from previous days
    if [[ "$last_test_date" != "$current_date" ]]; then
        attempts_today=0
    fi
    
    # Determine if we should run based on hour and retry status
    local is_test_hour=false
    local has_failed_attempts=false
    
    if [[ "$current_hour" -eq "$SPEED_TEST_HOUR" ]]; then
        is_test_hour=true
    fi
    
    if [[ "$last_test_date" == "$current_date" ]] && [[ "$attempts_today" -gt 0 ]]; then
        has_failed_attempts=true
    fi
    
    # Only run if: it's the test hour OR we have failed attempts to retry
    if [[ "$is_test_hour" == "false" ]] && [[ "$has_failed_attempts" == "false" ]]; then
        return 1
    fi
    
    # If we've reached max attempts, skip
    if [[ "$attempts_today" -ge "$MAX_SPEED_TEST_ATTEMPTS" ]]; then
        return 1
    fi
    
    # If this is a retry attempt, check if enough time has passed
    if [[ -n "$last_attempt_time" ]] && [[ "$attempts_today" -gt 0 ]]; then
        local current_time=$(date +%s)
        local time_since_last=$(( current_time - last_attempt_time ))
        
        if [[ "$time_since_last" -lt "$SPEED_TEST_RETRY_DELAY" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Run speed test and log results
run_speed_test() {
    log_message "Starting network speed test..."
    
    # Check if speedtest-cli is installed
    if ! command -v speedtest-cli &> /dev/null; then
        log_message "ERROR: speedtest-cli not installed. Install with: pip install speedtest-cli --break-system-packages"
        log_to_airtable "Speed Test Error" "speedtest-cli not installed"
        return 1
    fi
    
    # Check for active streams
    local active_streams=$(check_active_streams)
    if [[ "$active_streams" -gt 0 ]]; then
        log_message "Speed test skipped: $active_streams active stream(s) detected"
        update_speed_test_history "failed"
        return 2  # Return 2 to indicate streams active
    fi
    
    # Check network availability
    if ! check_network; then
        local message="Speed Test Skipped: Network unavailable"
        log_message "$message"
        log_to_airtable "Speed Test Skipped" "Network unavailable"
        
        # Log to speed test file
        local timestamp=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')
        echo "$timestamp - $message" >> "$SPEED_TEST_LOG"
        
        update_speed_test_history "failed"
        return 1
    fi
    
    # Check if Plex is updating
    if check_plex_updating; then
        local message="Speed Test Skipped: Plex update in progress"
        log_message "$message"
        log_to_airtable "Speed Test Skipped" "Plex update in progress"
        
        # Log to speed test file
        local timestamp=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')
        echo "$timestamp - $message" >> "$SPEED_TEST_LOG"
        
        update_speed_test_history "failed"
        return 1
    fi
    
    # Run the speed test
    log_message "Running speedtest-cli (this may take 30 seconds)..."
    local test_output=$(speedtest-cli --simple 2>&1)
    local exit_code=$?
    
    # Check for 403 error and retry immediately (common cold-start issue)
    if [[ $exit_code -ne 0 ]] && echo "$test_output" | grep -q "403"; then
        log_message "Got 403 Forbidden error - retrying immediately after 5 second delay..."
        sleep 5
        test_output=$(speedtest-cli --simple 2>&1)
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            log_message "Retry successful after 403 error"
        fi
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log_message "Speed test failed with exit code $exit_code: $test_output"
        log_to_airtable "Speed Test Failed" "Error running speedtest-cli (exit code: $exit_code)"
        update_speed_test_history "failed"
        return 1
    fi
    
    # Parse results
    local ping=$(echo "$test_output" | grep "Ping:" | awk '{print $2}')
    local download=$(echo "$test_output" | grep "Download:" | awk '{print $2}')
    local upload=$(echo "$test_output" | grep "Upload:" | awk '{print $2}')
    
    # Validate that we got actual values
    if [[ -z "$download" ]] || [[ -z "$upload" ]] || [[ -z "$ping" ]]; then
        if echo "$test_output" | grep -q "403"; then
            log_message "Speed test parsing failed due to 403 error (already retried). Output: $test_output"
            log_to_airtable "Speed Test Failed" "403 Forbidden error persisted after retry"
        else
            log_message "Speed test parsing failed. Output: $test_output"
            log_to_airtable "Speed Test Failed" "Failed to parse speedtest-cli output"
        fi
        update_speed_test_history "failed"
        return 1
    fi
    
    # Get server info (optional, requires full output)
    local server_info=$(speedtest-cli --list 2>&1 | head -5 | tail -1 || echo "Unknown")
    
    # Format the results
    local timestamp=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')
    local result_message="Download: ${download} Mbps | Upload: ${upload} Mbps | Ping: ${ping} ms"
    
    # Log to speed test file with rotation
    if [[ -f "$SPEED_TEST_LOG" ]] && [[ $(stat -f%z "$SPEED_TEST_LOG") -gt 10485760 ]]; then
        mv "$SPEED_TEST_LOG" "${SPEED_TEST_LOG}.1"
        touch "$SPEED_TEST_LOG"
        sudo chown "$PLEX_USER" "$SPEED_TEST_LOG"
    fi
    
    echo "$timestamp - Speed Test: $result_message" >> "$SPEED_TEST_LOG"
    
    # Log to main log
    log_message "Speed test completed: $result_message"
    
    # Log to Airtable
    log_to_airtable "Network Speed Test" "$result_message"
    
    # Update history as successful
    update_speed_test_history "success"
    
    return 0
}

# Handle speed test with retry logic
handle_speed_test() {
    if ! should_run_speed_test; then
        return 0
    fi
    
    local speed_info=$(get_speed_test_info)
    local attempts_today=$(echo "$speed_info" | grep -o '"attempts_today": *[0-9]*' | grep -o '[0-9]*$')
    local attempt_num=$((attempts_today + 1))
    
    log_message "Speed test window active (Attempt $attempt_num of $MAX_SPEED_TEST_ATTEMPTS)"
    
    run_speed_test
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log_message "Speed test completed successfully"
    elif [[ $result -eq 2 ]]; then
        # Streams active - will retry
        log_message "Speed test delayed due to active streams, will retry in 1 hour"
        
        if [[ $attempt_num -eq $MAX_SPEED_TEST_ATTEMPTS ]]; then
            local message="Speed Test Skipped: Unable to complete after $MAX_SPEED_TEST_ATTEMPTS attempts due to active streams"
            log_message "$message"
            log_to_airtable "Speed Test Skipped" "Unable to complete after $MAX_SPEED_TEST_ATTEMPTS attempts - streams active"
            
            local timestamp=$(TZ="$SPEED_TEST_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')
            echo "$timestamp - $message" >> "$SPEED_TEST_LOG"
        fi
    else
        # Other failure (network, Plex updating, etc.) - already logged
        if [[ $attempt_num -eq $MAX_SPEED_TEST_ATTEMPTS ]]; then
            log_message "Speed test attempts exhausted for today"
        fi
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_message "Starting Secure Plex Monitor Script with Network Speed Testing"

# Initialize systems
init_logging
init_queue
init_reboot_history
init_speed_test_history

# Check if speedtest-cli is installed
if ! command -v speedtest-cli &> /dev/null; then
    log_message "WARNING: speedtest-cli not installed. Speed tests will be skipped."
    log_message "Install with: pip install speedtest-cli --break-system-packages"
fi

# Process any queued events from previous runs
if check_network; then
    process_queue
fi

log_message "Starting main monitoring loop..."

# Main monitoring loop
while true; do
    log_message "Starting monitoring cycle..."
    
    # Check if we should run a speed test
    handle_speed_test
    
    reboot_info=$(get_reboot_info)
    attempts=$(echo "$reboot_info" | grep -o '"attempts": *[0-9]*' | grep -o '[0-9]*$')
    cycle=$(echo "$reboot_info" | grep -o '"cycle": *[0-9]*' | grep -o '[0-9]*$')
    
    if [[ "$attempts" -ge "$MAX_REBOOT_ATTEMPTS" ]] && [[ "$cycle" -ge 2 ]]; then
        log_message "In waiting period after reboot cycles. Continuing monitoring without reboot attempts."
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    if check_network; then
        process_queue
    fi
    
    if ! check_plex; then
        log_message "Plex Media Server is not running."
        restart_plex
        
        for ((i=1; i<=$MAX_RETRIES; i++)); do
            sleep 10
            if check_plex; then
                success_msg="Plex Media Server restarted successfully."
                log_message "$success_msg"
                log_to_airtable "Plex Restart Success" "$success_msg"
                break
            fi
            
            if [ $i -eq $MAX_RETRIES ]; then
                log_message "Max retries reached. Exiting."
                exit 1
            fi
        done
    else
        if ! check_network; then
            log_message "Network is down. Beginning recovery process..."
            
            for ((i=1; i<=$NETWORK_RESTART_ATTEMPTS; i++)); do
                if restart_network; then
                    log_message "Network recovered after attempt $i"
                    break
                fi
                
                if [ $i -eq $NETWORK_RESTART_ATTEMPTS ]; then
                    log_message "Network remains down after $NETWORK_RESTART_ATTEMPTS restart attempts. Initiating progressive reboot cycle."
                    if ! reboot_computer; then
                        log_message "Reboot cycle complete. Continuing normal monitoring."
                    fi
                fi
            done
        else
            log_message "All systems operational."
            check_streams
        fi
    fi
    
    log_message "Waiting for next check interval of $CHECK_INTERVAL seconds."
    sleep $CHECK_INTERVAL
done
# Auto-deploy test - 2025-11-10 08:20:21
# testing auto deploy
