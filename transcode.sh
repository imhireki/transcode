#!/usr/bin/bash

target=$1
storage="/mnt/hd/transcoded/$2"
mkdir $storage


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


transcode_video

