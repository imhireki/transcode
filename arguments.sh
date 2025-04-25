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

get_supported_sub_args() {
  media="$1"
  indexes="$2"
  flags=()

  # The loop would run once, even if the indexes is empty
  [[ -z "$indexes" ]] && return

  while IFS= read -r index; do
    stream=$(select_stream_by_index "$media" "$index")

    flags+=("-map 0:${index} -c:${index} copy")

    # Remove forced disposition from the sub
    forced=$(jq -r ".disposition.forced" <<< "$stream")
    [[ "$forced" ==  "1" ]] && flags+=("-disposition:${index} -forced")

  done <<< "$indexes"

  echo "${flags[*]}"
}

get_unsupported_sub_args() {
  media="$1"
  indexes="$2"

  subs_with_size=()

  # The loop would run once, even if the indexes is empty
  [[ -z "$indexes" ]] && return

  while IFS= read -r index; do
    stream=$(select_stream_by_index "$media" "$index")

    size=$(
      echo "$stream" | jq -r ".tags" |
        grep -i -Po '".*byte.*": "\d+"' |
        grep -Po '(?<=: ")\d+'
    )

    # Write to a temp file to get its size
    if [[ -z "$size" ]]; then
      ffmpeg -nostdin -v quiet -i "$media" -map 0:"$index" \
        -c copy "$TEMP_GRAPHIC_SUBTITLE_FILE"
      size=$(stat -c %s "$TEMP_GRAPHIC_SUBTITLE_FILE")
      rm "$TEMP_GRAPHIC_SUBTITLE_FILE"
    fi

    subs_with_size+=("${index} ${size}")

  done <<< "$indexes"

  # Sort by biggest size
  readarray -t sorted_subs_with_size < <(
    printf "%s\n" "${subs_with_size[@]}" | sort -k2 -rn
  )

  max_size_sub_index=$(
    echo "${sorted_subs_with_size[*]}" | head -n 1 | cut -d" " -f 1
  )

  overlay_filter_flags=(
    "-filter_complex [0:v:0][0:${max_size_sub_index}]overlay[v]"
    "-map [v]"
  )
  echo "${overlay_filter_flags[@]}"
}

get_subtitle_arguments() {
  media="$1"

  sub_groups=$(group_subs_by_compatibility "$media")

  supported_indexes=$(jq -r ".supported[]" <<< "$sub_groups")
  supported_flags=$(get_supported_sub_args "$media" "$supported_indexes")

  # There's supported subs
  [[ -n "$supported_flags" ]] && echo "$supported_flags" && return

  # Return if it's not supposed to burn them
  [[ $BURN_GRAPHIC_SUBTITLE == true ]] || return

  unsupported_indexes=$(jq -r ".unsupported[]" <<< "$sub_groups")
  unsupported_flags=$(get_unsupported_sub_args "$media" "$unsupported_indexes")

  # There's only unsupported subs
  [[ -n "$unsupported_flags" ]] && echo "$unsupported_flags"
}
