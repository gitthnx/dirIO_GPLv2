#!/bin/bash
#set -euo pipefail

# Directory I/O Monitor - Optimized Version
# Core functionality preserved with improved structure and efficiency

# Constants and Configuration
readonly VERSION="v1.0.0"
readonly VDATE="May 2025"
readonly HUGE_FS_THRESHOLD=$((35 * 1024 * 1024 * 1024))  # 35GB in bytes
readonly INOTIFY_LOG="/dev/shm/inotify.lg"
readonly EVENT_BUFFER_SIZE=15
readonly REFRESH_INTERVAL=1  # seconds between full scans

# Terminal Control Codes
readonly TC_CLEAR="\033[2J"
readonly TC_RESET="\033[0m"
readonly TC_BOLD="\033[1m"
readonly TC_UL="\033[4m"
readonly TC_RED="\033[31m"
readonly TC_GREEN="\033[32m"
readonly TC_YELLOW="\033[33m"
readonly TC_BLUE="\033[34m"

# Global Variables
declare -a recent_events=()
declare -a dir_size_at_depth=()
declare -i current_depth=0 max_depth=0
declare -i start_dir_size=0 current_dir_size=0
declare -i io_rate=0 total_io_change=0
declare -i paused=0 mode=1  # 0=minimal, 1=normal, 2=verbose
declare target_directory=""
declare inotify_pid=""

# Helper Functions #############################################################

# Display error message and exit
die() {
    printf "${TC_RED}ERROR: %s${TC_RESET}\n" "$1" >&2
    cleanup
    exit 1
}

# Cleanup background processes and temp files
cleanup() {
    [[ -n "$inotify_pid" ]] && kill "$inotify_pid" 2>/dev/null || true
    rm -f "$INOTIFY_LOG" "/dev/shm/inotify_part.lg"
    stty echo  # Ensure cursor is visible
    tput cnorm
    clear
}

# Handle signals
setup_signal_handlers() {
    trap 'cleanup; exit 0' INT TERM
    trap 'paused=1; display_status "PAUSED (Signal received)"' USR1
}

# Check for required commands
check_dependencies() {
    local deps=("inotifywait" "find" "awk" "tput" "bc" "stat")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null; then
            die "Required command '$cmd' not found"
        fi
    done
}

