#!/bin/sh

# Run a sync to reduce dirty caches
sync

# Tell the OS to clear caches
echo 3 > /proc/sys/vm/drop_caches
echo 2 > /proc/sys/vm/drop_caches
echo 1 > /proc/sys/vm/drop_caches
