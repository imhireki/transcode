#!/usr/bin/bash


get_downloads() {
  raw_downloads="transmission-remote -l"
  # raw_downloads="cat /home/hireki/documents/transmission_remote"

  # Removes the header and footer
  downloads=$(eval $raw_downloads | awk 'NR > 2 {print payload} {payload=$0}')

  # Return if there's no downloads or the daemon is down
  if [ -z "$downloads" ]; then return; fi

  # Get the average percentage of all downloads
  percentages=$(echo "$downloads" | awk -F'\\s\\s+' '{printf "%.3s\n", $3}')
  done=$(echo -e "$percentages" | awk '{ mean += $1 } END { printf "%.0f\n", mean/NR }')

  # Get the average ratio from all downloads
  ratios=$(echo "$downloads" | awk -F'\\s\\s+' '{ print  $8}')
  ratio=$(echo -e "$ratios" | awk '{ mean += $1 } END { printf "%.2f\n", mean/NR }')

  # Get fields (related to all downloads) from the footer
  have=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $2 } END { print field }')
  up=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $3 } END { print field }')
  down=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $4 } END { print field }')

  # Echo the downloads with the extra option
  all_option="    all   ${done}%   ${have}  N/A         ${up}     ${down}   ${ratio}  N/A      all"
  echo "$all_option" $'\n' "$downloads"
}


list_download_titles() {
  # Downloads argument
  downloads="$1"

  # Exit if there's no downloads
  if [ -z "$downloads" ]; then exit; fi

  # Extract the downloads' title
  titles=$(echo "$downloads" | awk -F'\\s\\s+' '{print $10}')

  # List the titles (Select to proceed, return otherwise)
  selected_title=$(echo "$titles"| rofi -dmenu -i -p "Title") || return

  # Return the download of the selected title
  echo "$downloads" | grep -F "$selected_title"
}


get_download_details() {
  # Selected download argument
  selected_download="$1"

  # Exit if there's no selected download
  if [ -z "$selected_download" ]; then exit; fi

  # Extract the downloads' details
  status=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $9}')
  done=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $3}')
  have=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $4}')
  eta=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $5}')
  up=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $6}')
  down=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $7}')
  ratio=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $8}')

  # Format the downloads' details
  details=(
    "Status: ${status}"
    "Done: ${done}"
    "Have: ${have}"
    "ETA: ${eta}"
    "Up: ${up}"
    "Down: ${down}"
    "Ratio: ${ratio}"
  )

  # List the details (exit if nothing's been selected)
  printf '%s\n' "${details[@]}" | rofi -dmenu -i -p "Details" > /dev/null || exit
}


control_download() {
  # Selected download argument
  selected_download="$1"

  # Grep its id (number or all)
  download_id=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $2}' | grep -Po "(\d+|all)")

  # Control options
  controls=( "Stop" "Resume" "Remove" "Kill Daemon" )

  # List the control (select to perform an action, exit otherwise)
  selected_control=$(printf '%s\n' "${controls[@]}" | rofi -dmenu -i -p "Controls") || exit

  # Perform action
  case $selected_control in
    Stop) transmission-remote -t $download_id -S;;
    Resume) transmission-remote -t $download_id -s;;
    Remove) transmission-remote -t $download_id -r;;
    "Kill Daemon") killall transmission-daemon;;
  esac
}


start_clipboard_magnet() {
  # Start transmission-daemon
  pidof transmsission-daemon || transmission-daemon

  # Wait for the daemon to start
  while ! pidof transmission-daemon; do
    sleep 1
  done

  # Start magnet from the clipboard
  transmission-remote -a "$(xclip -o -selection clipboard)" -s

  # Clean clipboard
  echo "" | xclip -selection clipboard
}


# Start magnet
if [[ "$(xclip -o -selection clipboard)" == "magnet:?"* ]]; then
  start_clipboard_magnet
# Open menu
else
  downloads=$(get_downloads)
  selected_download=$(list_download_titles "$downloads")
  get_download_details "$selected_download"
  control_download "$selected_download"
fi


