#!/bin/bash

# Signal handling functions
sigterm_handler() {
    # Handle signal trapping with dynamic signal assignment
    signl="$1" ; shift
    for sig ; do
        trap "$signl $sig" "$sig"
    done
}

sigterm_msg() {
    # Display signal received message at specific screen position
    posYX 50 0 0
    echo -e "$1 received, press 'q' or 'Q' to exit dirIO script \033[0K"
}

# Initial screen clear and directory validation
clear
avail=$( [ ! -d "$1" ] || [ -z "$1" ] && echo "0" || echo "1" ) # Check if directory exists and is provided
if [ "$1" == "/" ]; then
    avail=0
    echo; echo "*** no root fs io monitoring recommended ***" # Prevent monitoring root filesystem
fi

# Argument validation
if [ "$#" -eq "0" ] || [ "$#" -gt "1" ]; then
    echo " \$# $#   \$1 $1  directory path available $avail"
    echo "Usage: $0 '-h' | '--help' | '-?' | '/?'"
    key="q" # Default to quit if invalid arguments
fi

# Help menu definition with ANSI escape codes for formatting
keysdef="                                             \033[0K\n\
       keys: search tree level == 'n'        \033[0K\n\
             output mode       == 'm'        \033[0K\n\
             pause             == 'p'        \033[0K\n\
             resume            == ' ' or 'r' \033[0K\n\
             clear screen      == 'c' or 'C' \033[0K\n\
             help              == 'h' or 'H' or '?'  \033[0K\n\
             quit              == 'q' or 'Q' \033[0K\n\
                                             \033[0K\n\
       version $version                      \033[0K\n\
       $vdate                                \033[0K\n\
                                             \033[0K"

# Exit if directory invalid or help requested
if [ -z "$1" ] || [ "$avail" != "1" ] || [ "$#" -ne 1 ]; then
    echo "Usage: $0  /directory/to/monitor"
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "-?" ] || [ "$1" == "/?" ]; then
        echo -e -n "$keysdef"
    fi
    echo
    exit 1
fi


# Variable initialization
version="v0.1.5.2"
vdate="March 29, 2025"
directory="$1"
inotfy_pth="/dev/shm/inotify.lg" # Path for inotify log
pid_="$$" # Current process ID
start_date=$(date)
start_time=$(date +%s) # Start time in seconds
timeNext=0
timePrev=$(date +%s.%2N) # Previous timestamp with nanoseconds
llstr=""
#
paused=false
mode=1 # Display mode (0-3)
n_=10 # Directory depth level
n2_=0 # Previous depth level
cntr1=1 # Counter for graphical output
cntr2=1 # Counter for inotify output
winh_=1 # Window height percentage
rnd_=0 # Rounding toggle
# arrays
dir_size_=($(seq 0 10)) # Array for directory sizes at different depths
start_dir_size_=($(seq 0 10 1))
llstr_=($(seq 0 50 1))
#
rate_in=0 rate_out=0
sum_in=0 sum_out=0
total_input=0 total_output=0
# constants
MB=$((1024*1024))
GB=$((1024*1024*1024))
TB=$((1024*1024*1024*1024))

### Cursor positioning function
posYX() {
    ROW=$1
    #tput cup "${ROW#*[}" "$2" # Move cursor to specified row and column
    tput cup 44 50
    echo -e "row $1 col $2   "        #\033[0K"
    tput cup 45 0
    tput cup "$1" "$2"
    [ "$3" -ne "1" ] && echo -e "\e[?25l" || echo -e "\e[?25h" # Hide/show cursor
}

headln() {
  posYX 0 0 0
  echo "monitoring start: $start_date"" dirIO.sh $version"
  posYX 1 100 0
  tput cup 1 100
  echo "directory size (find -type cmd) $((dir_size/1024)) kB, directory size (du cmd) $((dir_size_du/1024)) kB"
  echo
}

path_depth() { echo "${*#/}" | awk -F/ '{print NF}'; }

