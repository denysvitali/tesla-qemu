#!/bin/bash

# Uses "Direct Linux Boot" method
# https://qemu-project.gitlab.io/qemu/system/linuxboot.html

RAM="${RAM:-2g}"
SMP="${SMP:-2}"
DISK_IMG="${DISK_IMG:-./out/disk.img}"
KERNEL="${KERNEL:-./cache/alpine-iso/boot/vmlinuz-lts}"
INITRD="${INITRD:-./cache/alpine-iso/boot/initramfs-lts}"
TAP="${TAP:-tap0}"
RESOLUTION="${RESOLUTION:-1920x1200}"
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
DISPLAY_BACKEND="${DISPLAY_BACKEND:-gtk,gl=on}"

qemu-system-x86_64 \
   -enable-kvm -cpu host -m "$RAM" -smp "$SMP" \
   -drive id=hd0,format=raw,file="$DISK_IMG",if=none \
   -device virtio-blk-pci,drive=hd0 \
   -kernel "$KERNEL" \
   -initrd "$INITRD" \
   -vga none \
   -device virtio-gpu-gl-pci,edid=on,xres="$WIDTH",yres="$HEIGHT" \
   -display "$DISPLAY_BACKEND" \
   -append "console=ttyS0 root=/dev/vda rootflags=rw init=/bin/bash modules=loop,squashfs,ext4,virtio,virtio_gpu,virtio_blk,virtio_pci,virtio_net,drm,drm_kms_helper,usbhid,mousedev,uinput,uhci_hcd,hid_generic,virtio_input,hid_multitouch,i2c_hid,input_e video=$RESOLUTION psi=1" \
   -usb \
   -device usb-ehci,id=ehci \
   -device usb-tablet \
   -serial stdio \
   -serial pty \
   -device virtio-net,netdev=network0 \
   -netdev tap,id=network0,ifname="$TAP",script=no,downscript=no \
   -boot d

#-append "console=ttyS0 root=/dev/sda rootflags=rw init=/bin/bash earlyprintk=ttyS0 modules=ext4,qxl,virtio,virtio_blk,virtio_pci,virtio_net fbmem=32M" \
