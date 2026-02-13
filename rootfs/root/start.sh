#!/bin/bash
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

chown -R tesla:tesla /home/tesla

/usr/bin/Xorg &
export DISPLAY=:0

# This assumes the screen is horizontally oriented - which should always be the case also
# for the models where the screen is portrait. 
# In that case, QtCar should start with --rotation=90 (or similar)
xrandr -s 1920x1080

/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
