#!/bin/bash

# Optimized directory I/O monitoring script
# Version: v0.1.5.3_optimized
# Date: April 2, 2025

# Constants and configuration
readonly VERSION="v0.1.5.3_optimized"
readonly VDATE="April 2, 2025"
readonly MB=$((1024*1024))
readonly GB=$((1024*1024*1024))
readonly TB=$((1024*1024*1024*1024))
readonly INOTIFY_LOG="/dev/shm/inotify.lg"
readonly INOTIFY_PART_LOG="/dev/shm/inotify_part.lg"
readonly LOG_LIMIT_KB=4
readonly DISPLAY_LIMIT=15

# Signal handling setup
setup_signals() {
    local sig
    for sig in TERM INT HUP; do
        trap "sigterm_msg $sig" "$sig"
    done
}

sigterm_msg() {
    tput cup 50 0
    echo -e "$1 received, press 'q' or 'Q' to exit dirIO script \033[0K"
}

# Validate directory argument
validate_directory() {
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi

    if [[ "$1" =~ ^(-h|--help|-?|/\?)$ ]]; then
        show_help
        exit 0
    fi

    if [[ ! -d "$1" || "$1" == "/" ]]; then
        echo "Error: Invalid directory path or root filesystem not recommended"
        show_usage
        exit 1
    fi

    directory="$1"
}

show_usage() {
    echo "Usage: $0 <directory_to_monitor>"
}

show_help() {
    echo -e "\nDirectory I/O Monitor Help:"
    echo "Keys: search tree level == 'N'up 'n'dn"
    echo "      output mode       == 'm'"
    echo "      pause             == 'p'"
    echo "      resume            == ' ' or 'r'"
    echo "      clear screen      == 'c' or 'C'"
    echo "      help              == 'h' or 'H' or '?'"
    echo "      quit              == 'q' or 'Q'"
    echo -e "\nVersion: $VERSION\nDate: $VDATE"
}

# Initialize variables
init_vars() {
    pid_=$$
    start_date=$(date)
    start_time=$(date +%s)
    paused=false
    mode=1
    n_=10
    n2_=0
    d_=0
    cntr1=1
    cntr2=1
    rnd_=0
    
    # Get filesystem block size
    blksz=$(stat -f -c '%S' "$directory")
    
    # Calculate directory depth
    base_path=$(grep -o '/' <<< "$directory" | wc -l)
    full_path=$(find "$directory" -type d -printf '%d\n' | sort -rn | head -1)
    depth_=$((base_path + full_path - 1))
    n_=$depth_
    
    # Count files and directories
    flnr_=$(find "$directory" -mindepth 0 -maxdepth 9 -type f | wc -l)
    drnr_=$(find "$directory" -mindepth 0 -maxdepth 9 -type d | wc -l)
    
    # Initialize directory size arrays
    dir_size=$(calculate_dir_size "$directory")
    dir_size_du=$(du -sb "$directory" | awk '{print $1}')
    start_dir_size=$dir_size
    
    for i in $(seq 0 $depth_); do
        start_dir_size_[$i]=$(calculate_dir_size "$directory" $((i+1)) $((i+1)))
        dir_size_[$i]=${start_dir_size_[$i]}
    done
}

calculate_dir_size() {
    local path=$1
    local mindepth=${2:-0}
    local maxdepth=${3:-0}
    
    find "$path" -mindepth "$mindepth" -maxdepth "$maxdepth" -type f,d -printf '%s\n' | 
        awk '{s+=$1} END {print s+0}'
}

# Cursor positioning
posYX() {
    tput cup "$1" "$2"
    [[ "$3" -ne 1 ]] && echo -en "\e[?25l" || echo -en "\e[?25h"
}

# Main monitoring functions
monitor_io() {
    # Check inotify log
    if [[ -s "$INOTIFY_LOG" || "$n_" -ne "$n2_" ]]; then
        process_inotify_log
        update_directory_sizes
    fi
    
    display_io_info
}

