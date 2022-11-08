#!/bin/bash

print_select() {
    maim -s | \
    tee ~/pictures/screenshots/select/$(date  +%Y_%m_%d-%H:%M:%S).png | \
    xclip -selection clipboard -t image/png
}

print_screen() {
    maim | \
    tee ~/pictures/screenshots/$(date +%Y_%m_%d-%H:%M:%S).png | \
    xclip -selection clipboard -t image/png
}

case $1 in
    select)
        print_select;; 
    screen)
        print_screen;;
esac

