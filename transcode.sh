#!/usr/bin/bash

list_directories() {
  base_dir="$1"

  while true; do
    selected_dir=$(find "$base_dir" -maxdepth 1 -type d | dmenu)

    # Nothing selected
    if [ -z "$selected_dir" ]; then
      break
    # Nested dir selected
    elif [ "$base_dir" != "$selected_dir" ]; then
      base_dir="$selected_dir"

    # Dir confirmed
    else
      echo "$selected_dir"
      break
    fi
  done
}


filter_streams_by_type() { 
  streams="$1"
  target_type="$2"

  streams_array="[]"

  # Iterate over the json streams
  while IFS= read -r stream; do
    codec_type=$(echo "$stream" | jq -r ".codec_type")

    # Append to streams_array the target stream
    if [ "$codec_type" == "$target_type" ]; then
      streams_array=$(echo "$streams_array" \
        | jq --argjson streams "$stream" ". + [$stream]")
    fi
  done < <(echo "$streams")

  echo "$streams_array"
}


get_audio_arguments() {
  streams="$1"

  audio_streams=$(filter_streams_by_type "$streams" "audio")
  codec_args=()

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")
    stream_index=$(echo "$stream" | jq -r ".index")

    if [[ "$codec_name" =~ (aac|flac|opus|ac3|mp3) ]]; then
      codec_args+=("-map 0:${stream_index} -c:${stream_index} copy")
    else
      codec_args+=("-map 0:${stream_index} -c:${stream_index} aac")
    fi

  done < <(echo "$audio_streams" | jq -c ".[]")

  echo "${codec_args[@]}"
}


get_video_arguments() {
  streams="$1"

  # Can include the cover
  video_streams=$(filter_streams_by_type "$streams" "video")

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")

    # Not a cover
    if ! [[ "$codec_name" =~ (jpeg|png|webp) ]]; then

      profile=$(echo "$stream" | jq -r ".profile")
      stream_index=$(echo "$stream" | jq -r ".index")

      # Not h264 or h264 without High profile (transcode)
      if [ "$codec_name" != "h264" ] || [ "$profile" != "High" ]; then
        echo "-map 0:${stream_index} -c:${stream_index} h264_nvenc" \
             "-profile:v high -pix_fmt yuv420p -preset fast"
      else
        echo "-map 0:${stream_index} -c:${stream_index} copy"

      fi

      break  # Real (not cover) stream's been found (stop the loop)
    fi
  done < <(echo "$video_streams" | jq -c ".[]")

}


_split_streams_by_compatibility() {
  streams="$1"
  split_streams='{"supported": [],"unsupported": []}'

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")

    if [[ "$codec_name" =~ ^(ass|subrip)$ ]]; then
      split_streams=$(echo "$split_streams" | jq --argjson stream \
                      "$stream" ".supported += [$stream]")
    else
      split_streams=$(echo "$split_streams" | jq --argjson stream \
                      "$stream" ".unsupported += [$stream]")
    fi
  done < <(echo "$streams" | jq -c ".[]")

  echo "$split_streams"
}


_get_supported_args() {
  supported_streams="$1"
  codec_args=()

  # Loop through the subtitle streams
  while IFS= read -r sub_stream; do
    stream_index=$(echo "$sub_stream" | jq -r ".index")
    codec_args+=("-map 0:${stream_index}")
  done < <(echo "$supported_streams" | jq -c ".[]")

  # Remove "forced disposition" from all subtitles
  echo "-disposition 0 ${codec_args[@]} -c:s copy"
}


_get_unsupported_args() {
  unsupported_streams="$1"
  media="$2"

  sub_with_bytes=()

  while IFS= read -r sub_stream; do
    num_bytes=$(echo "$sub_stream" | jq -r ".tags" \
      | grep -i -Po '".*byte.*": "\d+"' \
      | grep -Po '(?<=: ")\d+')

    stream_index=$(echo "$sub_stream" | jq -r ".index")

    # Write to a tmp file to get its bytes
    if [ -z "$num_bytes" ]; then
      ffmpeg -nostdin -v quiet -i "$media" \
        -map 0:"$stream_index" -c copy  /tmp/transcode_sub.mkv
      num_bytes=$(stat -c %s /tmp/transcode_sub.mkv)
      rm /tmp/transcode_sub.mkv
    fi

    sub_with_bytes+=("${stream_index} ${num_bytes}")

  done < <(echo "$unsupported_streams" | jq -c ".[]")

  # Sort by num of bytes
  readarray -t sorted_sub_with_bytes < \
      <(printf "%s\n" "${sub_with_bytes[@]}" | sort -k2,2nr)

  max_bytes_sub=$(printf "%s\n" "${sorted_sub_with_bytes[@]}"\
      | awk 'NR == 1 {print $1}')

  overlay_filter_args=("-filter_complex" "[0:v:0][0:${stream_index}]overlay[v]"
                       "-map" "[v]")
  echo "${overlay_filter_args[@]}"
}


