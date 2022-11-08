#!/bin/bash

killrecording() {
	recpid="$(cat /tmp/recordingpid)"
	# kill with SIGTERM, allowing finishing touches.
	kill -15 "$recpid"
	rm -f /tmp/recordingpid
	pkill -RTMIN+9 "${STATUSBAR:-dwmblocks}"
	# even after SIGTERM, ffmpeg may still run, so SIGKILL it.
	sleep 3
	kill -9 "$recpid"
	exit
	}

screencast() { \
	ffmpeg -y \
	-f x11grab \
	-s "$(xdpyinfo | awk '/dimensions/ {print $2;}')" \
	-i "$DISPLAY" \
	-f pulse -i default \
 	-c:v libx264rgb -qp 0 -r 30 -crf 0 -preset ultrafast -c:a aac \
	"$HOME/videos/recordings/screencast-$(date  +%Y_%m_%d-%H:%M:%S).mkv" &
	echo $! > /tmp/recordingpid
    }

video() { ffmpeg \
	-f x11grab \
	-s "$(xdpyinfo | awk '/dimensions/ {print $2;}')" \
	-i "$DISPLAY" \
 	-c:v libx264rgb -qp 0 -r 30 \
    -crf 0 -preset ultrafast \
	"$HOME/videos/recordings/video-$(date  +%Y_%m_%d-%H:%M:%S).mkv" &
	echo $! > /tmp/recordingpid
	}

audio() { \
	ffmpeg \
	-f alsa -i default \
	-c:a flac \
	"$HOME/audio-$(date  +%Y_%m_%d-%H:%M:%S).flac" &
	echo $! > /tmp/recordingpid
	}

case "$1" in
	screencast) screencast;;
	audio) audio;;
	video) video;;
	kill) killrecording;;
	*) ([ -f /tmp/recordingpid ] && exit);;
esac

