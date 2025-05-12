#!/bin/bash
#
# filename: directory_io_monitor.sh
#
# Directory I/O Monitor Script
# Monitors filesystem activity in a specified directory using inotifywait.
# Tracks size changes, calculates I/O rates, and displays recent events.
# Includes interactive controls and handles large directories efficiently.
#
# Requirements: inotifywait, find, awk, tput
#
# Version: 1.0
# Date: 2023-10-27 (Updated for optimization)

# --- Configuration ---
TARGET_DIR="."              # Default directory to monitor
UPDATE_INTERVAL_SEC=1       # How often to refresh the display (in seconds)
SIZE_CHECK_INTERVAL_SEC=10  # How often to recalculate full directory size (expensive on large trees)
EVENT_BUFFER_SIZE=50        # Number of recent events to display
MAX_DEPTH=5                 # Maximum depth level allowed for monitoring
INOTIFY_EVENTS="create,delete,modify,move" # Events to monitor

# --- Global Variables ---
declare -A current_sizes    # Associative array: depth -> current_size_bytes
declare -A previous_sizes   # Associative array: depth -> previous_size_bytes
declare -A io_rates_bytes_sec # Associative array: depth -> io_rate_bytes_per_second
declare -A cumulative_changes_bytes # Associative array: depth -> cumulative_change_bytes
declare -a recent_events_array # Array to store recent inotify events
declare -i current_depth=1    # Current depth level being displayed/tracked
declare -i start_time         # Timestamp when script started
declare -i last_update_time   # Timestamp of the last display update
declare -i last_size_check_time # Timestamp of the last full size calculation
declare -i total_elapsed_time # Total time script has been running
declare -i term_lines         # Terminal height
declare -i term_cols          # Terminal width

paused=false                # Flag to indicate if monitoring is paused
display_mode="text"         # Current display mode (text/graphical - graphical planned but basic text initially)
INOTIFY_PID=0               # PID of the background inotifywait process
declare -a dependencies=("inotifywait" "find" "awk" "tput") # Required commands

# --- Terminal Control Functions ---
tput_clear() { tput clear; }
tput_cup() { tput cup "$1" "$2"; }
tput_bold() { tput bold; }
tput_normal() { tput sgr0; }
tput_hide_cursor() { tput civis; }
tput_show_cursor() { tput cnorm; }
tput_red() { tput setaf 1; }
tput_green() { tput setaf 2; }
tput_yellow() { tput setaf 3; }
tput_blue() { tput setaf 4; }
tput_reset_color() { tput op; }

# --- Helper Functions ---

# Function to check for required commands
check_dependencies() {
    echo "Checking dependencies..."
    local missing=false
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            tput_red; echo "Error: Required command '$cmd' not found. Please install it."$(tput_reset_color)
            missing=true
        fi
    done
    if [[ "$missing" == "true" ]]; then
        exit 1
    fi
    echo "All dependencies found."
}

## Function to format bytes into human-readable string (KB, MB, GB, TB)
#format_bytes() {
#    local bytes=$1
#    local units=("B" "KB" "MB" "GB" "TB" "PB" "EB" "ZB" "YB")
#    local i=0
#    local value=$bytes
#
#    if (( bytes < 1024 )); then
#        printf "%5d %s" "$bytes" "${units[0]}"
#        return
#    fi
#
#    while (( value >= 1024 && i < ${#units[@]} - 1 )); do
#        value=$(awk "BEGIN { printf \"%.2f\", $value / 1024 }")
#        i=$((i + 1))
#    done
#    printf "%5.2f %s" "$value" "${units[i]}"
#}

