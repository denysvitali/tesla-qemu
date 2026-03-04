#!/bin/bash

# Network
ip link set lo up
ip addr add 192.168.90.100/24 dev eth0
ip link set eth0 up

chown -R tesla:tesla /home/tesla

# With init=/bin/bash, no init system sets up virtual filesystems.
# Mount them so modprobe, sysfs device discovery, etc. work.
mount -t sysfs sysfs /sys 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts 2>/dev/null

# Mount modloop to get Alpine kernel modules
mkdir -p /.modloop
mount -o loop /boot/modloop-lts /.modloop
ln -sf /.modloop/modules/6.6.14-0-lts /lib/modules/6.6.14-0-lts

# Load virtio GPU driver (needed for DRM/KMS)
modprobe virtio_gpu

# Load USB controller + HID stack (QEMU uses usb-ehci)
modprobe ehci_pci
modprobe ehci_hcd 2>/dev/null
modprobe usbhid
modprobe hid_generic

# Load evdev (creates /dev/input/eventN device nodes for input devices)
modprobe evdev

# Load uinput (needed for touch-proxy to create virtual input devices)
modprobe uinput

# Create /dev/input/ device nodes from sysfs.
# devtmpfs may not populate /dev/input/ after initramfs switch_root,
# so we create them manually from /sys/class/input/*/dev.
mkdir -p /dev/input
for dev in /sys/class/input/event*/dev; do
    [ -f "$dev" ] || continue
    name=$(basename "$(dirname "$dev")")
    IFS=: read -r major minor < "$dev"
    mknod "/dev/input/$name" c "$major" "$minor" 2>/dev/null
    chmod 666 "/dev/input/$name"
done

# Also create /dev/uinput if devtmpfs didn't
if [ ! -e /dev/uinput ] && [ -f /sys/class/misc/uinput/dev ]; then
    IFS=: read -r major minor < /sys/class/misc/uinput/dev
    mknod /dev/uinput c "$major" "$minor" 2>/dev/null
fi
chmod 666 /dev/uinput

# Allow non-root users to access GPU
chmod 666 /dev/dri/*

# Create DRI path symlink (Ubuntu Xorg expects this path)
mkdir -p /usr/lib/x86_64-linux-gnu
ln -sf /usr/lib/dri /usr/lib/x86_64-linux-gnu/dri

# Update Xorg input config with actual device paths.
# Event numbers can vary, so detect them from sysfs.
TABLET_DEV=""
KBD_DEV=""
for name_file in /sys/class/input/event*/device/name; do
    evname=$(cat "$name_file" 2>/dev/null)
    evdev="/dev/input/$(basename "$(dirname "$(dirname "$name_file")")")"
    case "$evname" in
        *QEMU*Tablet*) TABLET_DEV="$evdev" ;;
        *keyboard*|*Translated*) KBD_DEV="$evdev" ;;
    esac
done
if [ -n "$TABLET_DEV" ]; then
    sed -i "s|/dev/input/event1|$TABLET_DEV|" /etc/X11/xorg.conf.d/20-input.conf
    echo "Xorg input: tablet=$TABLET_DEV"
fi
if [ -n "$KBD_DEV" ]; then
    sed -i "s|/dev/input/event0|$KBD_DEV|" /etc/X11/xorg.conf.d/20-input.conf
    echo "Xorg input: keyboard=$KBD_DEV"
fi

/usr/bin/Xorg &
export DISPLAY=:0

# Wait for X to start
sleep 2

# Set resolution to 1080x1920 (portrait, Tesla center display)
xrandr -s 1200x1920

# Start x11-input-proxy: reads QEMU usb-tablet events, injects them into
# X11 via XTest (bypasses Xorg input driver issues), and creates a uinput
# multitouch device for QtCar's TouchDriver at /dev/input/touch.
/usr/local/bin/x11-input-proxy &
sleep 1

# Create the device node for the uinput device x11-input-proxy just made,
# then symlink it to /dev/input/touch for QtCar's TouchDriver.
for evdev in /sys/devices/virtual/input/input*/name; do
    if grep -q "Tesla Touch Proxy" "$evdev" 2>/dev/null; then
        INPUT_DIR=$(dirname "$evdev")
        for ev in "$INPUT_DIR"/event*; do
            [ -d "$ev" ] || continue
            EVENT_NAME=$(basename "$ev")
            if [ ! -e "/dev/input/$EVENT_NAME" ] && [ -f "$ev/dev" ]; then
                IFS=: read -r major minor < "$ev/dev"
                mknod "/dev/input/$EVENT_NAME" c "$major" "$minor" 2>/dev/null
            fi
            chmod 666 "/dev/input/$EVENT_NAME"
            ln -sf "/dev/input/$EVENT_NAME" /dev/input/touch
            echo "touch-proxy: created /dev/input/touch -> /dev/input/$EVENT_NAME"
            break
        done
        break
    fi
done

/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
