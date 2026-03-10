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

# Load uinput (needed for touch-proxy to create virtual multitouch device)
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

# Start x11-input-proxy: translates usb-tablet events into both X11 clicks
# and a uinput multitouch device for QtCar's TouchDriver.
/usr/local/bin/x11-input-proxy &

# Wait for x11-input-proxy to create its "Tesla Touch Proxy" uinput device (up to 5s),
# then expose it as /dev/input/touch for QtCar's --touch argument.
for _i in 1 2 3 4 5; do
    for _name in /sys/devices/virtual/input/input*/name; do
        [ -f "$_name" ] || continue
        if grep -q "Tesla Touch Proxy" "$_name"; then
            _input_dir=$(dirname "$_name")
            for _ev in "$_input_dir"/event*; do
                [ -d "$_ev" ] || continue
                _evname=$(basename "$_ev")
                if [ ! -e "/dev/input/$_evname" ] && [ -f "$_ev/dev" ]; then
                    IFS=: read -r _maj _min < "$_ev/dev"
                    mknod "/dev/input/$_evname" c "$_maj" "$_min" 2>/dev/null
                fi
                chmod 666 "/dev/input/$_evname"
                ln -sf "/dev/input/$_evname" /dev/input/touch
                echo "touch: /dev/input/touch -> /dev/input/$_evname"
                break 3
            done
        fi
    done
    echo "touch: waiting for x11-input-proxy device... ($_i/5)"
    sleep 1
done
if [ ! -e /dev/input/touch ]; then
    echo "touch: ERROR - x11-input-proxy device not found, /dev/input/touch missing"
fi

/usr/bin/Xorg &
export DISPLAY=:0

# Wait for X to start
sleep 2

# Set resolution to 1920x1200 (Model 3 native)
xrandr -s 1920x1200

/usr/sbin/sshd -f /etc/ssh/sshd_config_qemu &
