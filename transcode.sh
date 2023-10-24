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
  codec_args=""

  # Make an array out of the audio streams
  readarray -t audio_streams < <(echo "$streams" | grep "Audio")

  for audio_stream in "${audio_streams[@]}"; do
    # Audio: aac (LC), -> aac (LC)
    codec=$(echo "$audio_stream" | grep -Po "(?<=Audio: ).*?(?=,)")

    # #0:2(eng) -> 2
    stream_id=$(echo "$audio_stream" | grep -Po "(?<=#0:)\d*?(?=\(\w+\))")
 
    if [[ "$codec" =~ ^(aac \(LC\)|flac|opus|ac3|mp3)$ ]]; then
      codec_args+="-c:${stream_id} copy "
    else
      codec_args+="-c:${stream_id} aac "
    fi
  done

  echo "$codec_args"
}


get_video_arguments() {
  streams="$1"

  # Video: h264 (High 10),
  codec=$(echo "$streams" | grep "Video" -m 1 \
     | grep -Po "(?<=Video: ).*?(?=,)")

  transcode_args="-c:v h264_nvenc -profile:v high -pix_fmt yuv420p -preset fast"

  [ "$codec" != "h264 (High)" ] && echo "$transcode_args" || echo ""
}

