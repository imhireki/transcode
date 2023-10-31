#!/usr/bin/bash

# target=$1
# storage="/mnt/hd/transcoded/$2"
# mkdir $storage


function transcode_video {
  # ffmpeg \
  #   -hwaccel cuda -hwaccel_output_format cuda \
  #   -i "$media" \ 
  for media in "$target/"*; do
    ffmpeg \
      -i "$media" \
      -map 0:v:0 -map 0:a:m:language:jpn -map 0:s \
      -c:v h264_nvenc -c:a copy -c:s copy \
      -profile:v high -pix_fmt yuv420p -preset fast \
      "$storage/$(awk -F "/" '{print $NF}' <<< $media)"
  done
}


function transcode_audio {
  for media in "$target/"*; do
    ffmpeg \
      -nostdin \
      -i "$media" \
      -map 0:v -map 0:a -map 0:s \
      -c:v copy -c:a aac -c:s copy \
      "$storage/$(awk -F "/" '{print $NF}' <<< $media)"
  done
}


list_directories() {
  base_dir="/mnt/hd/animes"

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


get_codecs() {
  media="$1"
  streams=$(ffmpeg -i "$media" 2>&1 | grep "Stream #0:" )

  # Remove the thumbnail (v:1) and get the video's codec 
  video_codec=$(echo "$streams" | grep "Video" -m 1 \
    | grep -Po "(?<=Video: ).*?(?=,)")  # h264 (High 10)

  # Get all the audios' codecs
  audio_codecs=$(echo "$streams" | grep "Audio" \
    | grep -Po "(?<=Audio: ).*?(?=,)")  # aac (LC)

  # Get all the subtitles' codecs
  subtitle_codecs=$(echo "$streams"  | grep "Subtitle" \
    | grep -Po "(?<=Subtitle: ).*?(?=,|\(default\)|$)")  # ass

  # codecs=$(get_codecs "$1")
  # echo "$codecs"
}


get_audio_arguments() {
  streams="$1"
  codec_args=()

  # Make an array out of the audio streams
  readarray -t audio_streams < <(echo "$streams" | grep "Audio")

  for audio_stream in "${audio_streams[@]}"; do
    # Audio: aac (LC), -> aac (LC)
    codec=$(echo "$audio_stream" | grep -Po "(?<=Audio: ).*?(?=,)")

    # #0:2(eng) -> 2
    stream_id=$(echo "$audio_stream" | grep -Po "(?<=#0:)\d*?(?=\(\w+\))")
 
    if [[ "$codec" =~ ^(aac \(LC\)|flac|opus|ac3|mp3)$ ]]; then
      codec_args+=("-c:${stream_id} copy")
    else
      codec_args+=("-c:${stream_id} aac")
    fi
  done

  echo "${codec_args[@]}"
}


get_video_arguments() {
  streams="$1"

  # Video: h264 (High 10),
  codec=$(echo "$streams" | grep "Video" -m 1 \
     | grep -Po "(?<=Video: ).*?(?=,)")

  transcode_args="-c:v h264_nvenc -profile:v high -pix_fmt yuv420p -preset fast"

  [ "$codec" != "h264 (High)" ] && echo "$transcode_args" || echo ""
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

  # streams=$(ffprobe -v quiet -show_streams -print_format json "$1" | jq -c ".streams[]")
  # audio_streams=$(filter_streams_by_type "$streams" "audio")

  # while IFS= read -r stream; do
  #   echo "$stream" | jq -r ".codec_name"
  # done < <(echo "$audio_streams" | jq -c ".[]")
}


_split_streams_by_compatibility() {
  streams="$1"
  split_streams='{"supported": [],"unsupported": []}'

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")

    if [[ "$codec_name" =~ ^(ass|srt)$ ]]; then
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
    codec_name=$(echo "$sub_stream" | jq -r ".codec_name")
    stream_index=$(echo "$sub_stream" | jq -r ".index")

    if [[ "$codec_name" =~ ^(ass|srt)$ ]]; then
      codec_args+=("-c:$stream_index copy")
    fi
  done < <(echo "$supported_streams" | jq -c ".[]")
  echo "${codec_args[@]}"
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

  echo "-filter_complex '[0:v:0][0:${max_bytes_sub}]' -map '[v]'"
}
