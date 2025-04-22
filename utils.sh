#!/usr/bin/bash


list_streams_by_type() {
  # a: audio, v: video, s: subtitle
  media="$1"
  stream_type="$2"

  ffprobe -v quiet -show_streams -select_streams "$stream_type" \
    -print_format json "$media" | jq -c ".streams[]"
}

filter_streams_by_type() { 
  streams="$1"
  target_type="$2"

  streams_array="[]"

  # Iterate over the json streams
  while IFS= read -r stream; do
    codec_type=$(echo "$stream" | jq -r ".codec_type")

    # Append to streams_array the target stream
    if [ "$codec_type" == "$target_type" ]; then
      streams_array=$(echo "$streams_array" \
        | jq --argjson streams "$stream" ". + [$stream]")
    fi
  done < <(echo "$streams")

  echo "$streams_array"
}

get_output_filename() {
  media="$1"
  to_directory="$2"

  # Make the input directory in the output directory
  media_base_dir=$(awk -F "/" '{print $(NF-1)}' <<< "$media")
  mkdir -p "${to_directory}${media_base_dir}/"

  filename=$(basename "$media")
  output="${to_directory}${media_base_dir}/${filename}"

  format_name=$(ffprobe -v quiet -show_entries format=format_name \
     -print_format json "$media"| jq -r ".format.format_name")

  # Echo output non-mkv/mp4 as mkv
  [[ "$format_name" =~ ^(matroska,webm|mov,mp4,m4a,3gp,3g2,mj2)$ ]] \
    && echo "$output" || sed "s/\.\w\+$/.mkv/" <<< "$output"
}

save_working_dirs_to_json() {
  from_dir="$1"
  to_dir="$2"

  from_dir_basename=$(basename "$from_dir")

  input_dir="$from_dir"
  output_dir="${to_dir}${from_dir_basename}/"

  object=$(jq -n \
    --arg input_dir "$input_dir" \
    --arg output_dir "$output_dir" \
    '{ "INPUT_DIR": $input_dir, "OUTPUT_DIR": $output_dir }'
  )
  echo "$object" > /tmp/transcode_data.json
}

add_filename_to_json() {
  filename="$1"

  if [ -f /tmp/transcode_data.json ]; then
    object=$(/bin/cat /tmp/transcode_data.json \
      | jq --arg filename "$filename" '.FILENAME= $filename')
  else
    object=$(jq -n --arg filename "$filename" '{"FILENAME":$filename}')
  fi

  echo "$object" > "/tmp/transcode_data.json"
}
