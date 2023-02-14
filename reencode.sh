#!/usr/bin/bash

target_folder=$1
storage_folder="$HOME/videos/reencoded/$2"

mkdir $storage_folder

for media in $target_folder/*; do
  ffmpeg \
    -hwaccel cuda -hwaccel_output_format cuda \
    -i "$media" \
    -map 0:v -map 0:a:m:language:jpn -map 0:s \
    -c:v h264_nvenc -c:a copy -c:s copy \
    -profile:v high -pix_fmt yuv420p -preset fast \
    "$storage_folder/$(awk -F "/" '{print $NF}' <<< $media)"
done

