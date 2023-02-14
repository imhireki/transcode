#!/usr/bin/bash

extract_subs () {
  for media in *.*; do
    media_name=$(echo $media | cut -d. -f 1)
    ffmpeg -i "$media" -map 0:2 -c:s subrip "$media_name.srt"
  done
}

embed_sub () {
  for media in *.*; do
    media_name=$(echo $media | cut -d. -f 1)
    ffmpeg -i "$media" -i "subs/$media_name.srt" \
        -map 0:0 -map 0:1 -map 1:0 \
        -c:v copy -c:a copy -c:s subrip \
        "mkv/$media_name.mkv"
  done
}

extract_subs