# Function to format bytes into human-readable string (KB, MB, GB, TB)
format_bytes() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB" "PB" "EB" "ZB" "YB")
    local i=0
    local value=$bytes # Initialize value as integer

    # Handle bytes less than 1024 directly
    if (( bytes < 1024 )); then
        printf "%5d %s" "$bytes" "${units[0]}"
        return
    fi

    # Use awk for floating point division and comparison in the loop
    # The loop continues as long as the current value is >= 1024 AND we haven't reached the last unit
    # We use awk's exit status (0 for true, 1 for false) for the float comparison
    while awk "BEGIN { exit !($value >= 1024) }" && (( i < ${#units[@]} - 1 )); do
        # Perform the division and update 'value' with the new float string
        value=$(awk "BEGIN { printf \"%.2f\", $value / 1024 }")
        i=$((i + 1))
    done

    # Print the final formatted float value and unit
    printf "%5.2f %s" "$value" "${units[i]}"
}

# Function to get terminal dimensions
get_term_size() {
    term_lines=$(tput lines)
    term_cols=$(tput cols)
}

# --- Core Monitoring Functions ---

# Initialize variables and arrays
init_vars() {
    echo "Initializing variables..."
    start_time=$(date +%s)
    last_update_time=$start_time
    last_size_check_time=0 # Force initial size check

    # Initialize sizes and rates for all tracked depths (currently only current_depth)
    current_sizes["$current_depth"]=0
    previous_sizes["$current_depth"]=0
    io_rates_bytes_sec["$current_depth"]=0
    cumulative_changes_bytes["$current_depth"]=0

    recent_events_array=()
    get_term_size # Get initial terminal size
    tput_hide_cursor # Hide cursor while running
}

# Get directory size for a specific depth
# Uses find and awk for efficiency on large numbers of files.
get_directory_size() {
    local depth=$1
    local size=0

    # Find files within the specified depth and sum their sizes
    # Redirect stderr to /dev/null to ignore permission errors etc.
    size=$(find "$TARGET_DIR" -mindepth 1 -maxdepth "$depth" -type f -printf "%s\n" 2>/dev/null | awk '{sum+=$1} END {print sum}')

    # If awk output is empty (e.g., no files found), size will be empty. Treat as 0.
    size=${size:-0}
    echo "$size" # Return size via standard output
}

# Calculate I/O rates and cumulative totals
calculate_data_rate() {
    local current_size=$1
    local current_time=$2
    local depth=$3

    local prev_size=${previous_sizes["$depth"]:-0}
    local prev_time=${last_size_check_time:-0} # Use last size check time for rate calculation base

    local delta_time=$((current_time - prev_time))
    local delta_size=$((current_size - prev_size))

    if (( delta_time > 0 )); then
        io_rates_bytes_sec["$depth"]=$((delta_size / delta_time))
    else
        io_rates_bytes_sec["$depth"]=0
    fi

    # Update cumulative change
    # Cumulative change tracks the total change from the start, based on delta_size
    cumulative_changes_bytes["$depth"]=$((cumulative_changes_bytes["$depth"] + delta_size))

    # Store current values for next calculation
    previous_sizes["$depth"]=$current_size
}

# Process inotifywait log stream
# Reads events piped from inotifywait and adds them to the recent_events_array
process_inotify_stream() {
    local event_line="$1"
    if [[ -n "$event_line" ]]; then
        recent_events_array+=("$event_line")
        # Keep the array size within the buffer limit
        if (( ${#recent_events_array[@]} > EVENT_BUFFER_SIZE )); then
            recent_events_array=("${recent_events_array[@]:1}") # Remove the oldest event
        fi
    fi
}

# Display activity visually using tput
graphical_output() {
    tput_clear # Clear the screen for redraw
    get_term_size # Get current terminal size

    tput_cup 0 0; tput_bold; echo "Directory I/O Monitor - Target: $TARGET_DIR (Depth: $current_depth)"; tput_normal

    local current_time=$(date +%s)
    total_elapsed_time=$((current_time - start_time))
    local elapsed_formatted=$(date -u -d @"$total_elapsed_time" +'%H:%M:%S')

    tput_cup 2 0; tput_yellow; echo "Status: $( [[ "$paused" == true ]] && echo "PAUSED" || echo "RUNNING" ) | Elapsed: $elapsed_formatted"; tput_reset_color

    # Display metrics for the current depth
    local current_size=${current_sizes["$current_depth"]:-0}
    local io_rate=${io_rates_bytes_sec["$current_depth"]:-0}
    local cumulative_change=${cumulative_changes_bytes["$current_depth"]:-0}

    tput_cup 4 0; echo "Directory Size (Depth $current_depth): $(format_bytes "$current_size")"
    tput_cup 5 0; echo "I/O Rate (Approx):   $(format_bytes "$io_rate")/s"
    tput_cup 6 0; echo "Cumulative Change:   $(format_bytes "$cumulative_change")"

    tput_cup 8 0; tput_bold; echo "Recent Events:"; tput_normal

    # Display recent events
    local event_display_rows=$((term_lines - 15)) # Reserve space for metrics, headers, help
    if (( event_display_rows < 0 )); then event_display_rows=0; fi # Prevent negative rows

    local start_index=$(( ${#recent_events_array[@]} > event_display_rows ? ${#recent_events_array[@]} - event_display_rows : 0 ))

    for ((i=start_index; i < ${#recent_events_array[@]}; i++)); do
        local line_num=$((8 + (i - start_index) + 1))
        if (( line_num < term_lines - 5 )); then # Ensure we don't write over the help section
            tput_cup "$line_num" 0
            # Simple coloring based on event type (basic parsing)
            if [[ "${recent_events_array[i]}" =~ "CREATE" ]]; then tput_green;
            elif [[ "${recent_events_array[i]}" =~ "DELETE" ]]; then tput_red;
            elif [[ "${recent_events_array[i]}" =~ "MODIFY" ]]; then tput_blue;
            elif [[ "${recent_events_array[i]}" =~ "MOVED_" ]]; then tput_yellow;
            else tput_normal; fi
            # Truncate event line if too long
            echo "${recent_events_array[i]:0:$((term_cols - 2))}"$(tput_reset_color)
        fi
    done

    # Display help/key bindings at the bottom
    tput_cup $((term_lines - 5)) 0; tput_bold; echo "Key Bindings:"; tput_normal
    tput_cup $((term_lines - 4)) 0; echo " P: Pause/Resume | N/n: Change Depth (+/-1) | H: Help | Q: Quit"
    tput_cup $((term_lines - 3)) 0; echo " Depth Range: 1 - $MAX_DEPTH"
    tput_cup $((term_lines - 2)) 0; echo " Version 1.0 | Monitoring $TARGET_DIR"

    tput_cup $((term_lines - 1)) 0 # Leave cursor at the bottom
}

# Display help message (alternative to integrating into main view)
display_help() {
    tput_clear
    echo "Directory I/O Monitor Help"
    echo "--------------------------"
    echo "Monitors file system activity in real-time using inotifywait."
    echo "Tracks directory size changes, I/O rates, and recent events."
    echo ""
    tput_bold; echo "Key Bindings:"; tput_normal
    echo " P / p : Pause or resume the monitoring."
    echo " N / n : Increase / decrease the monitoring depth level."
    echo " + / = : Increase the monitoring depth level."
    echo " - / _ : Decrease the monitoring depth level."
    echo " H / h : Display this help message."
    echo " Q / q : Quit the script."
    echo ""
    tput_bold; echo "Monitoring Depth:"; tput_normal
    echo " The depth level controls how deep into subdirectories the size calculation goes."
    echo " Depth 1 includes files directly in the target directory."
    echo " Depth 2 includes files in the target directory and its immediate subdirectories, etc."
    echo " Supported range: 1 to $MAX_DEPTH."
    echo ""
    tput_bold; echo "I/O Rate:"; tput_normal
    echo " The approximate rate of data change (written/deleted bytes per second) within the monitored scope."
    echo " This is calculated periodically based on full directory size scans."
    echo ""
    tput_bold; echo "Cumulative Change:"; tput_normal
    echo " The total bytes added or removed since the script started."
    echo ""
    tput_bold; echo "Recent Events:"; tput_normal
    echo " Live stream of filesystem events (create, delete, modify, move) reported by inotifywait."
    echo ""
    echo "Press any key to return to monitoring..."
    read -n 1 -s # Wait for a key press
    # Redraw the main display after help
    graphical_output
}


# Handle keyboard input for interactive controls
handle_input() {
    local key
    # Read up to 1 character with a timeout of 0.05 seconds
    # This makes the read non-blocking enough to keep the loop responsive
    if read -t 0.05 -n 1 key; then
        case "$key" in
            [Pp])
                paused=!paused
                ;;
            [Nn]|\+|\=)
                if (( current_depth < MAX_DEPTH )); then
                    current_depth=$((current_depth + 1))
                    # Re-initialize size tracking for the new depth immediately
                    # Or queue a size calculation for the next interval
                    # Let's force a size recalculation soon
                     last_size_check_time=0
                    current_sizes["$current_depth"]=0
                    previous_sizes["$current_depth"]=0
                    io_rates_bytes_sec["$current_depth"]=0
                    cumulative_changes_bytes["$current_depth"]=0

                fi
                ;;
            [n]|\-|\_)
                if (( current_depth > 1 )); then
                    current_depth=$((current_depth - 1))
                     # Re-initialize size tracking for the new depth immediately
                    # Or queue a size calculation for the next interval
                     last_size_check_time=0
                     current_sizes["$current_depth"]=0
                     previous_sizes["$current_depth"]=0
                    io_rates_bytes_sec["$current_depth"]=0
                    cumulative_changes_bytes["$current_depth"]=0
                fi
                ;;
            [Hh])
                display_help
                ;;
            [Qq])
                echo "Quitting..."
                exit 0 # Handled by signal_handlers trap
                ;;
        esac
    fi
}

# --- Signal Handling ---

# Function to be called on script termination
cleanup() {
    echo "Cleaning up..."
    if [[ "$INOTIFY_PID" -ne 0 ]]; then
        kill "$INOTIFY_PID" 2>/dev/null
        wait "$INOTIFY_PID" 2>/dev/null # Wait for inotifywait to exit
    fi
    tput_show_cursor # Show cursor
    tput_normal # Reset text attributes
    tput_clear # Clear screen on exit (optional, but clean)
    exit 0
}

# Trap signals for clean termination
signal_handlers() {
    trap cleanup SIGINT SIGTERM
}

# --- Main Monitoring Loop ---

monitor_io() {
    # Start inotifywait in the background and pipe its output to process_inotify_stream
    # Using process substitution <(...) to create a file descriptor for the pipe
    inotifywait -m -r -e "$INOTIFY_EVENTS" "$TARGET_DIR" \
        --format '%T %w%f %e' --timefmt '%F %T' 2>/dev/null > >(while read -r line; do process_inotify_stream "$line"; done) &
    INOTIFY_PID=$!
    echo "inotifywait started with PID: $INOTIFY_PID"

    # Give inotifywait a moment to start
    sleep 1

    # Main loop
    while true; do
        local current_time=$(date +%s)

        # --- Periodic Full Size Check (Expensive) ---
        if ! "$paused" && (( current_time - last_size_check_time >= SIZE_CHECK_INTERVAL_SEC )); then
            echo "Recalculating size for depth $current_depth..." > /dev/tty # Debug to terminal
            local new_size=$(get_directory_size "$current_depth")
            current_sizes["$current_depth"]=$new_size
            calculate_data_rate "$new_size" "$current_time" "$current_depth"
            last_size_check_time=$current_time
            echo "Size calculation complete." > /dev/tty # Debug to terminal
        fi

        # --- Display Update ---
        if (( current_time - last_update_time >= UPDATE_INTERVAL_SEC )); then
             graphical_output
             last_update_time=$current_time
        fi

        # --- Handle Input ---
        handle_input

        # Small sleep to prevent tight loop and allow input/inotifywait processing
        sleep 0.01
    done
}

# --- Script Execution Start ---

# Check for target directory argument
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [directory]"
    exit 1
elif [[ $# -eq 1 ]]; then
    TARGET_DIR="$1"
fi

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    tput_red; echo "Error: Directory '$TARGET_DIR' not found or is not a directory."$(tput_reset_color)
    exit 1
fi

# Make target directory an absolute path for clarity and reliability
TARGET_DIR=$(readlink -f "$TARGET_DIR")

check_dependencies
init_vars
signal_handlers

# Initial size calculation before starting the main loop
echo "Performing initial size calculation for depth $current_depth..."
initial_size=$(get_directory_size "$current_depth")
current_sizes["$current_depth"]=$initial_size
previous_sizes["$current_depth"]=$initial_size # Set initial previous size to current for rate calculation start
last_size_check_time=$(date +%s)
echo "Initial size calculation complete: $(format_bytes "$initial_size"). Starting monitor."

# Start monitoring loop
monitor_io

# Should theoretically not be reached unless monitor_io loop is broken
cleanup