# Format bytes into human-readable string
format_bytes() {
    local bytes=$1
    if (( bytes >= 1024**3 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes/(1024^3)" | bc)"
    elif (( bytes >= 1024**2 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes/(1024^2)" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Calculate directory size at specific depth
get_directory_size() {
    local depth=$1
    find "$target_directory" -mindepth "$depth" -maxdepth "$depth" -type f,d \
        -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

# Initialize directory structure and sizes
init_directory_stats() {
    # Find maximum depth
    max_depth=$(find "$target_directory" -type d -printf '%d\n' | sort -rn | head -1)
    current_depth=$((max_depth > 10 ? 10 : max_depth))  # Limit initial depth
    
    # Initialize size arrays
    dir_size_at_depth=()
    for ((i=0; i<=max_depth; i++)); do
        dir_size_at_depth[i]=$(get_directory_size "$i")
    done
    
    start_dir_size=$(get_directory_size 0)  # Base size
    current_dir_size=$start_dir_size
}

# Process inotifywait output line
process_inotify_event() {
    local line=$1
    
    # Parse event components
    local timestamp=${line%%\] *}; timestamp=${timestamp#*[}
    local path=${line#*\] }; path=${path%%,*}
    local file=${path##*/}
    local event=${line##*,}; event=${event%%,*}
    local size=${line##*,}; size=${size//[^0-9]/}
    
    # Add to recent events buffer
    recent_events=("$(printf "%-12s %-16s %-40s %d" "$timestamp" "$event" "${file:0:40}" "${size:-0}")" "${recent_events[@]:0:$((EVENT_BUFFER_SIZE-1))}")
}

# Main Functions ##############################################################

# Start inotifywait in background
start_inotify_monitor() {
    # Use extended format if available (supports file sizes)
    if inotifywait --help | grep -q '%x'; then
        inotifywait -e create,modify,move,delete -r -m \
            --timefmt "%m/%d/%Y %H:%M:%S" \
            --format "[%T] %w,%f,%e,%x" \
            -o "$INOTIFY_LOG" \
            --exclude "$INOTIFY_LOG" \
            "$target_directory" &>/dev/null &
    else
        inotifywait -e create,modify,move,delete -r -m \
            --timefmt "%m/%d/%Y %H:%M:%S" \
            --format "[%T] %w,%f,%e" \
            -o "$INOTIFY_LOG" \
            --exclude "$INOTIFY_LOG" \
            "$target_directory" &>/dev/null &
    fi
    inotify_pid=$!
}

# Update directory statistics
update_stats() {
    local prev_size=$current_dir_size
    local now=$(date +%s.%N)
    
    # Full scan at reduced frequency for large directories
    if (( $(date +%s) % REFRESH_INTERVAL == 0 )); then
        current_dir_size=$(get_directory_size 0)
    else
        # Just update current depth
        dir_size_at_depth[$current_depth]=$(get_directory_size "$current_depth")
    fi
    
    # Calculate I/O rate
    io_rate=$((current_dir_size - prev_size))
    total_io_change=$((current_dir_size - start_dir_size))
    
    # Process new inotify events
    while IFS= read -r line; do
        process_inotify_event "$line"
    done < <(tail -n 50 "$INOTIFY_LOG" 2>/dev/null)
    
    # Truncate log file periodically
    if (( $(stat -c %s "$INOTIFY_LOG" 2>/dev/null) > 1048576 )); then
        tail -n 100 "$INOTIFY_LOG" > "$INOTIFY_LOG.tmp" && mv "$INOTIFY_LOG.tmp" "$INOTIFY_LOG"
    fi
}

# Display Functions ###########################################################

# Show current status line
display_status() {
    local status=$1
    local cols=$(tput cols)
    tput cup 0 0
    printf "${TC_BOLD}%-${cols}s${TC_RESET}" \
        "Directory I/O Monitor ${VERSION} - ${target_directory} - ${status}"
}

# Show main metrics
display_metrics() {
    local rows cols
    IFS=';' read -sdR -p $'\E[6n' rows cols
    rows=${rows#*[}
    
    tput cup 2 0
    printf "Current Depth: ${TC_BOLD}%d${TC_RESET}/${max_depth} | " "$current_depth"
    printf "Size: ${TC_BOLD}%s${TC_RESET} | " "$(format_bytes "$current_dir_size")"
    printf "I/O Rate: ${TC_BOLD}%s/s${TC_RESET}\n" "$(format_bytes "$io_rate")"
    printf "Total Change: ${TC_BOLD}%s${TC_RESET} | " "$(format_bytes "$total_io_change")"
    printf "Start Size: ${TC_BOLD}%s${TC_RESET}\n" "$(format_bytes "$start_dir_size")"
    
    # Depth size breakdown in verbose mode
    if (( mode >= 2 )); then
        printf "\n${TC_UL}Depth Size Breakdown:${TC_RESET}\n"
        for ((i=0; i<=max_depth && i<10; i++)); do
            printf "  %2d: %12s" "$i" "$(format_bytes "${dir_size_at_depth[$i]}")"
            (( (i+1) % 4 == 0 )) && printf "\n" || printf " | "
        done
        printf "\n"
    fi
}

# Show recent events
display_events() {
    local rows cols
    IFS=';' read -sdR -p $'\E[6n' rows cols
    rows=${rows#*[}
    
    tput cup $((rows - EVENT_BUFFER_SIZE - 5)) 0
    printf "${TC_UL}%-12s %-16s %-40s %s${TC_RESET}\n" "Time" "Event" "File" "Size"
    
    for event in "${recent_events[@]}"; do
        printf "%s\n" "$event"
    done
}

# Show help/controls
display_help() {
    local rows cols
    IFS=';' read -sdR -p $'\E[6n' rows cols
    rows=${rows#*[}
    
    tput cup $((rows - 5)) 0
    printf "${TC_BLUE}Controls:${TC_RESET} "
    printf "[${TC_GREEN}P${TC_RESET}]ause/[${TC_GREEN}R${TC_RESET}]esume "
    printf "[${TC_GREEN}N/n${TC_RESET}]Depth "
    printf "[${TC_GREEN}M${TC_RESET}]ode "
    printf "[${TC_GREEN}C${TC_RESET}]lear "
    printf "[${TC_GREEN}Q${TC_RESET}]uit "
    printf "[${TC_GREEN}?${TC_RESET}]Help\n"
}

# Main display update
update_display() {
    clear
    display_status "$((paused))" "PAUSED" : "RUNNING"")"
    display_metrics
    display_events
    display_help
}

# Handle user input
handle_input() {
    local key
    IFS= read -rs -n1 -t0.1 key || return
    
    case "$key" in
        [pP]) paused=1;;
        [rR]|' ') paused=0;;
        [nN]) ((current_depth = (current_depth + 1) % (max_depth + 1)));;
        [mM]) ((mode = (mode + 1) % 3));;
        [cC]) update_display;;
        [hH]|'?') show_full_help;;
        [qQ]) cleanup; exit 0;;
    esac
}

# Show extended help
show_full_help() {
    clear
    printf "${TC_BOLD}Directory I/O Monitor Help${TC_RESET}\n\n"
    printf "Version: ${VERSION} (${VDATE})\n\n"
    printf "Usage: %s /path/to/directory\n\n" "$0"
    printf "${TC_UL}Key Controls:${TC_RESET}\n"
    printf "  ${TC_GREEN}P${TC_RESET}      - Pause monitoring\n"
    printf "  ${TC_GREEN}R/Space${TC_RESET} - Resume monitoring\n"
    printf "  ${TC_GREEN}N${TC_RESET}      - Increase monitoring depth\n"
    printf "  ${TC_GREEN}n${TC_RESET}      - Decrease monitoring depth\n"
    printf "  ${TC_GREEN}M${TC_RESET}      - Cycle display mode (minimal/normal/verbose)\n"
    printf "  ${TC_GREEN}C${TC_RESET}      - Clear and redraw display\n"
    printf "  ${TC_GREEN}?${TC_RESET}      - Show this help\n"
    printf "  ${TC_GREEN}Q${TC_RESET}      - Quit\n\n"
    printf "Press any key to continue..."
    IFS= read -rs -n1
    update_display
}

# Main Execution ##############################################################

main() {
    # Check arguments
    if [[ $# -ne 1 || ! -d "$1" ]]; then
        die "Usage: $0 /path/to/directory"
    fi
    
    if [[ "$1" == "/" ]]; then
        die "Monitoring root filesystem is not recommended"
    fi
    
    target_directory=$1
    
    # Initial setup
    check_dependencies
    setup_signal_handlers
    init_directory_stats
    start_inotify_monitor
    
    # Hide cursor and set up terminal
    tput civis
    stty -echo
    
    # Main loop
    while true; do
        if (( !paused )); then
            update_stats
        fi
        
        update_display
        handle_input
        sleep 0.5
    done
}

main "$@"
