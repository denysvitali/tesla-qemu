#!/bin/bash
set -euo pipefail

CONTAINER_IMAGE_PATH="./cache/ubuntu-xorg-rootfs/"
DISK_MOUNT="./mnt/disk"
SQUASHFS_MOUNT="./mnt/squashfs"
ALPINE_ISO_MOUNT="./mnt/alpine-iso"


function log(){
    echo -e "\033[32m$1\033[0m"
}

function err() {
    echo -e "\033[31m$1\033[0m" > /dev/stderr
    exit 1
}

function cleanup() {
    local status=$?

    if mountpoint -q "$ALPINE_ISO_MOUNT" 2>/dev/null; then
        sudo umount "$ALPINE_ISO_MOUNT" || true
    fi
    if mountpoint -q "$DISK_MOUNT" 2>/dev/null; then
        sudo umount "$DISK_MOUNT" || true
    fi
    if mountpoint -q "$SQUASHFS_MOUNT" 2>/dev/null; then
        sudo umount "$SQUASHFS_MOUNT" || true
    fi

    exit "$status"
}

trap cleanup EXIT

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

mkdir -p out cache mnt

qemu-img create out/boot.img 1G
qemu-img create out/disk.img 6G

mkfs.exfat -n BOOT out/boot.img

# Format FS
mkfs.ext4 ./out/disk.img


log "Mount the disk image and squashfs"

mkdir -p "$DISK_MOUNT"
mkdir -p "$SQUASHFS_MOUNT"

sudo mount ./out/disk.img "$DISK_MOUNT"
sudo mount -t squashfs "$INPUT_FILE" "$SQUASHFS_MOUNT"

