#!/usr/bin/bash

function store_screenshot() {
  tee ~/pictures/screenshots/$(date +%s).png | \
  xclip -selection clipboard -t image/png
}

case $1 in
    area) maim -s -d 1 | store_screenshot;; 
    screen) maim -d 1 | store_screenshot;;
esac

