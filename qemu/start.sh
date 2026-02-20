#!/bin/bash

# Uses "Direct Linux Boot" method
# https://qemu-project.gitlab.io/qemu/system/linuxboot.html

qemu-system-x86_64 \
   -enable-kvm -cpu host -m 512m -smp 2 \
   -drive id=hd0,format=raw,file=./out/disk.img,if=none \
   -device virtio-blk-pci,drive=hd0 \
   -kernel ./cache/alpine-iso/boot/vmlinuz-lts \
   -initrd ./cache/alpine-iso/boot/initramfs-lts \
   -vga none \
   -device virtio-gpu-gl-pci,edid=on,xres=1200,yres=1920 \
   -display gtk,gl=on,zoom-to-fit=on \
   -append "console=ttyS0 root=/dev/vda rootflags=rw init=/bin/bash modules=loop,squashfs,ext4,virtio,virtio_gpu,virtio_blk,virtio_pci,virtio_net,drm,drm_kms_helper,usbhid,mousedev,uinput,uhci_hcd,hid_generic,virtio_input,hid_multitouch,i2c_hid,input_e video=1200x1920" \
   -usb \
   -device usb-ehci,id=ehci \
   -device usb-mouse \
   -device usb-tablet \
   -serial stdio \
   -serial pty \
   -device virtio-net,netdev=network0 \
   -netdev tap,id=network0,ifname=tap0,script=no,downscript=no \
   -boot d

#-append "console=ttyS0 root=/dev/sda rootflags=rw init=/bin/bash earlyprintk=ttyS0 modules=ext4,qxl,virtio,virtio_blk,virtio_pci,virtio_net fbmem=32M" \
