#!/bin/bash
X -ac -nolisten local -nolisten tcp -nolisten inet6 -dumbSched -verbose -logverbose &
sleep 1
export DISPLAY=:0
xrandr --output Virtual-0 --mode 1920x1200