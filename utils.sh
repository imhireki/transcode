#!/usr/bin/bash

source ./config.sh

parse_progress() {
  local progress=()
  local counter=0
  local key value

  while IFS='=' read -r key value; do
    if [[ counter -eq 12 ]]; then
      printf '%s,' "${progress[@]}" > "$PROGRESS"
      progress=()
      counter=0
    fi

    progress+=("$value")
    ((counter++))
  done
}

get_duration() {
  local media="$1"

  ffprobe -v quiet -show_entries format=duration \
    -print_format json  "test.mkv" | jq -r ".format.duration"
}

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

initialize_metadata() {
  cp "default_metadata.json" "$METADATA"
}

initialize_state() {
  cp "default_state.json" "$STATE"
  echo -1 > "$SHARED_COUNTER"
}

cleanup_state() {
  [[ -f "$STATE" ]] && rm "$STATE"
  [[ -f "$PROGRESS" ]] && rm "$PROGRESS"
  [[ -f "$SHARED_COUNTER" ]] && rm "$SHARED_COUNTER"
}

cleanup_metadata() {
  [[ -f "$METADATA" ]] && rm "$METADATA"
}

is_valid_json() {
  echo "$1" | jq -e . >/dev/null 2>&1
}

update_json() {
  local key="$1"  # .transcoding.video
  local value="$2"
  local json="$3"

  # value matches json's value
  [[ $(jq "$key" "$json") == "$value" ]] && return

  # Ensure --arg is used for strings and --argjson for everything else
  local argtype
  argtype=$(is_valid_json "$value" && echo "--argjson" || echo "--arg")

  # pass key directly, so it can use nested keys (.a.b)
  local new_json
  new_json=$(jq "$argtype" value "$value" "($key) = \$value" "$json")

  echo "$new_json" > "$json"
}

next_from_shared_counter() {
  local counter
  counter=$(cat "$SHARED_COUNTER")
  ((counter++))
  echo "$counter" | tee "$SHARED_COUNTER"
}

match_attribute() {
  local attribute="$1"  # h264
  local supported_values="$2"  # "h264|hevc"

  local regex="^(${supported_values})$"

  [[ "$attribute" =~ $regex ]] && return 0 || return 1
}

select_stream_by_index() {
  local media="$1"
  local index="$2"

  local matching_streams
  matching_streams=$(
    ffprobe -v quiet -show_streams -select_streams \
      "$index" -print_format json "$media"
  )
  jq -c ".streams[]" <<< "$matching_streams"
}

list_streams_by_type() {
  # a: audio, v: video, s: subtitle
  local media="$1"
  local stream_type="$2"

  ffprobe -v quiet -show_streams -select_streams "$stream_type" \
    -print_format json "$media" | jq -c ".streams[]"
}

get_stream_size() {
  local media="$1"
  local index="$2"

  local stream size

  # Check for size in the stream's metadata
  stream=$(select_stream_by_index "$media" "$index")
  size=$(
    echo "$stream" | jq -r ".tags" |
      grep -i -Po '".*byte.*": "\d+"' |
      grep -Po '(?<=: ")\d+'
  )

  if [[ -n "$size" ]]; then
    echo "$size" && return
  fi

  # Calculate the size
  ffmpeg -nostdin -v quiet -i "$media" -map 0:"$index" \
    -c copy "$TEMP_IMAGE_SUBTITLE_FILE"
  stat -c %s "$TEMP_IMAGE_SUBTITLE_FILE"
  rm "$TEMP_IMAGE_SUBTITLE_FILE"
}

get_output_filename() {
  local media="$1"
  local to_directory="$2"

  local filename title extension
  filename=$(basename "$media")  # a/b/c.mkv -> c.mkv
  title="${filename%.*}"
  extension="${filename##*.}"

  local format_name
  format_name=$(
    ffprobe -v quiet -show_entries format=format_name \
    -print_format json  "$media" | jq -r ".format.format_name"
  )
  if ! match_attribute "$format_name" "$SUPPORTED_FORMATS"; then
    extension="$PREFERRED_EXTENSION"
  fi

  # Add .transcode. if the output is going to where the input is
  local media_dir
  media_dir=$(dirname "$media")

  if [[ "$to_directory" == "$media_dir" ]]; then
    echo "${to_directory}/${title}.transcoded.${extension}"
  else
    mkdir -p "$to_directory"
    echo "${to_directory}/${title}.${extension}"
  fi
}
