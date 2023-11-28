#!/usr/bin/bash

pidof mpd >/dev/null || mpd && (alacritty --class ncmpcpp -e /bin/ncmpcpp) &
