#!/usr/bin/bash

source ./utils.sh
source ./flags.sh

transcode() {
  media="$1"
  output="$2"

  read -ra video_flags < <(make_video_flags "$media")
  read -ra audio_flags < <(make_audio_flags "$media")
  read -ra subtitle_flags < <(make_subtitle_flags "$media")

  has_pending_operations || return

  if is_burning_sub; then
    read -ra video_flags < <(make_burning_sub_video_flags)
    flags=( "${subtitle_flags[@]}" "${video_flags[@]}" "${audio_flags[@]}" )
  else
    flags=( "${video_flags[@]}" "${audio_flags[@]}" "${subtitle_flags[@]}" )
  fi

  ffmpeg -v quiet -hide_banner -nostdin -progress pipe:1 \
    -i "$media" "${flags[@]}" "$output" | parse_progress
}

media_path=$(realpath "$1" 2>/dev/null || echo "")
to_directory=$(realpath -m "$2" 2>/dev/null || echo "$PWD")

files=$(find "$media_path" -maxdepth 1 -type f 2>/dev/null | sort)
readarray -t files < <(find "$media_path" -maxdepth 1 -type f 2>/dev/null | sort)

initialize_metadata
update_json ".num_input_files" "${#files[@]}" "$METADATA"

for media in "${files[@]}"; do
  update_json ".duration" "$(get_duration "$media" )" "$METADATA"

  initialize_state
  output=$(get_output_filename "$media" "$to_directory")
  transcode "$media" "$output"
  cleanup_state

  num_output_files=$(jq -r ".num_output_files" "$METADATA")
  ((num_output_files++))
  update_json ".num_output_files" "$num_output_files" "$METADATA"
done
cleanup_metadata
