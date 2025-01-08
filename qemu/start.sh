#!/bin/bash

# Uses "Direct Linux Boot" method
# https://qemu-project.gitlab.io/qemu/system/linuxboot.html

qemu-system-x86_64 \
   -enable-kvm -cpu host -m 512m -smp 2 \
   -drive format=raw,file=./out/disk.img \
   -kernel ./cache/alpine-iso/boot/vmlinuz-lts \
   -initrd ./cache/alpine-iso/boot/initramfs-lts \
   -append "console=ttyS0 root=/dev/sda rootflags=rw init=/bin/bash earlyprintk=ttyS0 modules=ext4,virtio-gpu" \
   -device virtio-vga \
   -device virtio-gpu-pci \
   -usb \
   -device usb-ehci,id=ehci \
	-device usb-tablet \
   -serial stdio \
	-serial pty \
   -device virtio-net,netdev=network0 \
	-netdev tap,id=network0,ifname=tap0,script=no,downscript=no \
   -boot d
