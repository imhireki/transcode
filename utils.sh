#!/usr/bin/bash

has_pending_operations() {
  if [[ $(jq ".transcoding.video" "$STATE") == false ]] &&
     [[ $(jq ".transcoding.audio" "$STATE") == false ]] &&
     [[ $(jq ".transcoding.subtitle" "$STATE") == false ]]; then
    return 1
  else
    return 0
  fi
}

is_burning_sub() {
  [[ $(jq ".is_burning_sub" "$STATE") == true  ]] && return 0 || return 1
}

initialize_state() {
  cp "state_blueprint.json" "$STATE"
}

update_state() {
  key="$1"  # .transcoding.video
  value="$2"

  # value matches state's value
  [[ $(jq "$key" "$STATE") == "$value" ]] && return

  # pass value as json, so booleans are not quoted
  # pass key directly, so it can use nested keys (.a.b)
  new_state=$(jq --argjson value "$value" "($key) = \$value" "$STATE")

  echo "$new_state" > "$STATE"
}

cleanup() {
  [[ -f "$STATE" ]] && rm "$STATE"
  [[ -f "$PROGRESS" ]] && rm "$PROGRESS"
}

match_attribute() {
  attribute="$1"  # h264
  supported_values="$2"  # "h264|hevc"

  regex="^(${supported_values})$"

  [[ "$attribute" =~ $regex ]] && return 0 || return 1
}

select_stream_by_index() {
  media="$1"
  index="$2"

  matching_streams=$(
    ffprobe -v quiet -show_streams -select_streams \
      "$index" -print_format json "$media"
  )
  jq -c ".streams[]" <<< "$matching_streams"
}

list_streams_by_type() {
  # a: audio, v: video, s: subtitle
  media="$1"
  stream_type="$2"

  ffprobe -v quiet -show_streams -select_streams "$stream_type" \
    -print_format json "$media" | jq -c ".streams[]"
}

get_output_filename() {
  media="$1"
  to_directory="$2"

  # Make the input directory in the output directory
  media_base_dir=$(awk -F "/" '{print $(NF-1)}' <<< "$media")
  mkdir -p "${to_directory}${media_base_dir}/"

  filename=$(basename "$media")
  output="${to_directory}${media_base_dir}/${filename}"

  format_name=$(ffprobe -v quiet -show_entries format=format_name \
     -print_format json "$media"| jq -r ".format.format_name")

  # Echo output non-mkv/mp4 as mkv
  [[ "$format_name" =~ ^(matroska,webm|mov,mp4,m4a,3gp,3g2,mj2)$ ]] \
    && echo "$output" || sed "s/\.\w\+$/.mkv/" <<< "$output"
}

save_working_dirs_to_json() {
  from_dir="$1"
  to_dir="$2"

  from_dir_basename=$(basename "$from_dir")

  input_dir="$from_dir"
  output_dir="${to_dir}${from_dir_basename}/"

  object=$(jq -n \
    --arg input_dir "$input_dir" \
    --arg output_dir "$output_dir" \
    '{ "INPUT_DIR": $input_dir, "OUTPUT_DIR": $output_dir }'
  )
  echo "$object" > /tmp/transcode_data.json
}

add_filename_to_json() {
  filename="$1"

  if [ -f /tmp/transcode_data.json ]; then
    object=$(/bin/cat /tmp/transcode_data.json \
      | jq --arg filename "$filename" '.FILENAME= $filename')
  else
    object=$(jq -n --arg filename "$filename" '{"FILENAME":$filename}')
  fi

  echo "$object" > "/tmp/transcode_data.json"
}
