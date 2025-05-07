#!/usr/bin/bash

source ./utils.sh
source ./flags.sh

build_ordered_flags() {
  local media="$1"

  initialize_state

  local video_flags audio_flags subtitle_flags
  read -ra video_flags < <(make_video_flags "$media")
  read -ra audio_flags < <(make_audio_flags "$media")
  read -ra subtitle_flags < <(make_subtitle_flags "$media")

  has_pending_operations || { cleanup_state; return; }

  local flags=()

  if is_burning_sub; then
    read -ra video_flags < <(make_burning_sub_video_flags)
    flags=( "${subtitle_flags[@]}" "${video_flags[@]}" "${audio_flags[@]}" )
  else
    flags=( "${video_flags[@]}" "${audio_flags[@]}" "${subtitle_flags[@]}" )
  fi

  cleanup_state

  echo "${flags[@]}"
}

transcode() {
  local media="$1"
  local output="$2"

  update_json ".duration" "$(get_duration "$media" )" "$METADATA"

  # Get ordered flags for ffmpeg
  local ordered_flags
  read -ra ordered_flags < <(build_ordered_flags "$media")
  [[ "${#ordered_flags}" -eq 0 ]] && return 1

  ffmpeg -v quiet -hide_banner -nostdin -progress pipe:1 \
    -i "$media" "${ordered_flags[@]}" "$output" | parse_progress

  # The file's been processed. Increase counter.
  local num_output_files
  num_output_files=$(jq -r ".num_output_files" "$METADATA")
  ((num_output_files++))
  update_json ".num_output_files" "$num_output_files" "$METADATA"
}


media_path=$(realpath "$1" 2>/dev/null || echo "")
to_directory=$(realpath -m "$2" 2>/dev/null || echo "$PWD")

initialize_metadata

readarray -t files < <(find "$media_path" -maxdepth 1 -type f 2>/dev/null | sort)
update_json ".num_input_files" "${#files[@]}" "$METADATA"

for media in "${files[@]}"; do
  output=$(get_output_filename "$media" "$to_directory")
  transcode "$media" "$output"
done

cleanup_metadata
