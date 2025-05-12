#!/bin/bash

# Set initial variables
DIRECTORY="$1"
PID=$$
PAUSED=false
MODE=1
START_TIME=$(date +%s)
TOTAL_INPUT=0
TOTAL_OUTPUT=0
PREV_SIZE=0
KEY=""
GRAPHICAL_MODE=false
MONITOR_INTERVAL=1  # Interval in seconds for updating the output
ERROR_LOG="/tmp/io_monitor_error.log"

# Function to handle error logs
log_error() {
    echo "$(date) - $1" >> "$ERROR_LOG"
}

# Initial setup: validate directory
if [ -z "$DIRECTORY" ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory $DIRECTORY does not exist."
    log_error "Directory $DIRECTORY does not exist."
    exit 1
fi

# Display help message
show_help() {
    echo "Usage: $0 <directory>"
    echo "Controls:"
    echo "  'p'  - Pause monitoring"
    echo "  'r'  - Resume monitoring"
    echo "  'q'  - Quit the program"
    echo "  'm'  - Change output mode"
    echo "  'c'  - Clear screen"
    echo "  'h'  - Show help"
    echo "Version: 1.0"
}

# Function to get directory size in bytes
get_dir_size() {
    du -sb "$DIRECTORY" | cut -f1
}

# Function to update I/O activity (used with inotifywait)
monitor_io_activity() {
    inotifywait -m -r --format "%w%f %e" "$DIRECTORY" | while read file event
    do
        if [[ "$event" == *"CREATE"* || "$event" == *"MODIFY"* || "$event" == *"DELETE"* ]]; then
            CURRENT_SIZE=$(get_dir_size)
            let "DATA_RATE = CURRENT_SIZE - PREV_SIZE"
            let "TOTAL_INPUT += (DATA_RATE > 0 ? DATA_RATE : 0)"
            let "TOTAL_OUTPUT += (DATA_RATE < 0 ? -DATA_RATE : 0)"
            PREV_SIZE=$CURRENT_SIZE
        fi
    done
}

# Function to calculate and print data rates
calculate_data_rate() {
    CURRENT_SIZE=$(get_dir_size)
    let "DATA_RATE = CURRENT_SIZE - PREV_SIZE"
    let "TOTAL_INPUT += (DATA_RATE > 0 ? DATA_RATE : 0)"
    let "TOTAL_OUTPUT += (DATA_RATE < 0 ? -DATA_RATE : 0)"
    
    # Convert to KB, MB
    RATE_IN_KB=$(($TOTAL_INPUT / 1024))
    RATE_OUT_KB=$(($TOTAL_OUTPUT / 1024))
    RATE_IN_MB=$(($RATE_IN_KB / 1024))
    RATE_OUT_MB=$(($RATE_OUT_KB / 1024))
    
    echo -e "\033[1;32mData Input Rate: ${RATE_IN_KB}KB/s (${RATE_IN_MB}MB/s) \033[0m"
    echo -e "\033[1;31mData Output Rate: ${RATE_OUT_KB}KB/s (${RATE_OUT_MB}MB/s) \033[0m"
}

# Function to handle graphical output (bar chart-like display)
display_graphical_output() {
    DATA_IN_BAR=$(printf '%0.s#' $(seq 1 $((RATE_IN_KB / 10))))
    DATA_OUT_BAR=$(printf '%0.s#' $(seq 1 $((RATE_OUT_KB / 10))))

    echo -e "\033[1;33mData Input: [${DATA_IN_BAR:0:50}] ${RATE_IN_KB}KB/s\033[0m"
    echo -e "\033[1;34mData Output: [${DATA_OUT_BAR:0:50}] ${RATE_OUT_KB}KB/s\033[0m"
}

# Function to handle control key input
handle_keys() {
    read -rsn1 key
    case "$key" in
        q)
            echo "Quitting..."
            exit 0
            ;;
        p)
            PAUSED=true
            echo "Monitoring paused. Press 'r' to resume."
            ;;
        r)
            PAUSED=false
            echo "Monitoring resumed."
            ;;
        m)
            MODE=$((MODE + 1))
            if [ "$MODE" -gt 2 ]; then
                MODE=0
            fi
            ;;
        c)
            clear
            ;;
        h)
            show_help
            ;;
        *)
            ;;
    esac
}

# Main loop: monitor directory size and I/O activity
trap 'echo "Interrupt detected, exiting..."; exit 1' SIGINT
clear

# Start I/O monitoring in the background
monitor_io_activity &

while true; do
    if [ "$PAUSED" = false ]; then
        case "$MODE" in
            0) # Data rate mode
                calculate_data_rate
                ;;
            1) # Graphical mode
                display_graphical_output
                ;;
            *)
                echo "Invalid mode."
                ;;
        esac
    fi

    # Handle key inputs for control
    handle_keys
    sleep $MONITOR_INTERVAL
done