process_inotify_log() {
    # Process and limit log size
    sort -u -t' ' -k3,4 "$INOTIFY_LOG" | sort -t' ' -k2 > "$INOTIFY_PART_LOG"
    
    if [[ $(du -b "$INOTIFY_LOG" | cut -f1) -gt $((LOG_LIMIT_KB*1024)) ]]; then
        tail -n 25 "$INOTIFY_LOG" > "${INOTIFY_LOG}.tmp"
        mv "${INOTIFY_LOG}.tmp" "$INOTIFY_LOG"
    fi
    
    # Process log entries
    cntr2=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        llstr_[$((cntr2+2))]=$line
        size__=$(awk '{print $8}' <<< "$line")
        [[ "$size__" =~ ^[0-9]+$ ]] || size__=0
        
        if [[ $size__ -gt ${llstr_[0]} ]]; then
            llstr_[0]=$size__
            llstr_[1]=$line
        fi
        
        if [[ $mode -gt 0 && $cntr2 -le $DISPLAY_LIMIT ]]; then
            echo -e "\033[1K$((cntr2))\t$((llstr_[0]))\t${line:0:127} \033[0K"
        fi
        
        ((cntr2++))
    done < "$INOTIFY_PART_LOG"
    
    for i in $(seq $((cntr2+1)) $((DISPLAY_LIMIT+1)) ); do 
        tput cup $((47+i)) 0
        printf "\033[2K"
    done
}

update_directory_sizes() {
    if [[ "$n_" -ge "$depth_" ]]; then
        current_dir_size=$(calculate_dir_size "$directory")
    else
        current_dir_size=$(calculate_dir_size "$directory" 1 $((n_+1)))
    fi
    
    if [[ "$n_" -eq "$depth_" ]]; then
        for i in $(seq 0 $((depth_-1)) ); do
            dir_size_[$i]=$(calculate_dir_size "$directory" $((i+1)) $((i+1)))
        done
    fi
    
    n2_=$n_
}

display_io_info() {
    # Display basic info
    posYX 0 0 0
    echo "monitoring start: $start_date dirIO.sh $VERSION"
    
    posYX 1 0 0
    echo -n "Directory size (find): $((dir_size/1024)) kB, "
    echo "Directory size (du): $((dir_size_du/1024)) kB, Diff: $(((dir_size-dir_size_du)/1024)) kB"
    
    # Display current directory size info
    posYX 2 0 0
    echo -e "  start_dir_size $start_dir_size $(bc -l <<< "scale=2;$start_dir_size/$MB") MB"
    
    posYX 3 50 0
    echo -n "(subdir_level)"
    
    posYX 4 0 0
    echo -e "  current_dir_size $current_dir_size $(bc -l <<< "scale=2;$current_dir_size/$MB") MB"
    
    posYX 4 50 0
    printf "n: %9.0f %d(%d)" "${dir_size_[$n_]}" "$n_" "$depth_"
}

calculate_data_rate() {
    local now_=$(date +%s)
    local uptime_=$((now_-start_time))
    
    local data_rate_output=$((current_dir_size - dir_size))
    dir_size=$current_dir_size
    
    if [[ $data_rate_output -le 0 ]]; then
        input_sum=$((input_sum + data_rate_output))
    else
        output_sum=$((output_sum + data_rate_output))
    fi
    
    # Display data rate info
    posYX 7 0 0
    echo -e "$(date) start_dir_size $(bc -l <<< "scale=2;$start_dir_size/$MB") MB"
    echo "current_dir_size $(bc -l <<< "scale=2;$current_dir_size/$MB") MB"
    echo "io diff $(bc -l <<< "scale=2;($current_dir_size-$start_dir_size)/$MB") MB"
    
    posYX 10 0 0
    echo "Data I/O rate: $data_rate_output bytes/s ($(bc -l <<< "scale=4;$data_rate_output/$MB") MB/s)"
    echo "Data I/O sum: $input_sum / $output_sum bytes ($(bc -l <<< "scale=2;$input_sum/$MB") / $(bc -l <<< "scale=2;$output_sum/$MB") MB)"
}

