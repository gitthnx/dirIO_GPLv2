#!/bin/bash

# version 0.1
# June 21, 2024

# gpt 3.x
# initial prompt command:
# Please create a code example for data input output monitoring and data rate output within a bash shell command line. Create this script as bash shell script. Create this script for file system data input and data output and data rates from or to this directory, that is declared with script variables on startup. Please add request for keyboard input for stopping that script on pressing q or Q. Add another keyboard input scan for pausing output with pressing p and resuming with space key.



# Check if directory is provided
avail=$( [ ! -d $1 ] || [ -z "$1" ] && echo "0" || echo "1" )
if [ "$1" == "/" ]; then avail=0; echo; echo "*** no root fs io monitoring recommended ***"; fi
echo " \$# $#   \$1 $1  directory path available $avail"

keysdef=\
"                                             \n"\
"       keys: on 'statx' errors == 'n'        \n"\
"             pause             == 'p'        \n"\
"             resume            == ' ' or 'r' \n"\
"             quit              == 'q' or 'Q' \n"\
"                                             \n"\
"       version 0.1                           \n"\
"       June 15, 2024                         \n"
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
start_time=$(date +%s)
paused=false
err=false

dir_size=$(find "$directory" -type f,d | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
dir_size_du=$(du -sb "$directory" | awk '{print $1}')
start_dir_size=$((dir_size_du))
current_dir_size=$((dir_size))

start_date=$(date)
echo "monitoring start: $start_date"
echo "directory size (find -type cmd) $((dir_size/1024)) kB, directory size (du cmd) $((dir_size_du/1024)) kB"
echo
sleep 1.0


# Function to monitor data I/O and data rates
monitor_io() {
  local rate_in=0
  local rate_out=0

    # Get current I/O stats
    current_io=$(du -sb "$directory" | awk '{print $1}')

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

    # Update previous values
    dir_size_du=$((current_io))

    # Display data rates
    echo "  Data Input Rate:  $rate_in  bytes/sec $((rate_in/1024)) kB/s  $((rate_in/(1024*1024))) MB/s"
    echo "  Data Output Rate: $rate_out bytes/sec  $((rate_out/1024)) kB/s  $((rate_out/(1024*1024))) MB/s"
    echo "  Data Input Sum: $sum_in  bytes $((sum_in/1024)) kB  $((sum_in/(1024*1024))) MB"
    echo "  Data Output Sum: $sum_out  bytes $((sum_out/1024)) kB  $((sum_out/(1024*1024))) MB"
    echo
}



# Function to calculate data rate output
calculate_data_rate() {
    echo "$start_date   start_dir_size $((start_dir_size/1024)) kB  current_dir_size $((current_dir_size/1024)) kB  monitoring time io $(( ($current_dir_size-$start_dir_size)/1024 )) kb"
    current_dir_size=$(find "$directory" -type f,d | xargs stat --format="%s" | awk '{s+=$1} END {print s}')

    data_rate_output=$((current_dir_size - dir_size))
    echo "  data_rate_io $data_rate_output B/s"
    dir_size=$((current_dir_size))
    if [ $((data_rate_output)) -le 0 ]; then
      input_sum=$(( input_sum+data_rate_output ))
      in_sum_float=`echo "scale=3; $((input_sum))/(1024*1024)" | bc`
    else
      output_sum=$(( output_sum+data_rate_output ))
      out_sum_float=`echo "scale=3; $((output_sum))/(1024*1024)" | bc`
    fi

    echo -e -n "  Data rate io: $data_rate_output bytes/s  `echo  \"scale=4; $data_rate_output/1024/1024\" | bc` MB/s"
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    #echo -e -n " ${ROW#*[}"
    pos=${ROW#*[}
    #echo $pos

    data_io=$((${data_rate_output#-}))
    if [ $data_io -ge $((1024*1024)) ]; then relh_pos=10; elif [ $data_io -ge $((1024)) ]; then relh_pos=5; elif [ $data_io -ge $((512)) ]; then relh_pos=3; else relh_pos=$((data_io/255));  fi
    #echo -e -n "  io $data_rate_output  relh $relh_pos "

    tput cup  $pos 50
    echo -e -n "|"
    if [ $data_rate_output -le 0 ]; then tput cup $pos $((70-relh_pos)); else tput cup $pos $((70)); fi
    for i in $(seq 1 ${relh_pos#-} ); do printf "~"; done
    tput cup  $pos 70
    echo -e -n "|"
    tput cup ${ROW#*[} 90
    echo -e -n "|\n"
    echo "  data io sum: $((input_sum))  $((output_sum)) bytes"
    echo "  data io sum: $in_sum_float   $out_sum_float MB"
    echo
}



# Main loop
while true; do
  if [ "$paused" = false ]; then
       if [ "$err" = false ]; then
         calculate_data_rate #comment with difficulties with (hard)links, permissions, 'No such file or directory',
       fi
       monitor_io
  fi

  read -s -t 1 -n 1 key
  if [ "$key" = "q" ] || [ "$key" = "Q" ]; then
    echo "monitoring stop:  $(date)"
    echo
    sleep 1
    break
    exit 1
  elif [ "$key" = "p" ]; then
    paused=true
    echo "Output paused. Press space or key 'r' to resume."
  elif [ "$key" = " " ] || [ "$key" = "r" ]; then
    paused=false
    echo "Output resumed."
  elif [ "$key" = "n" ]; then
    if [ "$err" == "false" ]; then
      err="true"
    else
      err="false"
    fi
  elif [ ! "$key" == "" ]; then
    echo ""
    echo "key(s) pressed: $key"
    echo ""
  fi
done