update_nlevel_usage() {
  dir_size_[$i_]=$(find "$directory" -mindepth $1 -maxdepth $1 -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
}


### initialize variables/arrays
init_vars() {
    base_path=`echo "$directory" | grep -o '/' - | wc -l`
    full_path=`find $directory -type d -printf '%d\n' | sort -rn | head -1`
    ##full_path_=`find $directory -type d | sed 's|[^/]||g' | sort | tail -n1 | wc -c`
    echo $full_path
    echo $base_path
    depth_=$((base_path+full_path-1))
    echo $depth_
    n_=$((depth_))


    # Initial directory size calculations
    dir_size=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}') # Size using find
    dir_size_du=$(du -sb "$directory" | awk '{print $1}') # Size using du
    start_dir_size=$((dir_size_du))
    start_dir_size_[10]=$((dir_size_du))

    start_dir_size_[0]=$(find "$directory" -mindepth 1 -maxdepth 1 -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
    dir_size_[0]=$(( start_dir_size_[0]/(1*1) ))
    dir_sum=$((dir_size_[0]))
    #for i_ in {1..9}; do
    for i_ in $(seq 1 $((depth_)) ); do
    ###for i_ in {0.."$full_path"}; do
    start_dir_size_[$i_]=$(find "$directory" -mindepth $((i_+1)) -maxdepth $((i_+1)) -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
    dir_size_[$i_]=$(( start_dir_size_[$i_]/(1*1) ))
    dir_sum=$((dir_sum+dir_size_[$i_]))
    done

    current_dir_size=$((dir_size))

    #sleep 1
    clear
}






### I/O monitoring function
monitor_io() {

    # Check inotify log and display recent changes
    if [ "$(du "$inotfy_pth" | cut -f 1)" -gt "0" ] || [ "$n_" -ne "$n2_" ]; then
        posYX 47 0 0
        cat "$inotfy_pth" | tail -n 15 > /dev/shm/inotify_part.lg
        cp /dev/shm/inotify_part.lg "$inotfy_pth"
        cntr2=2
        llstr_[0]=0
        llstr_[1]=""
        #if [ "$winh_" -gt "50" ] && [ "$mode" -gt "0" ]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                len_=$(echo "$line" | wc -c)
                size__=$(echo $line | cut -d ' ' -f 8)
                if [ "$size__" != "''|*[!0-9]*" ]; then size__=0; fi
                #llstr=$(echo -e -n $line | head -c 100)
                #llstr_[$((cntr2))]=$(echo "$line")
                if [ $((size__)) -gt $((llstr_[0])) ]; then
                  llstr_[0]=$(echo $line | cut -d ' ' -f 8)
                  llstr_[1]=$(echo -n "$line")
                fi
                if [ $mode -gt 0 ]; then echo -e "\033[1K\t$(echo "$line" | tail -c 127) \033[0K"; fi
                cntr2=$((cntr2+1))
            done < "/dev/shm/inotify_part.lg"
            for i in $(seq 1 2); do printf "\033[2K"; done
        #fi



        # Update directory size based on depth level
        if [ "$n_" -ge "$depth_" ]; then
            current_dir_size=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
        else
            posYX 43 70 0
            echo " $n_ $n2_   "
            current_dir_size=$(find "$directory" -mindepth 1 -maxdepth $((n_+1)) -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
            sleep 0.01
        fi
        posYX 2 0 0
        #dir_size_[$n_]=$current_dir_size
        dir_size_du=$((current_dir_size))

        posYX 2 0 0
        #var=$(echo scale=3; $dir_sum/(1024*1024) | bc)
        var1=$(bc -l <<< "scale=2;$dir_sum/(1024*1024)")
        echo -e "  start_dir_size $dir_sum $var1 MB "
        posYX 3 50 0
        tput cup 3 50
          printf "(subdir_level)"
        tput cup 3 75
        #for i in $(seq 0 $((10)) ); do echo -e -n "${start_dir_size_[$i]}_($i) \033[0K"; done
        for i in $(seq 0 $((10)) ); do printf "%12.0f_(%d)" $((start_dir_size_[$i])) $((i)); done

        if [ "$n_" -lt "$depth_" ]; then
          dir_size_[$n_]=$(find "$directory" -mindepth $((n_+1)) -maxdepth $((n_+1)) -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}' 2> /dev/null )
          sleep 0.01
        elif [ "$n_" -eq "$depth_" ]; then
          for i in $(seq 0 $((depth_-1)) ); do
            dir_size_[$i]=$(find "$directory" -mindepth $((i+1)) -maxdepth $((i+1)) -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}' 2> /dev/null )
          done
        fi

        var1=$(bc -l <<< "scale=2;$((dir_size_[0]))/(1024*1024)")
        tput cup 4 0
        echo -e "current_dir_size $((dir_size_[0])) $var1 MB "
        tput cup 4 50
        #echo -e "n level: $n_"   "$((dir_size_[$n_])) \033[0K"
        printf "n: %9.0f %d(%d)" $((dir_size_[$n_])) $n_ $depth_
        tput cup 4 75
        #for i in $(seq 0 $((10)) ); do echo -e -n "${dir_size_[$i]}_($i) \033[0K"; done
        #awk '{printf "0x%x%s0x%x\n", $1, OFS, $2}' OFS='\t' ${dir_size_[@]}
        for i in $(seq 0 $((10)) ); do printf "%12.0f_(%d)" $((dir_size_[$i])) $((i)); done

        #tput cup 4 200
        ##posYX 4 110 0
        #echo -e -n "${dir_size_[@]}"

        n2_=$((n_))

    else
        posYX 45 50 0
        echo -e "no io"
    fi
    tput cup 65 0




    posYX 44 20 0
    # Window size information
    #winsize_=$(xwininfo -id "$(xdotool getactivewindow)" | awk -F ':' '/Width/ || /Height/{print $2}' | tr '\n' ' ')
    #winname_=$(xwininfo -id "$(xdotool getactivewindow)" -all | awk -F ':' '/xwininfo/ {print $3 $4}')
    #winh=$(xwininfo -id "$(xdotool getactivewindow)" | awk -F ':' '/Height/{print $2}' | tr '\n' ' ')
    #winh_=$(( (winh-400)*100/winh ))
    #echo -e "  winsize $winsize_  $winh_  $winname_ \033[0K"
    tput cup 44 0
    lns=$(tput lines)
    cols=$(tput cols)
    echo -e "  tput lines $lns cols $cols \033[0K"
    tput cup 65 0

}

# Data rate calculation function
calculate_data_rate() {
    #local rate_in=0 rate_out=0

    posYX 7 0 0
    printf '\e[150;7;3m' # Highlighted text
    echo -e "$(date)   start_dir_size $((start_dir_size/1024)) kB  current_dir_size $((current_dir_size/1024)) kB  io diff $(( ($current_dir_size-$start_dir_size)/(1024*1024) )) MB \033[0K"
    n__=$(([ "$n_" -eq "0" ] && echo -n "base dir level") || ([ "$n_" -eq "1" ] && echo -n "1 dir level") || ([ "$n_" -eq "$depth_" ] && echo -n "all dir levels") || echo -n "$n_ dir levels")
    echo -e "pid_$pid_ err_$err m_$mode n_$n_ for ($n__ of) $directory ($uptime_) \033[0K"
    printf '\e[0m' # Reset formatting

    now_=$(date +%s)
    uptime_=$((now_-start_time))


    data_rate_output=$((current_dir_size - dir_size))
    echo -e "  data_io_rate $data_rate_output B/s \033[0K"
    dir_size=$((current_dir_size))
    if [ "$data_rate_output" -le 0 ]; then
        input_sum=$((input_sum+data_rate_output))
        in_sum_float=$(echo "scale=3; $input_sum/(1024*1024)" | bc)
    else
        output_sum=$((output_sum+data_rate_output))
        out_sum_float=$(echo "scale=3; $output_sum/(1024*1024)" | bc)
    fi

    echo -e "  data io rate: $data_rate_output bytes/s  $(echo "scale=4; $data_rate_output/1024/1024" | bc) MB/s \033[0K"
    echo -e "  data io sum: $input_sum  $output_sum bytes  $(echo "scale=6; $input_sum/1024/1024" | bc)  $(echo "scale=6; $output_sum/1024/1024" | bc) MB   \033[0K"
    echo -e "  data io sum: $in_sum_float   $out_sum_float MB ($uptime_) \033[0K"
    printf "\033[2K"

    # Display detailed rates if mode > 2
    if [ "$sum_in" -ge "$((MB))" ]; then
        sum_in_="$((sum_in/$MB))MB"
    elif [ "$sum_in" -ge "1024" ]; then
        sum_in_="$((sum_in/1024))kB"
    else
        sum_in_="$sum_in B"
    fi

# Calculate I/O rates
    rate_io=$((current_dir_size - dir_size_du))
    if [ "$rate_io" -gt 0 ]; then
        rate_in=$((rate_in+rate_io))
        sum_in=$((sum_in+rate_in))
    elif [ "$rate_io" -lt 0 ]; then
        rate_out=$((rate_out+rate_io))
        sum_out=$((sum_out+rate_out))
    fi
    if [ "$rate_io" -ne 0 ]; then
        timeNext="$(date +%s.%2N)"
        timeBtwIO=$(echo "$timeNext-$timePrev" | bc)
        timePrev=$timeNext
    fi
    dir_size_du=$((current_dir_size))

    if [ "$mode" -eq "0" ]; then
      tput cup 46 50 0
      echo -e "press key 'm' for to continue graphical output (now mode=='0')"
    elif [ "$mode" -ge "2" ]; then
      tput cup 46 50 0
      echo -e "\033[0K"
      posYX 40 0 0
      echo -e "  input data avg_rate/analysis_runtime:  $((input_sum/uptime_))  bytes/sec\t $(($input_sum/1024/uptime_))  kB/s\t  $(echo "scale=6; $input_sum/1024/1024/$uptime_" | bc) MB/s \033[0K"
      echo -e "  output data avg_rate/analysis_runtime: $((output_sum/uptime_)) bytes/sec\t $(($output_sum/1024/uptime_)) kB/s\t  $(echo "scale=6; $output_sum/1024/1024/$uptime_" | bc) MB/s \033[0K"
    else
        for i in $(seq 40 41); do posYX "$i" 0 0; printf "\033[2K"; done
    fi

    IFS=';' read -sdR -p $'\E[6n' ROW COL # Get cursor position
    pos=${ROW#*[}

}

# Graphical output function
graphical_output() {
    posYX 12 0 0
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    gpos=${ROW#*[}
    pos=$((gpos+cntr1))

    data_io=$((${data_rate_output#-}))
    if [ ${data_rate_output#-} -ge $((10*1024*1024*1024)) ]; then relh_pos=19; elif [ $data_io -ge $((1024*1024*1024)) ]; then relh_pos=16; elif [ $data_io -ge $((1024*1024*1024)) ]; then relh_pos=11; elif [ $data_io -ge $((512*1024*1024)) ]; then relh_pos=9; elif [ $data_io -ge $((128*1024*1024)) ]; then relh_pos=7; elif [ $data_io -ge $((1024*1024)) ]; then relh_pos=5; elif [ $data_io -ge $((512*1024)) ]; then relh_pos=4; elif [ $data_io -ge $((64*1024)) ]; then relh_pos=3; elif [ $data_io -ge $((1*1024)) ]; then relh_pos=2; elif [ $data_io -ge $((64)) ]; then relh_pos=1; else relh_pos=$((data_io/(22*1024)));  fi   #relh_pos=$((data_io/255));
    #relh_pos=$([ "$data_io" -ge $((10*1024*1024*1024)) ] && echo 19 || [ "$data_io" -ge $((1024*1024*1024)) ] && echo 16 || [ "$data_io" -ge $((512*1024*1024)) ] && echo 9 || [ "$data_io" -ge $((128*1024*1024)) ] && echo 7 || [ "$data_io" -ge $((1024*1024)) ] && echo 5 || [ "$data_io" -ge $((512*1024)) ] && echo 4 || [ "$data_io" -ge $((64*1024)) ] && echo 3 || echo $((data_io/(22*1024))))

    date_=$([ "$rnd_" -eq "1" ] && date "+%H:%M:%S.%3N" || date "+%H:%M:%S.%2N")
    tput cup "$pos" 5

    [ "$data_io" -eq "0" ] && ioMBps='' || ioMBps=$(echo "scale=4; $data_rate_output/1024/1024" | bc)" MB/s"

    [ "$data_io" -ne "0" ] && echo -e "\033[1K$date_ $data_rate_output bytes/s $timeBtwIOs \033[0K" || echo -e "   \033[1K$date_ \033[0K"
    #[ "$data_rate_output" -lt 0 ] && tput cup "$pos" 53 && echo -e -n "$ioMBps" || [ "$data_rate_output" -gt 0 ] && tput cup "$pos" 112 && printf "%9s" $ioMBps
    if [ "$data_rate_output" -lt 0 ]; then tput cup "$pos" 53; echo -e -n "$ioMBps"; fi
    [ "$data_rate_output" -gt 0 ] && tput cup "$pos" 112 && printf "%9s" $ioMBps

    tput cup "$pos" 70; echo -e -n "|"
    [ "$data_rate_output" -le 0 ] && tput cup "$pos" $((90-relh_pos)) || tput cup "$pos" 91
    for i in $(seq 1 "${relh_pos#-}"); do printf "~"; done
    tput cup "$pos" 90; echo -e -n "|"
    tput cup "$pos" 110; echo -e -n "|"
    #tput cup "$pos" 150; printf " %.100s\n" $llstr; echo -e "\033[0K";
    llstr__=$(echo ${llstr_[1]} | cut -d ' ' -f 5,9)
    llstr___=$(echo ${llstr_[1]} | cut -d ' ' -f 8)
    #tput cup "$pos" 150; echo -e -n "$llstr__\n"; echo -e "\033[0K";
    tput cup "$pos" 150; printf "%s  %s " $llstr__ $llstr___; echo -e -n "\n \033[0K";

    cntr1=$((cntr1+1))
    [ "$cntr1" -gt "23" ] && cntr1=1 && rnd_=$((1-rnd_))
}











# Start inotifywait background process
# git clone https://github.com/gitthnx/inotify-tools
# cd inotify-tools; ./autogen.sh; mkdir build; cd build; ../configure; make -j12; cp src/inotifywait /dev/shm; cp src/.libs -R /dev/shm; cd ../..;
/dev/shm/inotifywait -e create,modify,move,delete -r -m --timefmt "%m/%d/%Y %H:%M:%S" --format "[%T] %w,%f,%e,%x" -o "$inotfy_pth" --exclude /dev/shm/inotify.lg "$directory" 1> /dev/shm/inotify.lg 2> /dev/shm/inotify.lg &
pid2_=$!
echo "pid of inotifywait&: $!" > /dev/shm/inotify_.msg

# init variables
init_vars

# Startup display
#posYX 3 0 0
headln

sleep 0.01

posYX 1 0 0

# Main monitoring loop
while true; do
    if [ "$paused" = false ]; then
        calculate_data_rate # Issues: hard links, permissions, 'No such file or directory'
        [ "$mode" -gt "0" ] && graphical_output
        monitor_io
    fi

    read -r -s -t 0.1 -N 1 key # Non-blocking key input
    posYX 45 0 0
    case "$key" in
        "q"|"Q")
            paused=true
            clear
            posYX 3 0 0
            echo "monitoring stop: $(date) uptime on I/O analysis: "$uptime_"s"
            echo -e -n "  key(s) pressed: '$key'"
            echo
            posYX 7 0 0
            ps ax | grep inotify | grep -v 'grep'
            kill -SIGTERM "$pid2_"
            IFS=';' read -sdR -p $'\E[6n' ROW COL # Get cursor position
            pos=${ROW#*[}
            sleep 1
            for i in $(seq  $((pos-1))  $(tput lines) 1 ); do posYX "$i" 0 0; printf "\033[2K"; done

            posYX 7 0 0
            ps aux | grep inotify | grep -v 'grep'
            IFS=';' read -sdR -p $'\E[6n' ROW COL # Get cursor position
            pos=${ROW#*[}
            for i in $(seq  $((pos-1))  $(tput lines)); do tput cup "$i" 0; printf "\033[2K"; done

            #manually SIGTERM inotifywait?

            sleep 0.01
            posYX 0 0 1
            sleep 1
            clear
            break
            ;;
        "p")
            paused=true
            mode_=$((mode))
            tput cup 46 50
            #posYX 46 50
            echo -e "directory I/O analysis paused, enter <space> or key 'r' to resume \033[0K"
            ;;
        $'\x0a'|$' '|r)
            mode=$((mode_))
            paused=false
            tput cup 46 50
            #posYX 46 50 0
            echo -e "directory I/O analysis resumed \033[0K"
            for i in $(seq 45 55); do posYX "$i" 0 0; printf "\033[2K"; done
            ;;
        "m")
            mode=$((mode+1))
            [ "$mode" -gt "3" ] && mode=0
            ;;
        "n")
            n_=$((n_+1))
            [ "$n_" -gt "$depth_" ] && n_=0
            if [ "$n_" -eq "$depth_" ]; then
                #posYX 46 100 0
                tput cup 46 50
                echo "n: $n_ ($n2_) $depth_  "
                #current_dir_size=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
            else
                #posYX 46 100 0
                tput cup 46 50
                echo "n: $n_ ($n2_) $depth_   "
                #current_dir_size=$(find "$directory" -mindepth 1 -maxdepth $((n_+1)) -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
                sleep 0.01
            fi
            #dir_size=$((current_dir_size))
            ;;
        "c"|"C")
            clear
            headln
            ;;
        "h"|"H"|"?")
            mode_=$((mode))
            mode=0
            posYX 47 0 0
            echo -e -n "\033[1K$keysdef\033[0K"
            for i in $(seq 1 10); do printf "\033[2K"; done
            ;;
    esac
    if [ -n "$key" ]; then
        posYX 45 0 0
        echo -e -n "  key(s) pressed: '$key'                    "
        #printf %d\\n "'$key"
    fi

    full_path=`find $directory -type d -printf '%d\n' | sort -rn | head -1`
    depth_=$((base_path+full_path-1))

done