log "Copy files to disk image"
sudo cp -R "$SQUASHFS_MOUNT"/* "$DISK_MOUNT" || true

if [ ! -d "$CONTAINER_IMAGE_PATH" ]; then
    log "Build X11 docker image"
    docker build -o "$CONTAINER_IMAGE_PATH" -f ./docker/Dockerfile.ubuntu ./docker
fi

log "Copy X11 stuff"
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/lib/xorg/modules ./mnt/disk/usr/lib/xorg/
sudo chmod a+x ./mnt/disk/usr/lib/xorg/modules/drivers/*.so
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/lib/x86_64-linux-gnu/dri ./mnt/disk/usr/lib/
sudo chmod a+x ./mnt/disk/usr/lib/dri/*.so

log "Copy Mesa/GL libraries"
# These libraries are needed for Xorg glamor, EGL, and OpenGL ES 2 (QtCar).
# Use cp -L to follow symlinks and get real files. Install into /usr/lib/ so
# both Xorg modules and applications find them without LD_LIBRARY_PATH hacks.
#
# Glamor in Xorg uses dlopen("libgbm.so.1") at runtime. If ANY transitive
# dependency of libgbm is missing, the dlopen fails silently and glamor is
# disabled entirely (no glamor lines in Xorg.log). We must provide the full
# dependency tree.
MESA_LIBS=(
    # --- Mesa DRI / GL core ---
    libLLVM-15.so.1
    libglapi.so.0
    libvirglrenderer.so.1
    libEGL.so.1
    libEGL_mesa.so.0
    libGLdispatch.so.0
    libGLESv2.so.2
    libGL.so.1
    libGLX.so.0
    libGLX_mesa.so.0
    libepoxy.so.0
    # --- GBM + DRM (glamor dlopen chain) ---
    libgbm.so.1
    libdrm.so.2
    libdrm_radeon.so.1
    libdrm_amdgpu.so.1
    libdrm_nouveau.so.2
    # --- libgbm transitive deps ---
    libexpat.so.1
    libffi.so.8
    libwayland-server.so.0
    libwayland-client.so.0
    # --- Xorg binary runtime deps ---
    libudev.so.1
    libsystemd.so.0
    libpciaccess.so.0
    libpixman-1.so.0
    libxcvt.so.0
    libXfont2.so.2
    libxshmfence.so.1
    libdbus-1.so.3
    libgcrypt.so.20
    # --- Transitive deps of above ---
    libelf.so.1
    libzstd.so.1
    libsensors.so.5
    libedit.so.2
    libtinfo.so.6
    libbsd.so.0
    libmd.so.0
    libaudit.so.1
    libunwind.so.8
    libselinux.so.1
    liblzma.so.5
)

SRC="$CONTAINER_IMAGE_PATH/usr/lib/x86_64-linux-gnu"
for lib in "${MESA_LIBS[@]}"; do
    # -L follows symlinks so we always get the real file
    sudo cp -L "$SRC/$lib" "./mnt/disk/usr/lib/$lib"
done

log "Create DRI symlink for Ubuntu Xorg modules"
sudo mkdir -p ./mnt/disk/usr/lib/x86_64-linux-gnu
sudo ln -sf /usr/lib/dri ./mnt/disk/usr/lib/x86_64-linux-gnu/dri

sudo cp "$CONTAINER_IMAGE_PATH"/usr/bin/Xorg ./mnt/disk/usr/bin/
sudo cp "$CONTAINER_IMAGE_PATH"/usr/bin/X ./mnt/disk/usr/bin/
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/lib/xorg ./mnt/disk/usr/lib/
sudo mkdir -p ./mnt/disk/usr/share/glvnd/egl_vendor.d
cat << EOF | sudo tee ./mnt/disk/usr/share/glvnd/egl_vendor.d/50_mesa.json
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "libEGL_mesa.so.0"
    }
}
EOF


log "Compile touch-proxy (static, translates usb-tablet ABS to ABS_MT multitouch)"
gcc -static -o out/touch-proxy tools/touch-proxy.c

log "Copy touch-proxy"
sudo cp out/touch-proxy ./mnt/disk/usr/local/bin/touch-proxy
sudo chmod a+x ./mnt/disk/usr/local/bin/touch-proxy

log "Compile x11-input-proxy (injects X11 clicks and creates uinput touch)"
docker run --rm \
    -v "$(pwd)/tools:/src:ro" \
    -v "$(pwd)/out:/out" \
    ubuntu:22.04 bash -c "
        apt-get update -qq &&
        apt-get install -y -qq gcc libx11-dev libxtst-dev linux-libc-dev >/dev/null 2>&1 &&
        gcc -O2 -o /out/x11-input-proxy /src/x11-input-proxy.c -lX11 -lXtst
    "

log "Copy x11-input-proxy"
sudo cp out/x11-input-proxy ./mnt/disk/usr/local/bin/x11-input-proxy
sudo chmod a+x ./mnt/disk/usr/local/bin/x11-input-proxy

log "Compile vblank-fix LD_PRELOAD shim (intercepts DRM_IOCTL_WAIT_VBLANK)"
docker run --rm \
    -v "$(pwd)/tools:/src:ro" \
    -v "$(pwd)/out:/out" \
    ubuntu:22.04 bash -c "
        apt-get update -qq && apt-get install -y -qq gcc >/dev/null 2>&1 &&
        gcc -O2 -shared -fPIC -o /out/vblank-fix.so /src/vblank-fix.c -lc
    "

log "Copy vblank-fix.so"
sudo mkdir -p ./mnt/disk/usr/local/lib
sudo cp out/vblank-fix.so ./mnt/disk/usr/local/lib/vblank-fix.so

log "Patch libQtCarUIFramework.so for touch input in QEMU"
# Four patches to libQtCarUIFramework.so (Model 3 ICE, firmware 2026.2.3):
#
# 1. NOP the conditional jump in DisplayDevice constructor that skips
#    loading the touch driver based on a display-type flag (this->0xd70).
#    At 0x89cef9: "jne 0x89d8f1" (0f 85 f2 09 00 00) → 6x NOP
#
# 2. Fix NULL theTouchDevice crash: the constructor reads theTouchDevice
#    (a BSS global, zero-initialized) and calls loadTouchDriver on it.
#    Since getInstance() hasn't been called yet, theTouchDevice is NULL,
#    causing a segfault at loadTouchDriver+0x17 (deref NULL+0xfa8).
#    Fix: replace the theTouchDevice load (17 bytes at 0x89cf28) with a
#    call to TouchDevice::getInstance(DisplayDevice*) via PLT, which
#    creates and caches a valid TouchDevice object.
#    New code: mov %r12,%rdi; call getInstance@plt; xchg %rax,%rbx; mov rdi,[rip+off]
#    getInstance@plt = 0x4e43e0, call offset from 0x89cf30 = 0xffc474b0
#    HighPrecisionTouch rip-rel from 0x89cf39 = 0x74db87 (target 0xfeaac0)
#
# 3. Patch ManagedQtCarTouchDriver::isPowered() to always return true.
#    At 0xaee050: → mov eax,1; ret (b8 01 00 00 00 c3)
#
# 4. Patch ManagedQtCarTouchDriver::isDisplayOn() to always return true.
#    At 0xaede20: → mov eax,1; ret (b8 01 00 00 00 c3)
TOUCH_LIB="./mnt/disk/usr/tesla/UI/lib/libQtCarUIFramework.so"
sudo python3 - "$TOUCH_LIB" <<'PY'
import sys

path = sys.argv[1]
patches = [
    (0x89cef9, bytes.fromhex('0f85f2090000'), bytes.fromhex('909090909090'), 'NOP touch-skip jump in DisplayDevice ctor'),
    (0x89cf28, None, bytes.fromhex('4c89e7e8b074c4ff4893488b3d87db7400'), 'call getInstance before loadTouchDriver'),
    (0xaee050, None, bytes.fromhex('b801000000c3'), 'ManagedQtCarTouchDriver::isPowered() -> return true'),
    (0xaede20, None, bytes.fromhex('b801000000c3'), 'ManagedQtCarTouchDriver::isDisplayOn() -> return true'),
]

with open(path, 'r+b') as f:
    for offset, expected, patch, desc in patches:
        f.seek(offset)
        orig = f.read(len(patch))
        if orig == patch:
            print(f'  {offset:#x}: already patched ({desc})')
            continue
        if expected is not None and orig != expected:
            raise SystemExit(
                f'{path}: unexpected bytes at {offset:#x}: '
                f'{orig.hex()} != {expected.hex()} ({desc})'
            )
        f.seek(offset)
        f.write(patch)
        print(f'  {offset:#x}: {orig.hex()} -> {patch.hex()}  ({desc})')
PY

log "Patch libdrm.so.2: drmWaitVBlank -> return 0 (VirtIO GPU has no vblank)"
# VirtIO GPU doesn't implement DRM_IOCTL_WAIT_VBLANK; every call returns ENOTSUP.
# QtCar gates frame presentation on a successful vblank wait, so the screen
# stays black.  Patch drmWaitVBlank (file offset 0x97e0, .text VMA == file
# offset for this lib) to xor eax,eax / ret immediately after endbr64.
#   0x97e4: 31 c0 c3  (xor eax,eax; ret)
LIBDRM="./mnt/disk/usr/lib/libdrm.so.2"
sudo python3 - "$LIBDRM" <<'PY'
import sys

path = sys.argv[1]
patches = [
    (0x97e4, None, bytes.fromhex('31c0c3'), 'drmWaitVBlank -> xor eax,eax; ret'),
]

with open(path, 'r+b') as f:
    for offset, expected, patch, desc in patches:
        f.seek(offset)
        orig = f.read(len(patch))
        if orig == patch:
            print(f'  {offset:#x}: already patched ({desc})')
            continue
        if expected is not None and orig != expected:
            raise SystemExit(
                f'{path}: unexpected bytes at {offset:#x}: '
                f'{orig.hex()} != {expected.hex()} ({desc})'
            )
        f.seek(offset)
        f.write(patch)
        print(f'  {offset:#x}: {orig.hex()} -> {patch.hex()}  ({desc})')
PY

log "Copy input libraries (needed by Xorg libinput driver)"
INPUT_LIBS=(
    libinput.so.10
    libevdev.so.2
    libmtdev.so.1
    libwacom.so.9
)
for lib in "${INPUT_LIBS[@]}"; do
    if [ -f "$SRC/$lib" ]; then
        sudo cp -L "$SRC/$lib" "./mnt/disk/usr/lib/$lib"
    fi
done

log "Copy libwacom data (needed by libinput)"
sudo mkdir -p ./mnt/disk/usr/share/libwacom
sudo cp -R "$CONTAINER_IMAGE_PATH"/usr/share/libwacom/* ./mnt/disk/usr/share/libwacom/

log "Copy scripts"
sudo cp -R ./rootfs/root/ ./mnt/disk/
sudo cp -R ./rootfs/home/tesla ./mnt/disk/home/

log "Remove Tesla Xorg config"
sudo rm -f ./mnt/disk/etc/X11/xorg.conf.d/10-monitor.conf

log "Copy Xorg modesetting config"
sudo cp ./rootfs/etc/X11/xorg.conf.d/10-modesetting.conf ./mnt/disk/etc/X11/xorg.conf.d/

log "Copy Xorg input config"
sudo cp ./rootfs/etc/X11/xorg.conf.d/20-input.conf ./mnt/disk/etc/X11/xorg.conf.d/


if [ ! -f "./cache/ssh/ssh_host_ecdsa_key" ]; then
    log "Generate SSH host keys"
    mkdir -p ./cache/ssh
    ssh-keygen -t ecdsa -f ./cache/ssh/ssh_host_ecdsa_key -N ""
    ssh-keygen -t ed25519 -f ./cache/ssh/ssh_host_ed25519 -N ""
fi

# Download and extract Alpine ISO boot files
ALPINE_VERSION="3.19.1"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-${ALPINE_VERSION}-x86_64.iso"
ALPINE_CACHE_DIR="./cache/alpine-iso"

if [ ! -d "$ALPINE_CACHE_DIR" ]; then
    log "Download Alpine Linux ISO"
    mkdir -p ./cache
    wget -O ./cache/alpine-standard.iso "$ALPINE_ISO_URL"

    log "Extract Alpine boot files"
    mkdir -p "$ALPINE_CACHE_DIR"
    mkdir -p "$ALPINE_ISO_MOUNT"
    sudo mount -o loop ./cache/alpine-standard.iso "$ALPINE_ISO_MOUNT"
    sudo cp -R "$ALPINE_ISO_MOUNT"/* "$ALPINE_CACHE_DIR/"
    sudo umount "$ALPINE_ISO_MOUNT"
    rmdir "$ALPINE_ISO_MOUNT"
fi

log "Copy SSH host keys"
sudo mkdir -p ./mnt/disk/var/etc/ssh
sudo cp ./cache/ssh/ssh_host_ecdsa_key ./mnt/disk/var/etc/ssh/ssh_host_ecdsa_key
sudo cp ./cache/ssh/ssh_host_ed25519 ./mnt/disk/var/etc/ssh/ssh_host_ed25519

log "Adding our SSH public keys"
sudo mkdir -p ./mnt/disk/root/.ssh
ssh-add -L | sudo tee "./mnt/disk/root/.ssh/authorized_keys"

log "Personalizing /home/tesla"
sudo cp -R ./mnt/disk/root/.ssh ./mnt/disk/home/tesla/

log "Allow shell for tesla user"
sudo sed -i -E 's@tesla:(.*):/bin/false@tesla:\1:/bin/bash@' ./mnt/disk/etc/passwd


log "Add custom sshd config"
cat << EOF | sudo tee ./mnt/disk/etc/ssh/sshd_config_qemu
PermitRootLogin yes
EOF

log "Copy /boot to disk image"
sudo mkdir -p ./mnt/disk/boot
sudo cp -R ./cache/alpine-iso/boot/* ./mnt/disk/boot/

log "DONE!"

trap - EXIT
cleanup
