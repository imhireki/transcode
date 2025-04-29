#!/usr/bin/bash

source ./config.sh
source ./utils.sh

make_audio_flags() {
  media="$1"
  flags=()

  while IFS= read -r stream; do
    index=$(jq -r ".index" <<< "$stream")
    codec=$(jq -r ".codec_name" <<< "$stream")

    if match_attribute "$codec" "$SUPPORTED_AUDIO_CODECS"; then
      flags+=("-map 0:${index} -c:${index} copy")
    else
      flags+=("-map 0:${index} -c:${index} ${AUDIO_ENCODING_FLAGS}")
      update_state ".transcoding.audio" true
    fi
  done < <(list_streams_by_type "$media" "a")

  echo "${flags[*]}"
}

make_reencoding_video_flags() {
  input_index=$(jq ".video.input_index" "$STATE")
  output_index=$(jq ".video.output_index" "$STATE")
  flags=(
    "-map" "0:${input_index}" "-c:${output_index}"
    "$VIDEO_ENCODING_FLAGS"
  )
  echo "${flags[*]}"
}

make_video_flags() {
  media="$1"

  while IFS= read -r stream; do
    codec=$(jq -r ".codec_name" <<< "$stream")

    # Skip covers
    match_attribute "$codec" "$UNSUPPORTED_COVERS" && continue

    index=$(jq -r ".index" <<< "$stream")
    profile=$(jq -r ".profile" <<< "$stream")

    # It's needed when burning subs, whether transcoding video or not.
    update_state ".index.video" "$index"

    if match_attribute "$codec" "$SUPPORTED_VIDEO_CODECS" && \
       match_attribute "$profile" "$SUPPORTED_VIDEO_PROFILES"; then
      echo "-map 0:${index} -c:${index} copy"
    else
      echo "-map 0:${index} -c:${index} ${VIDEO_ENCODING_FLAGS}"
      update_state ".transcoding.video" true
    fi

  done < <(list_streams_by_type "$media" "v")
}

group_subs_by_format() {
  media="$1"
  groups='{"text": [], "image": []}'

  while IFS= read -r stream; do
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

    if [[ "$forced" == "1" ]]; then
      flags+=("-disposition:${index} -forced")
      update_state ".transcoding.subtitle" true
    fi

  done <<< "$indexes"

  echo "${flags[*]}"
}

make_image_sub_flags() {
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
        -c copy "$TEMP_IMAGE_SUBTITLE_FILE"
      size=$(stat -c %s "$TEMP_IMAGE_SUBTITLE_FILE")
      rm "$TEMP_IMAGE_SUBTITLE_FILE"
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

  update_state ".index.subtitle" "$max_size_sub_index"
  update_state ".transcoding.subtitle" true

  overlay_filter_flags=(
    "-filter_complex [0:v:0][0:${max_size_sub_index}]overlay[v]"
    "-map [v]"
  )
  echo "${overlay_filter_flags[@]}"
}

make_subtitle_flags() {
  media="$1"

  sub_groups=$(group_subs_by_format "$media")

  text_sub_indexes=$(jq -r ".text[]" <<< "$sub_groups")
  text_sub_flags=$(make_text_sub_flags "$media" "$text_sub_indexes")

  # Prefer the text-based subs.
  [[ -n "$text_sub_flags" ]] && echo "$text_sub_flags" && return

  # Return if it's not supposed to burn any image-based sub
  [[ $BURN_IMAGE_SUBTITLE == true ]] || return

  image_sub_indexes=$(jq -r ".image[]" <<< "$sub_groups")
  image_sub_flags=$(make_image_sub_flags "$media" "$image_sub_indexes")

  # There's only image-based subs.
  if [[ -n "$image_sub_flags" ]]; then
    update_state ".is_burning_sub" true
    echo "$image_sub_flags"
  fi
}