graphical_output() {
    local data_io=${data_rate_output#-}
    local relh_pos
    
    # Determine relative height position based on data I/O
    if [[ $data_io -ge $((10*GB)) ]]; then relh_pos=19
    elif [[ $data_io -ge $GB ]]; then relh_pos=16
    elif [[ $data_io -ge $((512*MB)) ]]; then relh_pos=9
    elif [[ $data_io -ge $((128*MB)) ]]; then relh_pos=7
    elif [[ $data_io -ge $MB ]]; then relh_pos=5
    elif [[ $data_io -ge $((512*1024)) ]]; then relh_pos=4
    elif [[ $data_io -ge $((64*1024)) ]]; then relh_pos=3
    elif [[ $data_io -ge $((1*1024)) ]]; then relh_pos=2
    elif [[ $data_io -ge 64 ]]; then relh_pos=1
    else relh_pos=$((data_io/(22*1024)))
    fi
    
    local date_=$(date "+%H:%M:%S.%2N")
    local ioMBps=""
    [[ $data_io -ne 0 ]] && ioMBps=$(bc -l <<< "scale=4;$data_rate_output/$MB")" MB/s"
    
    posYX $((12+cntr1)) 5
    [[ $data_io -eq 0 ]] && echo -e "   \033[1K$date_ \033[0K" || 
        echo -e "\033[1K$date_ $data_rate_output bytes/s $timeBtwIO s \033[0K"
    
    # Display I/O rate and graph
    if [[ $data_rate_output -lt 0 ]]; then
        posYX $((12+cntr1)) 53
        echo -n "$ioMBps"
    fi
    
    [[ $data_rate_output -gt 0 ]] && {
        posYX $((12+cntr1)) 112
        printf "%9s" "$ioMBps"
    }
    
    posYX $((12+cntr1)) 70
    echo -n "|"
    
    [[ $data_rate_output -le 0 ]] && posYX $((12+cntr1)) $((90-relh_pos)) ||
        posYX $((12+cntr1)) 91
    
    for i in $(seq 1 "$relh_pos"); do printf "~"; done
    
    posYX $((12+cntr1)) 90
    echo -n "|"
    posYX $((12+cntr1)) 110
    echo -n "|"
    
    # Display log string
    local llstr__=$(awk '{print $5,$9}' <<< "${llstr_[1]}")
    local llstr___=$(awk '{print $8}' <<< "${llstr_[1]}")
    posYX $((12+cntr1)) 150
    printf "%s  %s " "$llstr__" "$llstr___"
    echo -en "\n \033[0K"
    
    ((cntr1++))
    [[ $cntr1 -gt 23 ]] && cntr1=1 && rnd_=$((1-rnd_))
}

# Main execution
main() {
    setup_signals
    validate_directory "$@"
    init_vars
    
    # Start inotifywait in background
    inotifywait -e create,modify,move,delete -r -m \
                --timefmt "%m/%d/%Y %H:%M:%S" \
                --format "[%T] %w,%f,%e,%x" \
                -o "$INOTIFY_LOG" \
                --exclude "$INOTIFY_LOG" \
                "$directory" >/dev/null 2>&1 &
    pid2_=$!
    
    # Main loop
    while :; do
        calculate_data_rate
        [[ $mode -gt 0 ]] && graphical_output
        monitor_io
        
        # Handle key input
        if read -r -s -t 0.1 -N 1 key; then
            case "$key" in
                "q"|"Q") break ;;
                "p") paused=true ;;
                $'\x0a'|$' '|"r") paused=false ;;
                "m") mode=$(((mode+1)%4)) ;;
                "n") n_=$(((n_-1)%(depth_+1))) ;;
                "N") n_=$(((n_+1)%(depth_+1))) ;;
                "d") d_=$(((d_-1)%6)) ;;
                "D") d_=$(((d_+1)%6)) ;;
                "c"|"C") clear ;;
                "h"|"H"|"?") show_help ;;
            esac
        fi
    done
    
    # Cleanup
    kill -SIGTERM "$pid2_"
    : > "$INOTIFY_LOG"
    : > "$INOTIFY_PART_LOG"
    clear
}

main "$@"
