#!/bin/bash
################################################################################
# Directory I/O Monitor
#
# Description:
#   Monitors file system events and directory size changes (at multiple depth 
#   levels) using inotifywait and du. It computes I/O metrics (MB/s) and shows 
#   cumulative totals along with recent file events and system resource usage.
#
# Features:
#   - Uses inotifywait to capture file create/modify/delete/move events.
#   - Uses find/du with -mindepth/-maxdepth for configurable depth-level sizing.
#   - Calculates real-time I/O rates (MB/s) using two-second intervals.
#   - Offers interactive controls: pause/resume, change depth level, toggle text/graphical view,
#     view help and diagnostics, and quit gracefully.
#   - Rotates inotify log when size exceeds 10MB.
#   - Clean termination via signal handling.
#
# Version: 1.0.0
# Author: Your Name
################################################################################

######################## Global Variables ####################################

# Directory to monitor; if not provided, defaults to current directory.
MONITOR_DIR=""

# Monitored depth level (changeable with n/N keys)
CURRENT_DEPTH=1

# Flag to pause/resume monitoring
PAUSED=false

# Display mode: "graphical" uses tput formatting; "text" simply prints plain text.
DISPLAY_MODE="graphical"

# Script version and start time (for diagnostics)
VERSION="1.0.0"
START_TIME=0

# Log and stats files in /tmp; these will be rotated if too big.
LOG_FILE="/tmp/dir_io_monitor.log"
STATS_FILE="/tmp/dir_io_stats.log"
METRICS_FILE="/tmp/dir_metrics.log"

######################## init_vars() #########################################
# Initializes global variables, sets the monitored directory, defaults, and clears
# previous log/stat files.
###############################################################################
init_vars() {
    MONITOR_DIR="${1:-$(pwd)}"
    CURRENT_DEPTH=1
    PAUSED=false
    DISPLAY_MODE="graphical"
    START_TIME=$(date +%s)
    # Clear (or create) log files
    : > "$LOG_FILE"
    : > "$STATS_FILE"
    : > "$METRICS_FILE"
}

######################## cleanup_and_exit() ##################################
# Restore terminal state and terminate all background processes.
###############################################################################
cleanup_and_exit() {
    stty sane
    kill 0   # Kill all child processes of this script
    echo "Terminated monitor gracefully."
    exit 0
}

######################## signal_handlers() ###################################
# Set traps for SIGINT/SIGTERM to ensure a clean exit.
###############################################################################
signal_handlers() {
    trap cleanup_and_exit SIGINT SIGTERM
}

######################## monitor_inotify() ###################################
# Monitors filesystem events recursively using inotifywait. Events (create,
# modify, delete, move) are appended to LOG_FILE with a timestamp.
###############################################################################
monitor_inotify() {
    inotifywait -m -r -e create -e modify -e delete -e move "$MONITOR_DIR" \
        --format '%T %w %f %e' --timefmt '%F %T' >> "$LOG_FILE" 2>/dev/null
}

