#!/bin/sh

maim -s \
    | tee ~/Pictures/screenshots/$(date +%H-%M_%d-%m-%Y).png \
    | xclip -selection clipboard -t image/png
