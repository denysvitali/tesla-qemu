#!/bin/bash

# Network
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

chown -R tesla:tesla /home/tesla

# Mount modloop to get Alpine kernel modules
mkdir -p /.modloop
mount -o loop /boot/modloop-lts /.modloop
ln -sf /.modloop/modules/6.6.14-0-lts /lib/modules/6.6.14-0-lts

# Load virtio GPU driver (needed for DRM/KMS)
modprobe virtio_gpu

# Allow non-root users to access GPU
chmod 666 /dev/dri/*

# Create DRI path symlink (Ubuntu Xorg expects this path)
mkdir -p /usr/lib/x86_64-linux-gnu
ln -sf /usr/lib/dri /usr/lib/x86_64-linux-gnu/dri

/usr/bin/Xorg &
export DISPLAY=:0

# Wait for X to start
sleep 2

# Set resolution to 1080x1920 (portrait, Tesla center display)
xrandr -s 1200x1920

/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
