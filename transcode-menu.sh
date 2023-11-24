#!/usr/bin/bash

get_directory_progress() {
  INPUT_DIR=$(jq -r ".INPUT_DIR" /tmp/transcode_data.json 2> /dev/null)
  OUTPUT_DIR=$(jq -r ".OUTPUT_DIR" /tmp/transcode_data.json 2> /dev/null)

  # Return if env directories aren't present
  ! [ -d "$INPUT_DIR" ] || ! [ -d "$OUTPUT_DIR" ] && return

  num_input_files=$(find "$INPUT_DIR" -maxdepth 1 -type f | wc -l)
  num_output_files=$(find "$OUTPUT_DIR" -maxdepth 1 -type f | wc -l)

  # Take away 1 to show the number of files done.
  [ $num_output_files -gt 0 ] && ((num_output_files--))

  percentage=$(( (num_output_files * 100) / num_input_files))
  echo "files done ${num_output_files}/${num_input_files} (${percentage}%)\n"
}


_get_raw_stats() {
  # Wait 3s max for the stats
  sleep_counter=0
  while ! [ -e /tmp/transcode_stats ]; do
    [ "$sleep_counter" -gt 2 ] && return 1 # Return when the time runs out
    sleep 1 && ((sleep_counter++))
  done
  echo $(awk -F"\r" '{ print $(NF-1) }' < /tmp/transcode_stats)
}


get_stats() {
  FILENAME=$(jq -r ".FILENAME" /tmp/transcode_data.json 2> /dev/null)

  stats=$(_get_raw_stats) || return 1

  frame=$(echo "$stats" | grep -Po "frame=\s*\d+" | grep -Po "\d+")
  fps=$(echo "$stats" | grep -Po "fps=\s*\d+" | grep -Po "\d+")
  size=$(echo "$stats" | grep -Po "size=\s*\S+" | grep -Po "\d+.*")
  time=$(echo "$stats" | grep -Po "time=\S+" | grep -Po "(?<==)\S+")
  bitrate=$(echo "$stats" | grep -Po "bitrate=\s*\S+" | grep -Po "(?<=[= ])\S+")
  speed=$(echo "$stats" | grep -Po "speed=\s*\S+" | grep -Po "(?<=[= ])\S+")

  duration=$(ffprobe -v error -show_entries format=duration \
             -of default=nw=1:nk=1 "$FILENAME" | cut -d. -f1)

  # Convert to seconds
  time=$(echo "$time" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' | cut -d. -f1)

  duration_percentage=$(( (time * 100) / duration ))

  progress=("time ${time}s/${duration}s (${duration_percentage}%)" "speed $speed"
            "frames $frame" "fps $fps" "size $size" "bitrate $bitrate")
  printf "%s\n" "${progress[@]}"
}


show_progress() {
  directory_progress=$(get_directory_progress)
  stats=$(get_stats) || return 1
  echo -e "${directory_progress}${stats}" | rofi -dmenu -i -p "Transcoding"
}


show_progress
