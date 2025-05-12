#!/bin/bash

### https://lmarena.ai/ -> 'Direct Chat'

########################################################################
# Directory I/O Monitor - Optimized Bash Script
# Version: 1.0.0
# Author: OpenAI ChatGPT
# Description: Monitors directory I/O activity using inotifywait with
#              interactive controls, graphical/text modes, depth level
#              navigation, and real-time stats.
########################################################################

##########################
# Configuration Defaults #
##########################
TARGET_DIR="${1:-.}"
LOG_FILE="/tmp/dir_io_monitor.log"
MAX_LOG_SIZE=10485760          # 10MB
DEFAULT_DEPTH=2
SLEEP_INTERVAL=2               # Seconds between samples

# Color settings for output
COLOR_TITLE="\e[1;36m"
COLOR_RESET="\e[0m"

##########################
# Global Variable Setup  #
##########################
declare -A size_at_depth       # Holds directory sizes by depth
declare -a event_log           # Recent file events
declare -i current_depth=$DEFAULT_DEPTH
declare -i running=1
declare -i paused=0
declare -i cumulative_io=0
declare mode="text"

##########################
# Function: init_vars    #
##########################
init_vars() {
    : > "$LOG_FILE"
    cumulative_io=0
    current_depth=$DEFAULT_DEPTH
    event_log=()
    trap signal_handlers SIGINT SIGTERM
}

#################################
# Function: signal_handlers     #
#################################
signal_handlers() {
    echo -e "\n${COLOR_TITLE}Terminating... Cleaning up.${COLOR_RESET}"
    kill "$INOTIFY_PID" 2>/dev/null
    tput cnorm
    stty echo
    exit 0
}

#################################
# Function: proc_lgfls          #
# Process inotify log entries  #
#################################
proc_lgfls() {
    while read -r line; do
        timestamp=$(date +'%H:%M:%S')
        event_log+=("[$timestamp] $line")
        (( ${#event_log[@]} > 10 )) && event_log=("${event_log[@]:1}")
    done < <(inotifywait -m -r -e modify,create,delete,move "$TARGET_DIR" 2>/dev/null)
}

#################################
# Function: monitor_io          #
# Monitor directory size       #
#################################
monitor_io() {
    local prev_size=0 curr_size=0 delta=0

    while (( running )); do
        if (( !paused )); then
            curr_size=$(calculate_size "$TARGET_DIR" "$current_depth")
            delta=$((curr_size - prev_size))
            prev_size=$curr_size
            (( delta > 0 )) && cumulative_io=$((cumulative_io + delta))
            calculate_data_rate "$delta"
            graphical_output "$curr_size" "$delta"
        fi
        sleep "$SLEEP_INTERVAL"
    done
}

######################################
# Function: calculate_size           #
# Uses find + du for performance     #
######################################
calculate_size() {
    local dir="$1"
    local depth="$2"
    find "$dir" -mindepth 1 -maxdepth "$depth" -type f -exec du -b {} + 2>/dev/null | awk '{sum += $1} END {print sum}'
}

######################################
# Function: calculate_data_rate      #
######################################
calculate_data_rate() {
    local bytes="$1"
    IO_RATE=$(echo "scale=2; $bytes / 1024 / 1024 / $SLEEP_INTERVAL" | bc)
}

######################################
# Function: graphical_output         #
######################################
graphical_output() {
    local size="$1"
    local delta="$2"

    clear
    tput cup 0 0
    echo -e "${COLOR_TITLE}Directory I/O Monitor - ${TARGET_DIR}${COLOR_RESET}"
    echo "------------------------------------------------------"
    echo "Depth Level       : $current_depth"
    echo "Current Size      : $(numfmt --to=iec $size)"
    echo "I/O Rate          : ${IO_RATE:-0.00} MB/s"
    echo "Cumulative I/O    : $(numfmt --to=iec $cumulative_io)B"
    echo "Events (last 10):"
    for (( i=0; i<${#event_log[@]}; i++ )); do
        echo "  ${event_log[$i]}"
    done
    echo "------------------------------------------------------"
    echo "[N/n] Increase/Decrease Depth | [P]ause | [M]ode | [Q]uit | [?]Help"
}

######################################
# Function: interactive_controls     #
######################################
interactive_controls() {
    while read -rsn1 key; do
        case "$key" in
            N) ((current_depth++));;
            n) ((current_depth > 1)) && ((current_depth--));;
            p|P) paused=$((1 - paused));;
            m|M) [[ "$mode" == "text" ]] && mode="graphical" || mode="text";;
            q|Q) signal_handlers;;
            ?) display_help;;
        esac
    done
}

######################################
# Function: display_help             #
######################################
display_help() {
    echo -e "\n${COLOR_TITLE}Help - Key Bindings${COLOR_RESET}"
    echo "---------------------------------------------"
    echo "N         : Increase directory depth"
    echo "n         : Decrease directory depth"
    echo "P         : Pause/Resume monitoring"
    echo "M         : Toggle text/graphical mode"
    echo "Q         : Quit application"
    echo "?         : Show this help screen"
    read -rp "Press any key to continue..." -n1
}

######################################
# Function: rotate_log               #
######################################
rotate_log() {
    [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -ge $MAX_LOG_SIZE ]] && mv "$LOG_FILE" "$LOG_FILE.old"
    : > "$LOG_FILE"
}

######################################
# Function: start_monitoring         #
######################################
start_monitoring() {
    tput civis
    inotifywait -m -r -q --format '%w%f %e' -e modify,create,delete,move "$TARGET_DIR" >> "$LOG_FILE" &
    INOTIFY_PID=$!
    tail -n 0 -F "$LOG_FILE" | proc_lgfls &
    interactive_controls &
    monitor_io
}

############
# MAIN     #
############
init_vars
start_monitoring
