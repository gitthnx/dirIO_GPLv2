#!/bin/bash

# version 0.11
# March 07, 2025

# gpt 3.x
# initial prompt command:
# Please create a code example for data input output monitoring and data rate output within a bash shell command line. Create this script as bash shell script. Create this script for file system data input and data output and data rates from or to this directory, that is declared with script variables on startup. Please add request for keyboard input for stopping that script on pressing q or Q. Add another keyboard input scan for pausing output with pressing p and resuming with space key.



# Check if directory is provided
clear
avail=$( [ ! -d $1 ] || [ -z "$1" ] && echo "0" || echo "1" )
if [ "$1" == "/" ]; then avail=0; echo; echo "*** no root fs io monitoring recommended ***"; fi
echo " \$# $#   \$1 $1  directory path available $avail"
echo "Usage: $0 '-h' | '--help' | '-?' | '/?'" 

keysdef=\
"                                             \n"\
"       keys: on 'statx' errors == 'n'        \n"\
"             pause             == 'p'        \n"\
"             resume            == ' ' or 'r' \n"\
"             clear screen      == 'c' or 'C' \n"\
"             help              == 'h' or 'H' or '?'  \n"\
"             quit              == 'q' or 'Q' \n"\
"                                             \n"\
"       version 0.11                          \n"\
"       March 07, 2025                        \n"
if [ -z "$1" ] || [ ! "$avail" == 1 ] || [ "$#" -ne 1 ]; then
  echo "Usage: $0  /directory/to/monitor"
  if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "-?" ] || [ "$1" == "/?" ]; then
    echo -e -n "$keysdef"
  fi
  echo
  exit 1
fi


# Initialize variables
directory="$1"
total_input=0
total_output=0
#start_time=$(date +%s%N)
start_time=$(date +%s)
paused=false
err=false
cntr1=1

dir_size=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
dir_size_du=$(du -sb "$directory" | awk '{print $1}')
start_dir_size=$((dir_size_du))
current_dir_size=$((dir_size))