get_subtitle_arguments() {
  streams="$1"
  media="$2"

  sub_streams=$(filter_streams_by_type "$streams" "subtitle")
  split_streams=$(_split_streams_by_compatibility "$sub_streams")

  # There's supported streams (echo its args)
  supported_streams=$(echo "$split_streams" | jq -c ".supported")
  supported_args=$(_get_supported_args "$supported_streams")
  [ -n "$supported_args" ] && echo "${supported_args[@]}" && return

  # There's ONLY unsupported streams (echo args for the dialogue)
  unsupported_streams=$(echo "$split_streams" | jq -c ".unsupported")
  unsupported_args=$(_get_unsupported_args "$unsupported_streams" "$media")
  [ -n "$unsupported_args" ] && echo "$unsupported_args" && return
}


get_output_filename() {
  media="$1"
  to_directory="$2"

  # Make the input directory in the output directory
  last_input_directory=$(awk -F "/" '{print $(NF-1)}' <<< "$media")
  mkdir -p "${to_directory}/${last_input_directory}/"

  input_without_directories=$(awk -F "/" '{print $NF}' <<< "$media")
  output="${to_directory}/${last_input_directory}/${input_without_directories}"

  format_name=$(ffprobe -v quiet -show_entries format=format_name \
     -print_format json "$media"| jq -r ".format.format_name")

  # Echo output non-mkv/mp4 as mkv
  [[ "$format_name" =~ ^(matroska,webm|mov,mp4,m4a,3gp,3g2,mj2)$ ]] \
    && echo "$output" || sed "s/\.\w\+$/.mkv/" <<< "$output"
}


transcode() {
  streams="$1"
  media="$2"
  to_directory="$3"

  video_arguments=$(get_video_arguments "$streams")
  subtitle_arguments=$(get_subtitle_arguments "$streams" "$media")

  if [[ "$subtitle_arguments[@]" =~ (filter_complex) ]]; then
    video_stream_index=$(echo "$video_arguments" | grep -Po "(?<=-map 0:)\d+")

    # Remove mapping and set a codec with video options
    video_arguments="-c:${video_stream_index} h264_nvenc -profile:v high\
    -pix_fmt yuv420p -preset fast"

    # Replace [0:v:0] with the actual stream index [0:video_stream_index]
    subtitle_arguments[1]=$(echo "${subtitle_arguments[1]}"\
      | sed "s/\[0:v:0\]/\[0:${video_stream_index}\]/g")
  fi

  audio_arguments=$(get_audio_arguments "$streams")
  output_filename=$(get_output_filename "$media" "$to_directory")

  ffmpeg -v quiet -stats -hide_banner -nostdin -i "$media" $video_arguments \
    ${subtitle_arguments[@]} $audio_arguments "$output_filename" \
    2>> /tmp/transcode_stats
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


get_directory_progress() {
  media="$1"
  to_directory="$2"

  # input directory length
  input_dirname=$(dirname "$media")
  num_input_files=$(find "${input_dirname}/" -maxdepth 1 -type f | wc -l)

  # Output directory length
  last_input_directory=$(awk -F "/" '{print $(NF-1)}' <<< "$media")
  num_output_files=$(find "${to_directory}/${last_input_directory}/" \
    -maxdepth 1 -type f | wc -l)

  percentage=$(( (num_output_files * 100) / num_input_files))

  echo "files ${num_output_files}/${num_input_files} (${percentage}%)"
}


get_stats() {
  media="$1"

  stats=$(awk -F "\r" '{print $NF }' < /tmp/transcode_stats)

  frame=$(echo "$stats" | grep -Po "frame=\s*\d+" | grep -Po "\d+")
  fps=$(echo "$stats" | grep -Po "fps=\s*\d+" | grep -Po "\d+")
  size=$(echo "$stats" | grep -Po "size=\s*\S+" | grep -Po "\d+.*")
  time=$(echo "$stats" | grep -Po "time=\S+" | grep -Po "(?<==)\S+")
  bitrate=$(echo "$stats" | grep -Po "bitrate=\s*\S+" | grep -Po "(?<=[= ])\S+")
  speed=$(echo "$stats" | grep -Po "speed=\s*\S+" | grep -Po "(?<=[= ])\S+")

  duration=$(ffprobe -v error -show_entries format=duration \
             -of default=nw=1:nk=1 "$media" | cut -d. -f1)

  # Convert to seconds
  time=$(echo "$time" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' | cut -d. -f1)

  duration_percentage=$(( (time * 100) / duration ))

  progress=("time ${time}s/${duration}s (${duration_percentage}%)" "speed $speed"
            "frames $frame" "fps $fps" "size $size" "bitrate $bitrate")
  printf "%s\n" "${progress[@]}"
}


show_progress() {
  media="$1"
  to_directory="$2"

  stats=$(get_stats "$media")
  directory_progress=$(get_directory_progress "$media" "$to_directory")

  echo -e "${directory_progress}\n${stats}" | rofi -dmenu -i -p "Transcoding"
}