######################## proc_lgfls() ########################################
# Processes the inotify log file: performs a log rotation when the log exceeds 
# 10MB. (This function is re-run on each display update.)
###############################################################################
proc_lgfls() {
    local max_size=$((10 * 1024 * 1024))  # 10MB threshold
    if [ -f "$LOG_FILE" ]; then
        local filesize
        filesize=$(stat -c%s "$LOG_FILE" 2>/dev/null)
        if [ "$filesize" -gt "$max_size" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
            : > "$LOG_FILE"
        fi
    fi
}

######################## monitor_io() ########################################
# Tracks directory size changes at the current depth level. Uses du with 
# --max-depth so that only directories at the specified level are accounted for.
# Every second the current total size is appended to STATS_FILE.
###############################################################################
monitor_io() {
    while true; do
        if [ "$PAUSED" = false ]; then
            # Using du to get the aggregate size (in bytes)
            local size_line
            size_line=$(du -sb --max-depth="$CURRENT_DEPTH" "$MONITOR_DIR" 2>/dev/null | tail -n 1)
            local current_time size
            current_time=$(date +%s)
            size=$(echo "$size_line" | awk '{print $1}')
            echo "$current_time $size" >> "$STATS_FILE"
        fi
        sleep 1
    done
}

######################## calculate_data_rate() ###############################
# Computes the I/O rate (in MB/s) based on the difference between the last two 
# measurements in STATS_FILE. The latest metric (current size and rate) is written 
# into METRICS_FILE.
###############################################################################
calculate_data_rate() {
    while true; do
        if [ "$PAUSED" = false ]; then
            local line_count
            line_count=$(wc -l < "$STATS_FILE")
            if [ "$line_count" -ge 2 ]; then
                local last_two t1 s1 t2 s2 dt ds rate
                last_two=$(tail -n 2 "$STATS_FILE")
                t1=$(echo "$last_two" | head -n1 | awk '{print $1}')
                s1=$(echo "$last_two" | head -n1 | awk '{print $2}')
                t2=$(echo "$last_two" | tail -n1 | awk '{print $1}')
                s2=$(echo "$last_two" | tail -n1 | awk '{print $2}')
                dt=$((t2 - t1))
                ds=$((s2 - s1))
                if [ "$dt" -gt 0 ]; then
                    # Convert bytes/sec to MB/sec (1 MB = 1048576 bytes)
                    rate=$(echo "scale=2; $ds / $dt / 1048576" | bc)
                else
                    rate="0.00"
                fi
                # Write the latest total size and I/O rate to METRICS_FILE
                echo "$s2 $rate" > "$METRICS_FILE"
            fi
        fi
        sleep 1
    done
}

######################## show_help() #########################################
# Displays a help screen with key bindings and usage information.
###############################################################################
show_help() {
    clear
    echo "Directory I/O Monitor Help"
    echo "---------------------------"
    echo "q : Quit the monitor"
    echo "p : Pause monitoring"
    echo "r : Resume monitoring"
    echo "n : Increase directory depth level"
    echo "N : Decrease directory depth level (min 1)"
    echo "m : Toggle display mode (text/graphical)"
    echo "h : Show this help screen"
    echo "v : Display version and diagnostic information"
    echo ""
    echo "Press any key to return..."
    read -rn 1
}

######################## show_diagnostics() ##################################
# Displays version and diagnostic information.
###############################################################################
show_diagnostics() {
    clear
    echo "Directory I/O Monitor Diagnostics"
    echo "---------------------------------"
    echo "Version:           $VERSION"
    echo "Monitoring Dir:    $MONITOR_DIR"
    echo "Current Depth:     $CURRENT_DEPTH"
    echo "Paused:            $PAUSED"
    echo ""
    echo "Press any key to return..."
    read -rn 1
}

######################## graphical_output() ##################################
# Displays real-time monitoring metrics using tput formatting. The output shows:
#  - Monitored directory & current depth level.
#  - Current total size (formatted with numfmt)
#  - I/O rate (MB/s) and cumulative size.
#  - Recent file events and system memory usage.
###############################################################################
graphical_output() {
    while true; do
        if [ "$PAUSED" = false ]; then
            clear
            # Get current terminal size (for responsiveness)
            cols=$(tput cols)
            lines=$(tput lines)
            # Get the latest metrics from METRICS_FILE (if available)
            if [ -s "$METRICS_FILE" ]; then
                read current_size io_rate < "$METRICS_FILE"
            else
                current_size=0
                io_rate="0.00"
            fi

            tput cup 0 0
            echo "Directory I/O Monitor - [$DISPLAY_MODE Mode]"
            echo "Monitoring: $MONITOR_DIR  |  Depth Level: $CURRENT_DEPTH"
            echo "Current Size: $(numfmt --to=iec "$current_size")  |  I/O Rate: ${io_rate} MB/s"
            echo "Cumulative Total: $(numfmt --to=iec "$current_size")"
            echo "-----------------------------------------------"
            echo "Recent File Events:"
            proc_lgfls       # Rotate log file if needed
            tail -n 5 "$LOG_FILE"
            echo "-----------------------------------------------"
            echo "System Resource Usage:"
            free -m | head -n 2
            echo "-----------------------------------------------"
            echo "Key Bindings: [q] Quit  [p] Pause  [r] Resume  [n/N] Depth +/-  [m] Toggle Mode"
            echo "              [h] Help  [v] Diagnostics"
        else
            tput cup 0 0
            echo "Monitoring is PAUSED. Press 'r' to resume."
        fi
        sleep 1
    done
}

######################## text_output() #######################################
# Displays real-time monitoring metrics in plain text (non-graphical mode).
###############################################################################
text_output() {
    while true; do
        if [ "$PAUSED" = false ]; then
            if [ -s "$METRICS_FILE" ]; then
                read current_size io_rate < "$METRICS_FILE"
            else
                current_size=0
                io_rate="0.00"
            fi
            echo "Dir: $MONITOR_DIR | Depth: $CURRENT_DEPTH | Size: $(numfmt --to=iec "$current_size") | I/O: ${io_rate} MB/s"
            tail -n 3 "$LOG_FILE"
            echo "Memory Usage:"
            free -m | head -n 2
            echo "---------------------------"
        else
            echo "PAUSED. Press 'r' to resume."
        fi
        sleep 1
    done
}

######################## keyboard_controls() ###############################
# Reads single keypresses in a non-blocking manner and interprets them as commands.
# Key bindings:
#   q: Quit; p: Pause; r: Resume; n: Increase depth; N: Decrease depth;
#   m: Toggle display mode; h: Show help; v: Show version/diagnostics.
###############################################################################
keyboard_controls() {
    # Set terminal to raw mode for non-blocking input
    stty -echo -icanon time 0 min 0
    while true; do
        key=$(dd bs=1 count=1 2>/dev/null)
        if [ -n "$key" ]; then
            case "$key" in
                q)
                    cleanup_and_exit
                    ;;
                p)
                    PAUSED=true
                    ;;
                r)
                    PAUSED=false
                    ;;
                n)
                    (( CURRENT_DEPTH++ ))
                    ;;
                N)
                    if (( CURRENT_DEPTH > 1 )); then
                        (( CURRENT_DEPTH-- ))
                    fi
                    ;;
                m)
                    if [ "$DISPLAY_MODE" = "graphical" ]; then
                        DISPLAY_MODE="text"
                    else
                        DISPLAY_MODE="graphical"
                    fi
                    ;;
                h)
                    show_help
                    ;;
                v)
                    show_diagnostics
                    ;;
            esac
        fi
        sleep 0.1
    done
}

######################## Main Script Execution ###############################
init_vars "$1"        # Set MONITOR_DIR to first argument or current directory
signal_handlers       # Setup clean termination traps

# Launch background processes for parallel tasks:
monitor_inotify &      # Start monitoring filesystem events via inotifywait
monitor_io &           # Begin polling directory size changes at CURRENT_DEPTH
calculate_data_rate &  # Compute I/O rate from STATS_FILE
keyboard_controls &    # Listen for key bindings in the background

# Display output in the foreground based on current mode.
while true; do
    if [ "$DISPLAY_MODE" = "graphical" ]; then
        graphical_output
    else
        text_output
    fi
    sleep 1
done
