# Tesla on QEMU

Run Tesla's QtCar infotainment UI from a firmware squashfs image inside QEMU.

## Requirements

- Linux with KVM available
- QEMU
- Docker
- `qemu-img`, `mkfs.ext4`, `mkfs.exfat`, `wget`, `ssh-keygen`, `ssh-add`
- A Tesla firmware squashfs image, for example `firmware/2026.2.3.model3.squashfs`

The build script also uses `sudo` to mount disk images and copy files into the generated root filesystem.

## Network Setup

Create the tap interface used by QEMU:

```bash
./create-tap.sh
```

The defaults are:

- Host tap device: `tap0`
- Host IP: `192.168.90.5/24`
- VM IP: `192.168.90.100`

You can override the host-side settings:

```bash
TAP=tap1 HOST_CIDR=192.168.91.5/24 ./create-tap.sh
```

## Build The Disk Image

```bash
./build.sh firmware/2026.2.3.model3.squashfs
```

This creates `out/disk.img`, copies the Tesla root filesystem into it, adds Xorg/Mesa support, installs the input proxy helpers, applies the current QtCar/DRM patches, and caches Alpine boot files under `cache/alpine-iso`.

The QtCar binary patches are firmware-specific. If a checked byte signature does not match, the build stops instead of silently patching an unknown binary.

## Start The VM

```bash
./qemu/start.sh
```

Useful launch overrides:

```bash
RAM=4g SMP=4 RESOLUTION=1920x1200 TAP=tap0 ./qemu/start.sh
```

Supported environment variables:

- `RAM`, default `2g`
- `SMP`, default `2`
- `DISK_IMG`, default `./out/disk.img`
- `KERNEL`, default `./cache/alpine-iso/boot/vmlinuz-lts`
- `INITRD`, default `./cache/alpine-iso/boot/initramfs-lts`
- `TAP`, default `tap0`
- `RESOLUTION`, default `1920x1200`
- `DISPLAY_BACKEND`, default `gtk,gl=on`

## Start Services In The VM

The VM boots with `init=/bin/bash`. From the QEMU serial console, start networking, device setup, Xorg, the input proxy, and sshd:

```bash
/root/start.sh
```

From another terminal, connect over SSH:

```bash
ssh root@192.168.90.100
```

Then start QtCar as the `tesla` user:

```bash
/root/start-qtcar.sh
```

If everything works, the QtCar UI should appear:

![QtCar UI](./docs/qtcar.jpg)

## Notes

- Touch input is handled through `x11-input-proxy`, which maps the QEMU USB tablet into X11 clicks and a uinput multitouch device exposed as `/dev/input/touch`.
- QtCar is still missing many surrounding Tesla services, so car graphics, maps, emergency-call UI, and other service-backed features may be absent or incomplete.
- The current image setup uses permissive device permissions inside the VM for convenience. Treat the VM image as a local development artifact.
