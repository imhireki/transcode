#!/usr/bin/bash

source ./utils.sh
source ./flags.sh

transcode() {
  media="$1"
  to_directory="$2"

  add_filename_to_json "$media"
  initialize_shared_counter
  initialize_state

  video_flags=$(make_video_flags "$media")
  audio_flags=$(make_audio_flags "$media")
  subtitle_flags=$(make_subtitle_flags "$media")

  # There's no actions to be performed, return.
  ! [[ "$video_flags" =~ (h264) ]] \
    && ! [[ "$audio_flags" =~ (aac) ]] \
    && ! [[ "$subtitle_flags" =~ (filter_complex|disposition) ]] \
    && return

  # BURNING SUBS
  if [[ "$subtitle_flags[@]" =~ (filter_complex) ]]; then
    video_stream_index=$(echo "$video_flags" | grep -Po "(?<=-map 0:)\d+")

    # Remove mapping and set a codec with video options
    video_flags="-c:${video_stream_index} h264 -profile:v high " \
                    "-pix_fmt yuv420p -preset fast"

    # Replace [0:v:0] with the actual stream index [0:video_stream_index]
    subtitle_flags[1]=$(echo "${subtitle_flags[1]}"\
      | sed "s/\[0:v:0\]/\[0:${video_stream_index}\]/g")

    # flag order to burn sub
    flags=($video_flags ${subtitle_flags[@]} $audio_flags)
  else
    # flag order to copy sub
    flags=($video_flags $audio_flags ${subtitle_flags[@]})
  fi

  output_filename=$(get_output_filename "$media" "$to_directory")

  ffmpeg -v quiet -stats -hide_banner -nostdin -i "$media" \
    ${flags[@]} "$output_filename" 2>> /tmp/transcode_stats

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
