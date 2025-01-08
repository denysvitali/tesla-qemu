#!/bin/bash

# Exit on error
set -e

BUSYBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
INITRD_DIR="initrd"

# Create initrd directory structure
mkdir -p "${INITRD_DIR}/bin"
mkdir -p "${INITRD_DIR}/dev"
mkdir -p "${INITRD_DIR}/proc"
mkdir -p "${INITRD_DIR}/sys"
mkdir -p "${INITRD_DIR}/etc"
mkdir -p "${INITRD_DIR}/mnt"

# Download busybox
if [ ! -f "${INITRD_DIR}/bin/busybox" ]; then
    echo "Downloading busybox..."
    wget -O "${INITRD_DIR}/bin/busybox" "${BUSYBOX_URL}"
    chmod +x "${INITRD_DIR}/bin/busybox"
fi

# Create symlinks for busybox applets
cd "${INITRD_DIR}/bin"
for applet in $("./busybox" --list); do
    ln -sf busybox "$applet"
done
cd ../..

# Create the compressed CPIO archive
cd "${INITRD_DIR}"
find . | cpio -H newc -o | gzip > ../out/initramfs.img
cd ..

echo "Ramdisk image created as initramfs.img"
