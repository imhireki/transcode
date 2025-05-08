#!/usr/bin/bash

source ./config.sh
source ./utils.sh

make_audio_flags() {
  local media="$1"
  local flags=()
  local stream

  while IFS= read -r stream; do

    local index codec shared_counter
    index=$(jq -r ".index" <<< "$stream")
    codec=$(jq -r ".codec_name" <<< "$stream")
    shared_counter=$(next_from_shared_counter)

    if match_attribute "$codec" "$SUPPORTED_AUDIO_CODECS"; then
      flags+=("-map 0:${index} -c:${shared_counter} copy")
    else
      flags+=("-map 0:${index} -c:${shared_counter} ${AUDIO_ENCODING_FLAGS}")
      update_json ".transcoding.audio" true "$STATE"
    fi
  done < <(list_streams_by_type "$media" "a")

  echo "${flags[*]}"
}

make_burning_sub_video_flags() {
  local output_index flags
  output_index=$(jq ".video.output_index" "$STATE")
  flags=( "-c:${output_index}" "$VIDEO_ENCODING_FLAGS" )

  echo "${flags[*]}"
}

make_overlay_filter_flags() {
  local subtitle_index="$1"

  local video_index
  video_index=$(jq ".video.input_index" "$STATE")

  local overlay_filter_flags
  overlay_filter_flags=(
    -filter_complex
    "[0:${video_index}][0:${subtitle_index}]overlay[v]"
    -map "[v]"
  )

  echo "${overlay_filter_flags[@]}"
}

make_video_flags() {
  local media="$1"
  local stream

  while IFS= read -r stream; do
    local codec
    codec=$(jq -r ".codec_name" <<< "$stream")

    # Skip covers
    match_attribute "$codec" "$UNSUPPORTED_COVERS" && continue

    local index profile shared_counter
    index=$(jq -r ".index" <<< "$stream")
    profile=$(jq -r ".profile" <<< "$stream")
    shared_counter=$(next_from_shared_counter)

    # It's needed when burning subs, whether transcoding video or not.
    update_json ".video.input_index" "$index" "$STATE"
    update_json ".video.output_index" "$shared_counter" "$STATE"

    if match_attribute "$codec" "$SUPPORTED_VIDEO_CODECS" && \
       match_attribute "$profile" "$SUPPORTED_VIDEO_PROFILES"; then
      echo "-map 0:${index} -c:${shared_counter} copy"
    else
      echo "-map 0:${index} -c:${shared_counter} ${VIDEO_ENCODING_FLAGS}"
      update_json ".transcoding.video" true "$STATE"
    fi

    # Skip any extra video stream or cover
    return
  done < <(list_streams_by_type "$media" "v")
}

group_subs_by_format() {
  local media="$1"
  local groups='{"text": [], "image": []}'
  local stream

  while IFS= read -r stream; do

    local codec index
    codec=$(jq -r ".codec_name" <<< "$stream")
    index=$(jq -r ".index" <<< "$stream")

    if match_attribute "$codec" "$SUPPORTED_SUBTITLE_CODECS"; then
      groups=$(jq --arg index "$index" '.text += [$index]' <<< "$groups")
    else
      groups=$(jq --arg index "$index" '.image += [$index]' <<< "$groups")
    fi
  done < <(list_streams_by_type "$media" "s")

  echo "$groups"
}

make_text_sub_flags() {
  local media="$1"
  local indexes="$2"
  local flags=()

  # The loop would run once, even if the indexes is empty
  [[ -z "$indexes" ]] && return

  local index

  while IFS= read -r index; do

    local stream shared_counter
    stream=$(select_stream_by_index "$media" "$index")
    shared_counter=$(next_from_shared_counter)

    flags+=("-map 0:${index} -c:${shared_counter} copy")

    # Remove forced disposition from the sub
    local forced
    forced=$(jq -r ".disposition.forced" <<< "$stream")
    if [[ "$forced" == "1" ]]; then
      flags+=("-disposition:${shared_counter} -forced")
      update_json ".transcoding.subtitle" true "$STATE"
    fi
  done <<< "$indexes"

  echo "${flags[*]}"
}

make_image_sub_flags() {
  local media="$1"
  local indexes="$2"

  # The loop would run once, even if the indexes is empty
  [[ -z "$indexes" ]] && return

  update_json ".transcoding.subtitle" true "$STATE"
  local index heaviest_stream_index heaviest_stream_size

  while IFS= read -r index; do

    local size
    size=$(get_stream_size "$media" "$index")

    if [[ $size -gt $heaviest_stream_size ]]; then
      heaviest_stream_index="$index"
      heaviest_stream_size="$size"
    fi
  done <<< "$indexes"

  make_overlay_filter_flags "$heaviest_stream_index"
}

make_subtitle_flags() {
  local media="$1"

  local sub_groups
  sub_groups=$(group_subs_by_format "$media")

  local text_sub_indexes text_sub_flags
  text_sub_indexes=$(jq -r ".text[]" <<< "$sub_groups")
  text_sub_flags=$(make_text_sub_flags "$media" "$text_sub_indexes")

  # Prefer the text-based subs.
  [[ -n "$text_sub_flags" ]] && echo "$text_sub_flags" && return

  # Return if it's not supposed to burn any image-based sub
  [[ $BURN_IMAGE_SUBTITLE == true ]] || return

  local image_sub_indexes image_sub_flags
  image_sub_indexes=$(jq -r ".image[]" <<< "$sub_groups")
  image_sub_flags=$(make_image_sub_flags "$media" "$image_sub_indexes")

  # There's only image-based subs.
  if [[ -n "$image_sub_flags" ]]; then
    update_json ".is_burning_sub" true "$STATE"
    echo "$image_sub_flags"
  fi
}
