#!/usr/bin/bash

source ./utils.sh
source ./flags.sh

transcode() {
  media="$1"
  output="$2"

  initialize_storage

  update_json ".filename" "$media" "$METADATA"
  update_json ".directory.input" "$(dirname "$media")" "$METADATA"
  update_json ".directory.output" "$(dirname "$output")" "$METADATA"

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

  cleanup_storage
}

media_path=$(realpath "$1" 2>/dev/null || echo "")
to_directory=$(realpath -m "$2" 2>/dev/null || echo "$PWD")

while IFS= read -r media; do
  output=$(get_output_filename "$media" "$to_directory")
  transcode "$media" "$output"
done < <(find "$media_path" -maxdepth 1 -type f | sort)
