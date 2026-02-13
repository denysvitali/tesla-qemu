#!/bin/bash
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

chown -R tesla:tesla /home/tesla

# Mount modloop and symlink Alpine kernel modules
mkdir -p /.modloop
mount -o loop /boot/modloop-lts /.modloop
ln -sf /.modloop/modules/6.6.14-0-lts /lib/modules/6.6.14-0-lts

# Load virtio GPU driver (needed for DRM/KMS)
modprobe virtio_gpu

/usr/bin/Xorg &
export DISPLAY=:0

# Wait for X to start
sleep 2

# Set resolution to 1920x1080 (landscape)
xrandr -s 1920x1080

/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
