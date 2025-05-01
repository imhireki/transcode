#!/usr/bin/bash

source ./config.sh

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

initialize_shared_counter() {
  echo -1 > "$SHARED_COUNTER"
}

is_valid_json() {
  echo "$1" | jq -e . >/dev/null 2>&1
}

update_state() {
  key="$1"  # .transcoding.video
  value="$2"

  # value matches state's value
  [[ $(jq "$key" "$STATE") == "$value" ]] && return

  # Ensure --arg is used for strings and --argjson for everything else
  argtype=$(is_valid_json "$value" && echo "--argjson" || echo "--arg")

  # pass key directly, so it can use nested keys (.a.b)
  new_state=$(jq "$argtype" value "$value" "($key) = \$value" "$STATE")

  echo "$new_state" > "$STATE"
}

next_from_shared_counter() {
  counter=$(cat "$SHARED_COUNTER")
  ((counter++))
  echo "$counter" | tee "$SHARED_COUNTER"
}

cleanup() {
  [[ -f "$STATE" ]] && rm "$STATE"
  [[ -f "$PROGRESS" ]] && rm "$PROGRESS"
  [[ -f "$SHARED_COUNTER" ]] && rm "$SHARED_COUNTER"
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

  filename=$(basename "$media")  # a/b/c.mkv -> c.mkv
  title="${filename%.*}"
  extension="${filename##*.}"

  format_name=$(
    ffprobe -v quiet -show_entries format=format_name \
    -print_format json  "$media" | jq -r ".format.format_name"
  )
  if ! match_attribute "$format_name" "$SUPPORTED_FORMATS"; then
    extension="$PREFERRED_EXTENSION"
  fi

  # Add .transcode. if the output is going to where the input is
  media_dir=$(dirname "$media")
  if [[ "$to_directory" == "$media_dir" ]]; then
    echo "${to_directory}/${title}.transcoded.${extension}"
  else
    mkdir -p "$to_directory"
    echo "${to_directory}/${title}.${extension}"
  fi
}
