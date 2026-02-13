# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tesla-QEMU emulates Tesla's infotainment system (QtCar UI) using QEMU virtualization. It extracts Tesla firmware from squashFS images and combines it with a minimal Linux environment, X11, and GPU drivers to run the QtCar application in a VM.

## Key Commands

```bash
# Network setup (once per session)
sudo ip tuntap add dev tap0 mode tap
sudo ip link set tap0 up
sudo ip addr add 192.168.90.5/24 dev tap0

# Build QEMU disk image from firmware
./build.sh firmware/2024.20.9.mcu2

# Start the VM
./qemu/start.sh

# SSH into VM (password: root)
ssh root@192.168.90.100

# Inside VM: start X11 and SSH daemon
/root/start.sh

# Inside VM: start QtCar UI (runs as tesla user)
/root/start-qtcar.sh
```

## Architecture

```
QEMU (KVM, 512MB RAM, 2 CPUs)
└── Linux Kernel (bzImage) + initramfs
    └── Root filesystem (disk.img, ext4)
        └── Xorg + VirtIO GPU + Mesa/VirGL
            └── QtCar (/usr/tesla/UI/bin/QtCar)
```

### Key Directories

- `firmware/` - Tesla squashFS firmware images (`.mcu2` files)
- `out/` - Build outputs: `disk.img` (6GB), `boot.img` (1GB), `bzImage`
- `cache/` - Cached dependencies: Ubuntu ISO extraction, SSH keys, Alpine ISO
- `rootfs/` - Scripts copied to VM image during build
  - `rootfs/root/start.sh` - VM init: network, Xorg, sshd
  - `rootfs/home/tesla/start.sh` - QtCar launcher with env vars
- `mnt/` - Temporary mount points for build process

### Build Process (build.sh)

1. Creates disk images (1GB boot + 6GB main ext4)
2. Mounts Tesla squashFS firmware and copies to disk
3. Builds Ubuntu Docker image for X11/GPU drivers if not cached
4. Copies Xorg modules, DRI drivers, and Mesa libraries
5. Generates SSH host keys and copies authorized_keys
6. Configures tesla user shell and sshd

### VM Configuration

- **Display**: VirtIO GPU with GTK frontend, OpenGL enabled
- **Network**: Tap interface (tap0), VM IP: 192.168.90.100
- **Input**: USB mouse/tablet devices
- **Kernel modules**: virtio, virtio_gpu, virtio_blk, virtio_net, drm, usbhid

### QtCar Environment

The QtCar application requires specific environment variables:
- `DISPLAY=:0`
- `LD_LIBRARY_PATH=/usr/tesla/UI/lib:/lib`
- `MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu_dri`

Main binary: `/usr/tesla/UI/bin/QtCar`

## Known Limitations

- Touch/input doesn't work - UI uses custom kernel driver (`tesla-uinput`)
- Missing Tesla services (car graphics, maps, E112 UI) - only QtCar starts
- Build requires sudo for mounting filesystems
- Docker required for X11 environment build
