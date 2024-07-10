#!/bin/bash
# -cdrom http://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/mini.iso \
qemu-system-x86_64 \
	-drive file=ubuntu_disk.img \
	-m 4096 \
	-cpu Denverton-v1 \
	-nic user,hostfwd=tcp::60022-:22 \
	-vga qxl \
	-usb \
    	-device usb-ehci,id=ehci \
	-device usb-tablet \
	-serial stdio \
	-serial pty \
	-device virtio-net,netdev=network0 \
	-netdev tap,id=network0,ifname=tap0,script=no,downscript=no \
	-boot d \
	--enable-kvm
