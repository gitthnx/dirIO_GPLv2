#!/bin/bash

# Directory to monitor (default: current directory)
MONITOR_DIR="${1:-$(pwd)}"

# Initialize variables
init_vars() {
    declare -g LOG_FILE="/tmp/dir_io_monitor.log"
    declare -g STATS_FILE="/tmp/dir_io_stats.log"
    declare -g TOTAL_SIZE=0
    declare -g PREV_SIZE=0
    declare -g START_TIME=$(date +%s)
    declare -g STOPPED=false
}

# Signal handlers for clean termination
signal_handlers() {
    trap 'echo "Terminating..."; exit 0' SIGINT SIGTERM
}

# Function to process log files efficiently
proc_lgfls() {
    tail -f "$LOG_FILE" | while read -r line; do
        echo "Event: $line"
    done
}

# Monitor directory size changes
monitor_io() {
    while true; do
        [[ "$STOPPED" == "true" ]] && continue
        TOTAL_SIZE=$(du -sb "$MONITOR_DIR" | awk '{print $1}')
        echo "$(date +%s) $TOTAL_SIZE" >> "$STATS_FILE"
        sleep 1
    done
}

# Calculate and display I/O metrics
calculate_data_rate() {
    while true; do
        [[ "$STOPPED" == "true" ]] && continue
        local NOW=$(date +%s)
        local RATE=$(( (TOTAL_SIZE - PREV_SIZE) / (NOW - START_TIME) ))
        PREV_SIZE="$TOTAL_SIZE"
        echo "Current Size: $TOTAL_SIZE bytes, I/O Rate: ${RATE:-0} bytes/sec"
        sleep 1
    done
}

# Graphical output with tput
graphical_output() {
    while true; do
        [[ "$STOPPED" == "true" ]] && continue
        clear
        echo "Monitoring: $MONITOR_DIR"
        echo "Press 'q' to quit, 'p' to pause, 'r' to resume"
        sleep 1
    done
}

# Keyboard interaction
keyboard_controls() {
    while true; do
        read -rn 1 key
        case $key in
            q) exit 0 ;;
            p) STOPPED=true ;;
            r) STOPPED=false ;;
        esac
    done
}

# Start monitoring
init_vars
signal_handlers

# Run all functions in parallel
monitor_io &
calculate_data_rate &
graphical_output &
keyboard_controls
