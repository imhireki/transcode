#!/usr/bin/bash

source ./config.sh
source ./utils.sh

get_audio_arguments() {
  media="$1"
  flags=()

  while IFS= read -r stream; do
    index=$(jq -r ".index" <<< "$stream")
    codec=$(jq -r ".codec_name" <<< "$stream")

    if match_attribute "$codec" "$SUPPORTED_AUDIO_CODECS"; then
      flags+=("-map 0:${index} -c:${index} copy")
    else
      flags+=("-map 0:${index} -c:${index} ${AUDIO_ENCODING_FLAGS}")
    fi
  done < <(list_streams_by_type "$media" "a")

  echo "${flags[*]}"
}

get_video_arguments() {
  media="$1"

  while IFS= read -r stream; do
    codec=$(jq -r ".codec_name" <<< "$stream")

    # Skip covers
    match_attribute "$codec" "$UNSUPPORTED_COVERS" && continue

    index=$(jq -r ".index" <<< "$stream")
    profile=$(jq -r ".profile" <<< "$stream")

    if match_attribute "$codec" "$SUPPORTED_VIDEO_CODECS" && \
       match_attribute "$profile" "$SUPPORTED_VIDEO_PROFILES"; then
      echo "-map 0:${index} -c:${index} copy"
    else
      echo "-map 0:${index} -c:${index} ${VIDEO_ENCODING_FLAGS}"
    fi

  done < <(list_streams_by_type "$media" "v")
}

group_subs_by_compatibility() {
  media="$1"
  groups='{"supported": [], "unsupported": []}'

  while IFS= read -r stream; do
    codec=$(jq -r ".codec_name" <<< "$stream")
    index=$(jq -r ".index" <<< "$stream")

    if match_attribute "$codec" "$SUPPORTED_SUBTITLE_CODECS"; then
      groups=$(jq --arg index "$index" '.supported += [$index]' <<< "$groups")
    else
      groups=$(jq --arg index "$index" '.unsupported += [$index]' <<< "$groups")
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
