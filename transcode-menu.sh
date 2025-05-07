#!/usr/bin/bash

source ./config.sh

get_files_progress() {
  num_input_files=$(jq -r ".num_input_files" "$METADATA")
  num_output_files=$(jq -r ".num_output_files" "$METADATA")

  [[ "$num_input_files" -eq 0 ]] && return
  percentage=$(( (num_output_files * 100) / num_input_files))

  printf "%s\n" "files done ${num_output_files}/${num_input_files} (${percentage}%)"
}

get_stats() {
  # 2:quality 8:dup_frames 9:drop_frames 11:progress
  IFS="," read -ra stats < "$PROGRESS"

  duration=$(jq -r ".duration" "$METADATA")
  time=$(
    awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' <<< "${stats[7]}"
  )
  duration_percentage=$(
    awk -v x="$time" -v y="$duration" 'BEGIN { printf "%.1f\n",  (x * 100) / y }'
  )
  pretty_time=$(date -u -d "@$time" +%T)
  pretty_duration=$(date -u -d "@$duration" +%T)

  size=$(numfmt --to=iec --suffix=B --format="%.1f" "${stats[4]}")

  # time 00:01:15/00:24:32 (5.1%) frame 1809 (69.52 fps)
  # birate 5175.6kbits/s (46.5MB) at 2.9x
  progress=(
    "time ${pretty_time%*.}/${pretty_duration%*.} (${duration_percentage}%)"
    "frame ${stats[0]} (${stats[1]} fps)"
    "birate ${stats[3]} (${size})" "at ${stats[10]#' '}"
  )

  printf "%s\n" "${progress[@]}"
}


show_progress() {
  directory_progress=$(get_directory_progress)
  stats=$(get_stats) || return 1
  echo -e "${directory_progress}${stats}" | rofi -dmenu -i -p "Transcoding"
}


show_progress
