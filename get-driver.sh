#!/bin/bash

DRIVER_VERSION="0.1.5+git20200331-3"
DRIVER_URL="http://de.archive.ubuntu.com/ubuntu/pool/main/x/xserver-xorg-video-qxl/xserver-xorg-video-qxl_${DRIVER_VERSION}_amd64.deb"

if [ ! -f "cache/xf86-video-qxl-$DRIVER_VERSION.deb" ]; then
    wget -O cache/xf86-video-qxl-$DRIVER_VERSION.deb "$DRIVER_URL"
fi

# Extract the driver
mkdir -p cache/xf86-video-qxl
pushd cache/xf86-video-qxl || exit
ar x ../xf86-video-qxl-$DRIVER_VERSION.deb
tar -xf data.tar.zst
popd || exit