### set cursor position
posYX() {
  ROW=$1
  tput cup ${ROW#*[} $2
#  echo -e "var1_Y $1 var2_X $2 \n"
  if [ "$3" -ne "1" ]; then echo -e "\e[?25l"; else echo -e "\e[?25h"; fi
}

### function to monitor data I/O and data rates
monitor_io() {
  local rate_in=0
  local rate_out=0

  # was there data io?
  # inotifywait -e create,access,modify,move,delete -r -m -c -o /dev/shm/inotify.lg  /dev/shm/tmp
  # cat /dev/shm/inotify.lg != '' (?)

    # Get current I/O stats
#    current_io=$(du -sb "$directory" | awk '{print $1}')
    current_io=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')

    # Calculate data rates
    # 1s timeout on read cmd
    rate_io=$((current_io - dir_size_du))
    if [ $((rate_io)) -le 0 ]; then
      rate_in=$(( rate_in+rate_io ))
      sum_in=$(( sum_in+rate_in ))
    else
      rate_out=$(( rate_out+rate_io ))
      sum_out=$(( sum_out+rate_out ))
    fi

    # Update variable with current values
    dir_size_du=$((current_io))

    # Display data rates
    posYX 40 0 0
    echo -e  "  Data Input Rate:  $rate_in  bytes/sec $((rate_in/1024)) kB/s  $((rate_in/(1024*1024))) MB/s \033[0K"
    echo -e  "  Data Output Rate: $rate_out bytes/sec  $((rate_out/1024)) kB/s  $((rate_out/(1024*1024))) MB/s \033[0K"
    echo -e  "  Data Input Sum: $sum_in  bytes $((sum_in/1024)) kB  $((sum_in/(1024*1024))) MB \033[0K"
    echo -e  "  Data Output Sum: $sum_out  bytes $((sum_out/1024)) kB  $((sum_out/(1024*1024))) MB \033[0K"

    #winsize_=$(xwininfo -id $(xdotool getactivewindow) | awk -F ':' '/Width/ || /Height/{print $2}')
    #winsize_=$(xdotool getwindowgeometry $(xdotool getactivewindow) | grep -e 'Geometry' | cut -d ':' -f 2 | cut -d 'x' -f 1 | tr -d ' ')
    winsize_=$(xwininfo -id $(xdotool getactivewindow) | awk -F ':' '/Width/ || /Height/{print $2}' | tr '\n' ' ' )
    winname_=$(xwininfo -id $(xdotool getactivewindow) -all | awk -F ':'      '/xwininfo/ {print  $3 $4}')
    #winname_=$(wmctrl -l |  cut -d ' ' -f 4,5)   #wmctrl -lpG
    echo -e "  winsize $winsize_ "$winname_" \033[0K"


}

# Function to calculate data rate output
calculate_data_rate() {
    posYX 7 0 0
    echo -e "$start_date   start_dir_size $((start_dir_size/1024)) kB  current_dir_size $((current_dir_size/1024)) kB  monitoring period io diff $(( ($current_dir_size-$start_dir_size)/1024 )) kb \033[0K"

    now_=$(date +%s) #%s%N
    uptime_=$((now_-start_time))

# find "$directory" -type d  | xargs stat --format="%s" | awk '{s+=$1} END {print s}' | awk '{print $1/1024/1024" GB"}'
# find "$directory" -type d,f  -printf '"%h/%f"\n'  | xargs stat --format="%s" | awk '{s+=$1} END {print s}' | awk '{print $1/1024/1024/1024" GB"}'
# du -sm  /dev/shm | awk '{print $1/1024" GB"}'

#    current_dir_size=$(find "$directory" -type f,d | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
    current_dir_size=$(find "$directory" -type f,d -printf '"%h/%f"\n' | xargs stat --format="%s" | awk '{s+=$1} END {print s}')

    data_rate_output=$((current_dir_size - dir_size))
    echo -e "  data_rate_io $data_rate_output B/s \033[0K"
    dir_size=$((current_dir_size))
    if [ $((data_rate_output)) -le 0 ]; then
      input_sum=$(( input_sum+data_rate_output ))
      in_sum_float=`echo "scale=3; $((input_sum))/(1024*1024)" | bc`
    else
      output_sum=$(( output_sum+data_rate_output ))
      out_sum_float=`echo "scale=3; $((output_sum))/(1024*1024)" | bc`
    fi

#    echo -e -n "\033[0K"  #from cursor to \n
#    echo -e "\033[1K"  #before cursor pos
#    echo -e "\033[2K"  #whole line
    echo -e "  Data rate io: $data_rate_output bytes/s  `echo  \"scale=4; $data_rate_output/1024/1024\" | bc` MB/s \033[0K"

    echo -e "  data io sum: $((input_sum))  $((output_sum)) bytes \033[0K"
    echo -e -n "  data io sum: $in_sum_float   $out_sum_float MB ";
    #printf "%s.%s " "${uptime_:0: -9}" "${uptime_: -9:3}"
    echo -e " ($uptime_) \033[0K"


    # get current cursor pos
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    #echo -e -n " ${ROW#*[}"
    pos=${ROW#*[}
    #echo $pos
}

# Function for graphical representation of data IO
graphical_output() {

    posYX 12 0 0
    # get current cursor pos
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    #echo -e -n " ${ROW#*[}"
    gpos=${ROW#*[}
    pos=$((gpos+cntr1))

    #echo $pos

    data_io=$((${data_rate_output#-}))
    if [ $data_io -ge $((1024*1024)) ]; then relh_pos=10; elif [ $data_io -ge $((1024)) ]; then relh_pos=5; elif [ $data_io -ge $((512)) ]; then relh_pos=3; else relh_pos=$((data_io/255));  fi
    #echo -e -n "  io $data_rate_output  relh $relh_pos "

#    tput cup  $pos 70
#    for i in $(seq 1 $((110-70)) ); do printf "."; done

    tput cup  $pos 5
#   posYX $pos 0 0
#    date_=$(date "+%H:%M:%S_%T. %6N")
    date_=$(date "+%H:%M:%S.%3N")
    if [ "$data_io" -ne "0" ]; then echo -e "  Data rate io: $data_rate_output bytes/s  `echo  \"scale=4; $data_rate_output/1024/1024\" | bc` MB/s \033[0K"; else echo -e "   $date_ \033[0K"; fi
    tput cup  $pos 70
    echo -e -n "|"
    if [ $data_rate_output -le 0 ]; then tput cup $pos $((90-relh_pos)); else tput cup $pos $((90)); fi
    for i in $(seq 1 ${relh_pos#-} ); do printf "~"; done
    tput cup  $pos 90
    echo -e -n "|"
    tput cup $pos 110
    echo -e -n "|\n"


#    echo -e "cntr1 $cntr1 pos $pos"
    cntr1=$((cntr1+1))
    if [ "$cntr1" -gt "23" ]; then cntr1=1; fi

}






start_date=$(date)
posYX 3 0 0
echo "monitoring start: $start_date"
echo "directory size (find -type cmd) $((dir_size/1024)) kB, directory size (du cmd) $((dir_size_du/1024)) kB"
echo
sleep 1.0
#clear


# Main loop
while true; do
  if [ "$paused" = false ]; then
       #clear
       if [ "$err" = false ]; then
         calculate_data_rate #comment with difficulties with (hard)links, permissions, 'No such file or directory',
         graphical_output
       fi
       monitor_io
  fi
  
  read -s -t 0.1 -n 1 key
  posYX 45 0 0
  if [ "$key" = "q" ] || [ "$key" = "Q" ]; then
    echo "monitoring stop:  $(date)"
    echo
    sleep 1
    clear
    posYX 0 0 1
    break
    exit 1
  elif [ "$key" = "p" ]; then
    paused=true
    echo "Output paused. Press space or key 'r' to resume."
  elif [ "$key" = " " ] || [ "$key" = "r" ]; then
    paused=false
    posYX 47 0 0
    echo -e "Output resumed. \033[0K"
  elif [ "$key" = "n" ]; then
    if [ "$err" == "false" ]; then
      err="true"
    else
      err="false"
    fi
  elif [ "$key" = "c" ] || [ "$key" = "C" ]; then
    clear
  elif [ "$key" = "h" ] || [ "$key" = "H" ] || [ "$key" = '?' ] ; then
    posYX 47 0 0
    echo -e -n "$keysdef"  
  elif [ ! "$key" == "" ]; then
    posYX 46 0 0
    echo -e -n ""
    echo -e -n "key(s) pressed: $key"
    echo -e -n ""
  fi

done
