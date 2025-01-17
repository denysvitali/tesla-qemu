#!/bin/bash
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

chown -R tesla:tesla /home/tesla

/usr/bin/Xorg &
export DISPLAY=:0
xrandr 
/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
