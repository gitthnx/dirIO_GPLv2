#!/bin/bash
# dirIOMonitor.sh - Real-time Directory I/O Monitor
# Version: v1.0.0_optimized
# Author: Optimized Script by ChatGPT
# Date: May 2025

#############################
#        INIT SECTION       #
#############################

init_vars() {
    version="v1.0.0_optimized"
    depth_level=1
    paused=0
    display_mode=2   # 0=text, 1=graphical, 2=both
    interval=2       # Seconds between rate updates
    huge_fs=34000000000 # 34GB threshold in bytes
    dir_to_monitor="$1"
    total_bytes=0
    prev_size=0
    last_time=$(date +%s)
    event_log="io_events.log"
    rate_log="rate_stats.log"
    rotate_limit=10485760  # 10MB
    trap signal_handlers SIGINT SIGTERM
    mkdir -p /tmp/dirIOMonitor
    clear
}

#############################
#      SIGNAL HANDLING      #
#############################

signal_handlers() {
    echo -e "\n\033[33mTerminating monitoring...\033[0m"
    tput cnorm
    rm -f /tmp/dirIOMonitor/*
    exit 0
}

#############################
#     CALCULATE STATS       #
#############################

calculate_size() {
    find "$dir_to_monitor" -mindepth 1 -maxdepth "$depth_level" -type f -exec stat -c%s {} + 2>/dev/null | awk '{s+=$1} END{print s}'
}

calculate_data_rate() {
    current_time=$(date +%s)
    current_size=$(calculate_size)
    elapsed=$((current_time - last_time))
    delta=$((current_size - prev_size))
    rate=0
    if ((elapsed > 0)); then
        rate=$((delta / elapsed))
    fi
    total_bytes=$((total_bytes + (delta > 0 ? delta : 0)))
    prev_size=$current_size
    last_time=$current_time
}

#############################
#     INOTIFY PROCESSING    #
#############################

proc_lgfls() {
    local event="$1"
    echo "$(date '+%H:%M:%S') - $event" >> "$event_log"
    if (( $(stat -c %s "$event_log") > rotate_limit )); then
        mv "$event_log" "$event_log.old"
        touch "$event_log"
    fi
}

#############################
#     DISPLAY FUNCTIONS     #
#############################

graphical_output() {
    local rate_kb=$((rate / 1024))
    local bar_width=50
    local fill=$((rate_kb * bar_width / 10240)) # scale: 10MB/s = full bar
    fill=$((fill > bar_width ? bar_width : fill))
    bar=$(printf "%-${fill}s" "#" | tr ' ' '#')
    printf "[%-50s] %6d KB/s\n" "$bar" "$rate_kb"
}

display_stats() {
    tput cup 0 0
    tput el
    echo -e "\033[1mDirectory:\033[0m $dir_to_monitor"
    echo -e "\033[1mDepth:\033[0m $depth_level"
    echo -e "\033[1mCurrent Size:\033[0m $((prev_size / 1024 / 1024)) MB"
    echo -e "\033[1mTotal I/O:\033[0m $((total_bytes / 1024 / 1024)) MB"
    echo -e "\033[1mRate:\033[0m $((rate / 1024)) KB/s"
    [[ $display_mode -eq 1 || $display_mode -eq 2 ]] && graphical_output
    echo -e "\033[1mRecent Events:\033[0m"
    tail -n 5 "$event_log"
    echo -e "\033[2m[P]ause  [N/n] Change Depth  [Q]uit\033[0m"
}

#############################
#     MONITOR FUNCTION      #
#############################

monitor_io() {
    inotifywait -r -m -e modify,create,delete,move --format '%w%f %e' "$dir_to_monitor" 2>/dev/null |
    while read -r file event; do
        ((paused)) && continue
        proc_lgfls "$file $event"
    done &
    watch_pid=$!

    while true; do
        ((paused)) && { sleep 1; continue; }
        calculate_data_rate
        display_stats
        sleep "$interval"
    done
}

#############################
#     INTERACTIVE INPUT     #
#############################

read_keys() {
    while true; do
        read -rsn1 key
        case "$key" in
            q|Q) kill $watch_pid; signal_handlers ;;
            p|P) paused=$((1 - paused)) ;;
            N) depth_level=$((depth_level + 1)) ;;
            n) depth_level=$((depth_level > 1 ? depth_level - 1 : 1)) ;;
        esac
    done
}

#############################
#        MAIN ENTRY         #
#############################

main() {
    [[ -z "$1" ]] && { echo "Usage: $0 <directory>"; exit 1; }
    [[ ! -d "$1" ]] && { echo "Error: Directory does not exist."; exit 1; }

    init_vars "$1"
    tput civis
    read_keys &
    monitor_io
}

main "$@"
