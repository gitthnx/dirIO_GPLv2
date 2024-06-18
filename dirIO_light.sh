#!/bin/bash

# Initialize variables
directory="$1"
total_input=0
total_output=0
start_time=$(date +%s)
paused=false

dir_size=$(find "$directory" -type f | xargs stat --format="%s" | awk '{s+=$1} END {print s}')
#total_output=$((dir_size))

# Function to calculate data rate output
calculate_data_rate() {
    current_dir_size=$(find "$directory" -type f | xargs stat --format="%s" | awk '{s+=$1} END {print s}')

    data_rate_output=$((current_dir_size - dir_size))
    dir_size=$((current_dir_size))
    if [ $((data_rate_output)) -le 0 ]; then
      input_sum=$(( input_sum+data_rate_output ))
      in_sum_float=`echo "scale=3; $((input_sum))/(1024*1024)" | bc`
    else
      output_sum=$(( output_sum+data_rate_output ))
      out_sum_float=`echo "scale=3; $((output_sum))/(1024*1024)" | bc`
    fi

    echo "Data rate io: $data_rate_output bytes/s  `echo  \"scale=4; $data_rate_output/1024/1024\" | bc` MB/s"
    echo "data io sum: $((input_sum))  $((output_sum)) bytes"
    echo "data io sum: $in_sum_float   $out_sum_float MB"
}

# Main loop
while true; do
  if [ "$paused" = false ]; then
       calculate_data_rate
  fi

  read -t 1 -n 1 key
  if [ "$key" = "q" ] || [ "$key" = "Q" ]; then
    break
  elif [ "$key" = "p" ]; then
    paused=true
    echo "Output paused. Press space to resume."
  elif [ "$key" = " " ]; then
    paused=false
    echo "Output resumed."
  fi
done

