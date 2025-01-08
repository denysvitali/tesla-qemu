#!/bin/bash
set -e

DOCKER_IMAGE="ubuntu-xorg"
CONTAINER_IMAGE_PATH="./cache/ubuntu-xorg-rootfs/"


function log(){
    echo -e "\033[32m$1\033[0m"
}

function err() {
    echo -e "\033[31m$1\033[0m" > /dev/stderr
    exit 1
}

if [ $# -ne 1 ]; then
    err "Usage: $0 <input_file>"
fi

INPUT_FILE=$1

FULL_FILE_PATH=$(realpath -s "$INPUT_FILE")
if [ ! -f "$FULL_FILE_PATH" ]; then
    err "Input file '$INPUT_FILE' does not exist"
fi

DIR_NAME=$(dirname "$FULL_FILE_PATH")
THE_PWD=$(pwd)

# Make sure $THE_PWD is a substring of $DIR_NAME
if [[ ! "$DIR_NAME" == "$THE_PWD"* ]]; then
    err "Input file '$INPUT_FILE' is not in the current directory"
fi

log "Start build"

if [ ! -f "cache/ubuntu.iso" ]; then
    log "Download Ubuntu"
    wget -O cache/ubuntu.iso "https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-live-server-amd64.iso"
    log "Extract ISO"
    pushd cache
    mkdir -p ubuntu-iso
    pushd ubuntu-iso
    7z x ../ubuntu.iso
    popd
    popd
fi

qemu-img create out/boot.img 1G
qemu-img create out/disk.img 6G

mkfs.exfat -n BOOT out/boot.img

# Format FS
mkfs.ext4 ./out/disk.img


log "Mount the disk image and squashfs"

mkdir -p ./mnt/disk
mkdir -p ./mnt/squashfs

sudo mount ./out/disk.img ./mnt/disk
sudo mount -t squashfs "$INPUT_FILE" ./mnt/squashfs

log "Copy files to disk image"
sudo cp -R ./mnt/squashfs/* ./mnt/disk

if [ ! -d "$CONTAINER_IMAGE_PATH" ]; then
    log "Build X11 docker image"
    docker build -o "$CONTAINER_IMAGE_PATH" -f ./docker/Dockerfile.ubuntu ./docker
fi

log "Copy X11 stuff"
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/lib/xorg/modules ./mnt/disk/usr/lib/xorg/
sudo chmod a+x ./mnt/disk/usr/lib/xorg/modules/drivers/*.so
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/lib/x86_64-linux-gnu/dri ./mnt/disk/usr/lib/
sudo chmod a+x ./mnt/disk/usr/lib/dri/*.so
# sudo cp -R "$CONTAINER_IMAGE_PATH"/lib/x86_64-linux-gnu/*.so* ./mnt/disk/lib/

log "Copy scripts"
sudo cp -R ./rootfs/root/ ./mnt/disk/
sudo cp -R ./rootfs/home/tesla ./mnt/disk/home/

log "Remove Tesla Xorg config"
sudo rm ./mnt/disk/etc/X11/xorg.conf.d/10-monitor.conf

log "Copy /boot to disk image"
sudo cp -R ./cache/alpine-iso/boot ./mnt/boot

log "DONE!"

sudo umount ./mnt/disk
sudo umount ./mnt/squashfs
