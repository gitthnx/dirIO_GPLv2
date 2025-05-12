#!/bin/bash
set -euo pipefail

# Directory I/O monitoring script using inotifywait
# Monitors filesystem events, calculates I/O rates, and displays recent activity

# Global variables
declare -r VERSION="0.2.0"
declare -r VDATE="May 2025"
declare -r INOTIFY_LOG="/dev/shm/inotify.lg"
declare -r HUGEFS_GB=35
declare -r MB=$((1024*1024))
declare -r GB=$((1024*1024*1024))
declare -a recent_events=()
declare -i max_events=15
declare -i current_depth=0
declare -i max_depth=0
declare -i start_size=0
declare -i current_size=0
declare -i start_time
declare -i input_sum=0
declare -i output_sum=0
declare -i inotify_pid=0
declare target_directory=""
declare paused=false
declare -i mode=1

# Check for required dependencies
check_dependencies() {
    local deps=("inotifywait" "find" "awk" "tput" "bc")
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || { echo "Error: $dep is required"; exit 1; }
    done
}

# Format bytes to human-readable units
format_bytes() {
    local bytes=$1
    if (( bytes >= GB )); then
        echo "$(bc -l <<< "scale=2; $bytes/$GB") GB"
    elif (( bytes >= MB )); then
        echo "$(bc -l <<< "scale=2; $bytes/$MB") MB"
    elif (( bytes >= 1024 )); then
        echo "$(bc -l <<< "scale=2; $bytes/1024") KB"
    else
        echo "${bytes} B"
    fi
}

# Initialize variables and validate directory
init_vars() {
    if [[ $# -ne 1 || ! -d "$1" || "$1" == "/" ]]; then
        echo "Usage: $0 /directory/to/monitor"
        echo "Error: Valid directory required (not root)"
        exit 1
    fi
    target_directory="$1"
    start_time=$(date +%s)
    
    # Calculate initial directory depth
    max_depth=$(find "$target_directory" -type d -printf '%d\n' | sort -rn | head -1)
    current_depth=$max_depth
    
    # Get initial directory size
    start_size=$(get_directory_size "$current_depth")
    current_size=$start_size
    
    # Check if directory is on large partition
    local prtsz
    prtsz=$(df -k "$target_directory" | awk 'NR==2{print $2}')
    if (( prtsz * 1024 > HUGEFS_GB * GB )); then
        current_depth=1  # Limit depth for large partitions
    fi
}

# Set up signal handlers
signal_handlers() {
    trap cleanup SIGINT SIGTERM
}

# Cleanup function
cleanup() {
    tput clear
    tput cnorm  # Show cursor
    [[ $inotify_pid -ne 0 ]] && kill -SIGTERM "$inotify_pid" 2>/dev/null
    rm -f "$INOTIFY_LOG" /dev/shm/inotify_*.lg 2>/dev/null
    echo "Monitoring stopped: $(date)"
    exit 0
}

# Calculate directory size up to specified depth
get_directory_size() {
    local depth=$1
    find "$target_directory" -mindepth 0 -maxdepth "$depth" -type f -printf '%s\n' \
        | awk '{s+=$1} END {print s}' 2>/dev/null || echo 0
}

# Process inotify event
process_inotify_event() {
    local line=$1
    local event_size=0 event_type path filename
    
    # Parse inotifywait output: [time] path,filename,event,size
    read -r _ path filename event_type size <<< "$line"
    
    # Handle event size
    [[ $event_type =~ DELETE|MOVED_TO ]] && event_size=-${size:-0}
    [[ $event_type =~ CREATE|MODIFY|MOVED_FROM ]] && event_size=${size:-0}
    
    # Update I/O sums
    (( event_size > 0 )) && (( input_sum += event_size ))
    (( event_size < 0 )) && (( output_sum += event_size ))
    
    # Add to recent events buffer
    recent_events=("$line" "${recent_events[@]:0:$((max_events-1))}")
}

# Calculate I/O metrics
calculate_metrics() {
    if [[ $paused == false ]]; then
        local new_size
        new_size=$(get_directory_size "$current_depth")
        local rate=$((new_size - current_size))
        
        if (( rate > 0 )); then
            (( input_sum += rate ))
        elif (( rate < 0 )); then
            (( output_sum += rate ))
        fi
        current_size=$new_size
    fi
}

# Handle user input
handle_input() {
    local key
    if read -r -s -t 0.5 -n 1 key; then
        tput cup 45 5
        echo -e "Key pressed: '$key' \033[0K"
        
        case "$key" in
            q|Q) cleanup ;;
            p|P) 
                paused=true
                mode=0
                ;;
            " "|r|R) 
                paused=false
                mode=1
                ;;
            n) 
                (( current_depth = current_depth > 0 ? current_depth - 1 : max_depth ))
                ;;
            N) 
                (( current_depth = current_depth < max_depth ? current_depth + 1 : 0 ))
                ;;
            c|C) 
                tput clear
                ;;
            h|H|?) 
                mode=0
                display_help
                ;;
            m) 
                (( mode = mode < 3 ? mode + 1 : 0 ))
                ;;
        esac
    fi
}

# Display help message
display_help() {
    tput cup 47 0
    cat << 'EOF'
Keys:
  q/Q: Quit
  p: Pause
  <space>/r/R: Resume
  n/N: Decrease/Increase monitoring depth
  m: Cycle display mode
  c/C: Clear screen
  h/H/?: Show this help
Version: 0.2.0
Date: May 2025
EOF
}

# Update terminal display
update_display() {
    tput clear
    local uptime=$(( $(date +%s) - start_time ))
    local rate=$((current_size - start_size))
    
    # Header
    tput cup 0 0
    echo "Monitoring: $target_directory (Depth: $current_depth/$max_depth)"
    echo "Started: $(date -d "@$start_time")"
    
    # Size and I/O metrics
    tput cup 3 0
    echo "Current Size: $(format_bytes "$current_size")"
    echo "I/O Rate: $(format_bytes "$rate")/s"
    echo "Input Sum: $(format_bytes "$input_sum")"
    echo "Output Sum: $(format_bytes "${output_sum#-}")"
    echo "Status: ${paused:+Paused}Running"
    
    # Recent events
    if (( mode > 0 && ${#recent_events[@]} > 0 )); then
        tput cup 10 0
        echo "Recent Events:"
        local i=0
        for event in "${recent_events[@]}"; do
            (( i++ ))
            tput cup $((10 + i)) 0
            echo "${event:0:120} \033[0K"
        done
    fi
    
    # Help prompt
    tput cup 45 0
    echo "Press 'h' for help \033[0K"
}

# Main function
main() {
    check_dependencies
    init_vars "$@"
    signal_handlers
    
    tput civis  # Hide cursor
    update_display
    
    # Start inotifywait in background
    inotifywait -e create,modify,move,delete -r -m \
        --timefmt "%m/%d/%Y %H:%M:%S" \
        --format "[%T] %w,%f,%e,%x" \
        -o "$INOTIFY_LOG" \
        "$target_directory" >/dev/shm/inotify_stdout.lg 2>/dev/shm/inotify_error.lg &
    inotify_pid=$!
    
    # Main loop
    while true; do
        [[ -s "$INOTIFY_LOG" ]] && while IFS= read -r line; do
            process_inotify_event "$line"
        done < "$INOTIFY_LOG"
        : > "$INOTIFY_LOG"  # Clear log
        
        [[ $paused == false ]] && calculate_metrics
        update_display
        handle_input
        sleep 0.1
    done
}

main "$@"

