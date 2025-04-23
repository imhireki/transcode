#!/usr/bin/bash

source ./utils.sh

get_audio_arguments() {
  streams="$1"

  codec_args=()

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")
    stream_index=$(echo "$stream" | jq -r ".index")

    if [[ "$codec_name" =~ (aac|flac|opus|ac3|mp3) ]]; then
      codec_args+=("-map 0:${stream_index} -c:${stream_index} copy")
    else
      codec_args+=("-map 0:${stream_index} -c:${stream_index} aac")
    fi
  done < <(list_streams_by_type "$media" "a")

  echo "${codec_args[@]}"
}

get_video_arguments() {
  streams="$1"

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")

    # Skip cover and remove it (since it will not be mapped)
    [[ "$codec_name" =~ (jpeg|png|webp) ]] && return

    profile=$(echo "$stream" | jq -r ".profile")
    stream_index=$(echo "$stream" | jq -r ".index")

    # Not h264 or h264 without High profile (transcode)
    if [[ "$codec_name" != "h264" ]] || [[ "$profile" != "High" ]]; then
      echo "-map 0:${stream_index} -c:${stream_index} h264" \
           "-profile:v high -pix_fmt yuv420p -preset fast"
    else
      echo "-map 0:${stream_index} -c:${stream_index} copy"
    fi
  done < <(list_streams_by_type "$media" "v")
}

group_subs_by_compatibility() {
  media="$1"
  groups='{"supported": [],"unsupported": []}'

  while IFS= read -r stream; do
    codec_name=$(echo "$stream" | jq -r ".codec_name")

    if [[ "$codec_name" =~ ^(ass|subrip)$ ]]; then
      groups=$(echo "$groups" | jq --argjson stream \
        "$stream" ".supported += [$stream]")
    else
      groups=$(echo "$groups" | jq --argjson stream \
        "$stream" ".unsupported += [$stream]")
    fi
  done < <(list_streams_by_type "$media" "s")

  echo "$groups"
}

_get_supported_sub_args() {
  supported_streams="$1"
  args=()

  while IFS= read -r sub_stream; do
    stream_index=$(echo "$sub_stream" | jq -r ".index")

    # Map supported stream
    args+=("-map 0:${stream_index}")

    # Disable forced disposition, known for causing compatibility problems.
    forced=$(echo "$sub_stream" | jq -r ".disposition.forced")
    [[ "$forced" -eq 1 ]] && args+=("-disposition:${stream_index} -forced")
  done <<< "$supported_streams"
  echo "${args[*]} -c:s copy"
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
  done <<< "$unsupported_streams"

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
  media="$1"

  streams=$(group_subs_by_compatibility "$media")

  # There's supported streams (echo its args)
  supported_streams=$(echo "$streams" | jq -c ".supported[]")
  supported_args=$(_get_supported_sub_args "$supported_streams")
  [ -n "$supported_args" ] && echo "${supported_args[@]}" && return

  # There's ONLY unsupported streams (echo args for the dialogue)
  unsupported_streams=$(echo "$streams" | jq -c ".unsupported[]")
  unsupported_args=$(_get_unsupported_sub_args "$unsupported_streams" "$media")
  [ -n "$unsupported_args" ] && echo "$unsupported_args" && return
}
