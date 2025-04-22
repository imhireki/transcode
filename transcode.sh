#!/usr/bin/bash

source ./utils.sh
source ./arguments.sh

transcode() {
  streams="$1"
  media="$2"
  to_directory="$3"

  add_filename_to_json "$media"

  video_arguments=$(get_video_arguments "$streams")
  subtitle_arguments=$(get_subtitle_arguments "$streams" "$media")
  audio_arguments=$(get_audio_arguments "$streams")

  # There's no actions to be performed, return.
  ! [[ "$video_arguments" =~ (h264) ]] \
    && ! [[ "$audio_arguments" =~ (aac) ]] \
    && ! [[ "$subtitle_arguments" =~ (filter_complex|disposition) ]] \
    && return

  # BURNING SUBS
  if [[ "$subtitle_arguments[@]" =~ (filter_complex) ]]; then
    video_stream_index=$(echo "$video_arguments" | grep -Po "(?<=-map 0:)\d+")

    # Remove mapping and set a codec with video options
    video_arguments="-c:${video_stream_index} h264 -profile:v high \
-pix_fmt yuv420p -preset fast"

    # Replace [0:v:0] with the actual stream index [0:video_stream_index]
    subtitle_arguments[1]=$(echo "${subtitle_arguments[1]}"\
      | sed "s/\[0:v:0\]/\[0:${video_stream_index}\]/g")

    # Argument order to burn sub
    arguments=($video_arguments ${subtitle_arguments[@]} $audio_arguments)
  else
    # Argument order to copy sub
    arguments=($video_arguments $audio_arguments ${subtitle_arguments[@]})
  fi

  output_filename=$(get_output_filename "$media" "$to_directory")

  ffmpeg -v quiet -stats -hide_banner -nostdin -i "$media" \
    ${arguments[@]} "$output_filename" 2>> /tmp/transcode_stats

  rm /tmp/transcode_stats
}

transcode_directory() {
  from_directory="$1"
  to_directory="$2"

  while IFS= read -r media; do
    streams=$(ffprobe -v quiet -show_streams -print_format json \
              "$media" | jq -c ".streams[]")
    transcode "$streams" "$media" "$to_directory"
  done < <(find "$from_directory" -maxdepth 1 -type f | sort)
}

transcode_file() {
  media="$1"
  to_directory="$2"

  streams=$(ffprobe -v quiet -show_streams -print_format json \
            "$media" | jq -c ".streams[]")
  transcode "$streams" "$media" "$to_directory"
}


input="$1"
to_directory="/mnt/hd/transcoded/"

# Directory
if [ -d "$input" ]; then
  from_directory="${input%/}/"  # Add trailing slash
  save_working_dirs_to_json "$from_directory" "$to_directory"
  transcode_directory "$from_directory" "$to_directory"
# File
elif [ -f "$input" ]; then
  transcode_file "$input" "$to_directory"
fi
