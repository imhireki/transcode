#!/usr/bin/bash

function remove_corrupted() {
  bytes=$(awk '{print $5}' <<< $file)

  if [ "$bytes" == "0" ]; then
    rm $file_name_ext
  fi
}

function rename_date_filename {
  # hour-minute_day-month-year         - '{printf "%s-%s-%s %s:%s:00", $5, $4, $3, $1, $2}'
  # year-month-day_hour:minute         - '{printf "%s-%s-%s %s:%s:00", $1, $2, $3, $4, $5}'
  # year-month-day_hour.minute.second  - '{printf "%s-%s-%s %s:%s:%s", $1, $2, $3, $4, $5, $6}'
  # year_month_day-hour:minute:second  - '{printf "%s-%s-%s %s:%s:%s", $1, $2, $3, $4, $5, $6}'
  files=$(/bin/ls -l --time-style='+%s' | grep .png)

  while read file; do
    file_name_ext=$(awk '{print $7}' <<< $file)
    file_name=$(awk '{print substr($1, 1, length($1)-4)}' <<< $file_name_ext)
    formatted_file_name=$(awk -F '[:_.-]' '{printf "%s-%s-%s %s:%s:%s", $1, $2, $3, $4, $5, $6}' <<< $file_name)
    
    # echo $file_name_ext $file_name $formatted_file_name
    mv "$file_name_ext" "$(date --date="$formatted_file_name" +"%s").png"
  done < <(echo "$files")
}

function shift_dates() {
  find ./*.png -print | while read filename; do
      file_name=$(awk -F'[./]' '{print $3}' <<< $filename)
      touch -t "$(date -d @$file_name +%Y%m%d%H%M.%S)" $filename
  done
}

