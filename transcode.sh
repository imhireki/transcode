#!/usr/bin/bash

source ./utils.sh
source ./flags.sh

transcode() {
  media="$1"
  to_directory="$2"

  add_filename_to_json "$media"
  initialize_shared_counter
  initialize_state

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

  output_filename=$(get_output_filename "$media" "$to_directory")

  ffmpeg -v quiet -stats -hide_banner -nostin \
    -i "$media" "${flags[@]}" "$output_filename"

  cleanup
}

media_path="$1"
to_directory="$2"

if [ -d "$media_path" ]; then
  from_directory="${media_path%/}/"  # Add trailing slash if not present
  save_working_dirs_to_json "$from_directory" "$to_directory"

  while IFS= read -r media; do
    transcode "$media" "$to_directory"
  done < <(find "$from_directory" -maxdepth 1 -type f | sort)

elif [ -f "$media_path" ]; then
  transcode "$media_path" "$to_directory"
fi
