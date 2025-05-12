#!/bin/bash

#set -euo pipefail

# Constants
VERSION="1.0.0"
VDATE="May 2025"
LOG_FILE="/dev/shm/inotify_$$.log"
MAX_EVENTS=15
HUGEFS_GB=35
MB=$((1024*1024))
GB=$((1024*1024*1024))

# Global variables
target_directory=""
current_depth=0
max_depth=0
paused=false
mode=1
start_time=0
current_dir_size=0
start_dir_size=0
io_rate_bps=0
cumulative_io=0
recent_events=()
event_index=0
inotify_pid=0
terminal_lines=0
terminal_cols=0

# Check for required commands
check_dependencies() {
    local deps=(inotifywait find awk tput bc)
    for cmd in "${deps[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "Error: $cmd is required but not installed." >&2
            exit 1
        }
    done
}

# Initialize variables and validate directory
init_vars() {
    if [[ $# -ne 1 || ! -d "$1" || "$1" == "/" ]]; then
        echo "Usage: $0 /path/to/directory"
        echo "Error: Provide a valid directory (not root '/')"
        exit 1
    fi

    target_directory="$1"
    start_time=$(date +%s)
    start_dir_size=$(get_directory_size 0)
    current_dir_size=$start_dir_size
    max_depth=$(find "$target_directory" -type d -printf '%d\n' | sort -rn | head -1)
    current_depth=$max_depth
    local prtsz
    prtsz=$(df -k "$target_directory" | awk 'NR==2{print $2}')
    if (( prtsz * 1024 > HUGEFS_GB * GB )); then
        current_depth=1
    fi
    recent_events=()
}

# Set up signal handlers
signal_handlers() {
    trap cleanup SIGINT SIGTERM
}

# Clean up resources on exit
cleanup() {
    if [[ -n "$inotify_pid" && "$inotify_pid" != 0 ]]; then
        kill -SIGTERM "$inotify_pid" 2>/dev/null
    fi
    tput cnorm # Restore cursor
    tput clear
    rm -f "$LOG_FILE"
    echo "Monitoring stopped: $(date)"
    exit 0
}

# Calculate directory size up to specified depth
get_directory_size() {
    local depth=$1
    find "$target_directory" -maxdepth "$depth" -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}'
}

# Format bytes to human-readable string
format_bytes() {
    local bytes=$1
    if (( bytes >= GB )); then
        echo "$(bc -l <<< "scale=2; $bytes/$GB") GB"
    elif (( bytes >= MB )); then
        echo "$(bc -l <<< "scale=2; $bytes/$MB") MB"
    elif (( bytes >= 1024 )); then
        echo "$(bc -l <<< "scale=2; $bytes/1024") KB"
    else
        echo "$bytes B"
    fi
}

# Process a single inotify event
process_inotify_event() {
    local line=$1
    # Parse event: [time] path,file,event,size
    local time path file event size iodir=0
    IFS=',' read -r time path file event size <<< "$(echo "$line" | awk -F'[, ]' '{print $1","$2","$3","$4","$5}')"
    
    case "$event" in
        "CREATE"|"MODIFY"|"MOVED_FROM") iodir=1 ;;
        "DELETE"|"MOVED_TO") iodir=-1 ;;
        *) iodir=0 ;;
    esac
    
    if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
        cumulative_io=$(( cumulative_io + size * iodir ))
    fi
    
    # Store in fixed-size buffer
    recent_events[event_index]="$time $path$file $event $(format_bytes "${size:-0}")"
    event_index=$(( (event_index + 1) % MAX_EVENTS ))
}

# Calculate I/O rates and metrics
calculate_metrics() {
    if [[ "$paused" = true ]]; then
        return
    fi
    
    local now new_size
    now=$(date +%s)
    new_size=$(get_directory_size "$current_depth")
    io_rate_bps=$(( (new_size - current_dir_size) / (now - start_time + 1) ))
    current_dir_size=$new_size
}

# Handle user input
handle_input() {
    local key
    if ! read -r -s -t 0.1 -n 1 key; then
        return
    fi
    
    tput cup $((terminal_lines - 2)) 5
    echo -n "Key pressed: '$key'                    "
    
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
            current_depth=$(( current_depth - 1 ))
            (( current_depth < 0 )) && current_depth=$max_depth
            ;;
        N) 
            current_depth=$(( current_depth + 1 ))
            (( current_depth > max_depth )) && current_depth=0
            ;;
        c|C) 
            tput clear
            ;;
        h|H|?) 
            mode=0
            display_help
            ;;
        m) 
            mode=$(( (mode + 1) % 4 ))
            ;;
    esac
}

# Display help message
display_help() {
    tput cup 10 0
    cat << 'EOF'
Keys:
  q/Q: Quit
  p/P: Pause
  <space>/r/R: Resume
  n/N: Decrease/Increase monitoring depth
  c/C: Clear screen
  m: Cycle display mode
  h/H/?: Show this help
EOF
}

# Update terminal display
update_display() {
    terminal_lines=$(tput lines)
    terminal_cols=$(tput cols)
    
    tput clear
    tput cup 0 0
    echo "Directory I/O Monitor $VERSION ($VDATE)"
    echo "Monitoring: $target_directory (Depth: $current_depth/$max_depth)"
    
    # Metrics
    tput cup 3 0
    echo "Start Size: $(format_bytes $start_dir_size)"
    echo "Current Size: $(format_bytes $current_dir_size)"
    echo "I/O Rate: $(format_bytes $io_rate_bps)/s"
    echo "Cumulative I/O: $(format_bytes $cumulative_io)"
    echo "Status: ${paused:+Paused}${paused:-Running}"
    
    # Recent events
    if (( mode > 0 )); then
        tput cup 10 0
        echo "Recent Events:"
        local i idx
        for (( i=0; i<MAX_EVENTS; i++ )); do
            idx=$(( (event_index - i - 1 + MAX_EVENTS) % MAX_EVENTS ))
            if [[ -n "${recent_events[idx]}" ]]; then
                echo "${recent_events[idx]}" | cut -c 1-$((terminal_cols - 1))
            fi
        done
    fi
    
    # Status line
    tput cup $((terminal_lines - 2)) 0
    echo "Press 'h' for help"
}

# Main function
main() {
    check_dependencies
    init_vars "$@"
    signal_handlers
    tput civis # Hide cursor
    
    # Start inotifywait in coprocess
    coproc INOTIFY { inotifywait -e create,modify,move,delete -r -m \
        --timefmt "%m/%d/%Y %H:%M:%S" --format "[%T] %w,%f,%e,%x" \
        --exclude "$LOG_FILE" "$target_directory" 2>/dev/null; }
    inotify_pid=$INOTIFY_PID
    
    local cycle_count=0
    while true; do
        # Process inotify events
        if [[ -n "${INOTIFY[0]}" && -r "${INOTIFY[0]}" ]]; then
            while read -r -u "${INOTIFY[0]}" line; do
                process_inotify_event "$line"
            done
        fi
        
        # Update metrics every 5 cycles to reduce load
        if (( cycle_count % 5 == 0 )); then
            calculate_metrics
        fi
        
        update_display
        handle_input
        cycle_count=$(( cycle_count + 1 ))
        sleep 0.1
    done
}

# Run main
main "$@"
