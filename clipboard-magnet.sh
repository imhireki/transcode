#!/usr/bin/bash

start_magnet() {
  magnet="$1"

  # Start transmission-daemon
  if ! pidof transmission-daemon > /dev/null; then
    transmission-daemon
    # Wait for the daemon to start
    while ! pidof transmission-daemon > /dev/null; do
      sleep 1
    done
  fi

  # Wait for the daemon to be able to add magnet
  sleep 1

  # Start magnet from the clipboard
  transmission-remote -a "$magnet" -s
}


clipboard=$(xclip -o -selection clipboard 2> /dev/null)
[[ "$clipboard" == "magnet:?"* ]] && start_magnet "$clipboard"
