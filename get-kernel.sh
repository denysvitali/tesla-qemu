#!/bin/bash

KERNEL_PACKAGE="https://archlinux.org/packages/core/x86_64/linux/download/"

if [ ! -f "cache/linux.tar.xz" ]; then
    wget -O cache/linux.tar.xz "$KERNEL_PACKAGE"
fi

# Extract the kernel
mkdir -p cache/linux
tar -xf cache/linux.tar.xz -C cache/linux

# Create symlink
ln $PWD/cache/linux/usr/lib/modules/*/vmlinuz ./out/vmlinuz
