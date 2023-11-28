#!/bin/bash

mpv --title=browser_player "$(xclip -o -selection clipboard)" &
