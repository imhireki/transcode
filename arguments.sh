#!/usr/bin/bash

source ./utils.sh

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
        echo "-map 0:${stream_index} -c:${stream_index} h264" \
             "-profile:v high -pix_fmt yuv420p -preset fast"
      else
        echo "-map 0:${stream_index} -c:${stream_index} copy"
      fi

      break  # Real (not cover) stream's been found (stop the loop)
    fi
  done < <(echo "$video_streams" | jq -c ".[]")

}

_split_sub_streams_by_compatibility() {
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

_get_supported_sub_args() {
  supported_streams="$1"
  codec_args=()

  # Loop through the subtitle streams
  while IFS= read -r sub_stream; do
    stream_index=$(echo "$sub_stream" | jq -r ".index")
    codec_args+=("-map 0:${stream_index}")

    # If there's no disposition arg and forced sub, reset disposition
    if ! [[ "${codec_arg[@]}" =~ "-disposition 0" ]]; then
     forced_sub=$(echo "$sub_stream" | jq -r ".disposition.forced")
      [ "$forced_sub" -ne 0 ] && codec_args+=("-disposition 0")
    fi

  done < <(echo "$supported_streams" | jq -c ".[]")

  echo "${codec_args[@]} -c:s copy"
}

_get_unsupported_sub_args() {
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

  overlay_filter_args=("-filter_complex" "[0:v:0][0:${max_bytes_sub}]overlay[v]"
                       "-map" "[v]")
  echo "${overlay_filter_args[@]}"
}

get_subtitle_arguments() {
  streams="$1"
  media="$2"

  sub_streams=$(filter_streams_by_type "$streams" "subtitle")
  split_streams=$(_split_sub_streams_by_compatibility "$sub_streams")

  # There's supported streams (echo its args)
  supported_streams=$(echo "$split_streams" | jq -c ".supported")
  supported_args=$(_get_supported_sub_args "$supported_streams")
  [ -n "$supported_args" ] && echo "${supported_args[@]}" && return

  # There's ONLY unsupported streams (echo args for the dialogue)
  unsupported_streams=$(echo "$split_streams" | jq -c ".unsupported")
  unsupported_args=$(_get_unsupported_sub_args "$unsupported_streams" "$media")
  [ -n "$unsupported_args" ] && echo "$unsupported_args" && return
}
