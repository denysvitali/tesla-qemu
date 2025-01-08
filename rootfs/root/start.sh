#!/bin/bash
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

/usr/bin/Xorg &
