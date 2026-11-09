# Customization Guide

This guide shows you how to customize various aspects of the distrox distribution.

## Table of Contents

- [Kernel Customization](#kernel-customization)
- [Rootfs Customization](#rootfs-customization)
- [Userspace (Zig) Customization](#userspace-zig-customization)
- [Init System Customization](#init-system-customization)
- [Bootloader Customization](#bootloader-customization)
- [Adding Software](#adding-software)
- [Network Configuration](#network-configuration)
- [Advanced Customization](#advanced-customization)
- [Testing Customizations](#testing-customizations)

## Kernel Customization

### Using menuconfig

The easiest way to customize the kernel:

```bash
# Build the kernel once so the distrox:kernel image exists
make kernel

# Start the kernel configuration menu
docker run -it --rm -v "$(pwd):/work" distrox:kernel bash
# inside the container:
cd /build/linux
make menuconfig
cp .config /work/linux.config

# back on the host, rebuild with the new configuration
make kernel initramfs iso
```

### Common Kernel Options

#### Enable Networking

```sh
Networking support --->
    [*] Networking support
    Networking options --->
        [*] TCP/IP networking
        [*] IP: kernel level autoconfiguration
```

#### Enable USB Support

```sh
Device Drivers --->
    [*] USB support --->
        <*> EHCI HCD (USB 2.0) support
        <*> OHCI HCD support
        <*> USB Mass Storage support
```

#### Enable Filesystem Support

```sh
File systems --->
    <*> The Extended 4 (ext4) filesystem
    <*> FUSE (Filesystem in Userspace) support
    DOS/FAT/NT Filesystems --->
        <*> VFAT (Windows-95) fs support
```

### Manual Configuration

Edit `linux.config` directly (it is fed to `make olddefconfig` in the
`kernel-builder` stage):

```bash
# Enable feature
CONFIG_FEATURE_NAME=y

# Enable as module
CONFIG_FEATURE_NAME=m

# Disable feature
# CONFIG_FEATURE_NAME is not set
```

**Note:** do NOT strip `bzImage` — it is a raw binary with an embedded EFI
stub; stripping corrupts the boot sector.

## Rootfs Customization

The Alpine rootfs is built in the `rootfs-builder` stage of the `Dockerfile`.

### Change Installed Packages

Edit the `apk add` list:

```dockerfile
RUN apk add --no-cache \
        alpine-base \
        openrc \
        python3 \
    && rm -rf /var/cache/apk/*
```

Then rebuild: `make rootfs initramfs iso`. Dev tools are intentionally
excluded — it is usually cheaper to `apk add` them inside the running guest
(Assuming the network works, see [Network Configuration](#network-configuration)).

### Runlevels / Services

The standard OpenRC runlevels are enabled in the Dockerfile (`rc-update add
...`). To add a service, add a `RUN rc-update add <service> default` line
there, or run `rc-update` inside the guest.

### Console Login

The rootfs spawns an auto root shell on tty1 (askfirst) and ttyS0
(respawn) via `/etc/inittab`, configured in the Dockerfile.

## Userspace (Zig) Customization

Zig sources live in `userspace/` (a busybox-style multi-call binary,
dispatching on `argv[0]` or the first argument) and `init/` (PID 1).

### Add a New Command

1. Add the implementation under `userspace/src/`
2. Register it in `userspace/src/commands/listing.zig` (keep the
   `enabled` flag accurate for Linux)
3. Sync the `ZIG_COMMANDS` list in `scripts/mkinitramfs.sh` (it generates the
   profile aliases that route commands to the Zig binary)
4. Rebuild:

```bash
make userspace initramfs iso
```

### Build Tuning

- Userspace: `anyzig 0.15.1`, `-Doptimize=ReleaseFast`, target
  `x86_64-linux-musl` (see the `make userspace` rule in the `Makefile`)
- Init: `anyzig 0.16.0`, `--release=small`, target `x86_64-linux-musl`

## Init System Customization

### Zig PID 1 (`/init`)

The Zig init in `init/` becomes `/init` in the initramfs. See
`init/README.md` for how it works (SIGCHLD handler, mounts, device nodes,
fork/exec shell loop). To change behavior (extra mounts, different shell,
services), edit `init/src/main.zig` and rebuild:

```bash
make init initramfs iso
```

The initramfs (`scripts/mkinitramfs.sh`) only uses the Zig init if
`init/zig-out/bin/init` exists and is executable — otherwise it falls back
to the shell script `init.sh`.

### Shell Fallback (`init.sh`)

`init.sh` is copied into the rootfs image as `/init` (see the `rootfs-builder`
stage) so there is always a bootable fallback. Edit it for quick experiments
without a Zig toolchain.

## Bootloader Customization

### Syslinux Configuration

Edit `syslinux.cfg`:

```cfg
# Change default boot entry
DEFAULT my-custom-entry

# Change timeout (in deciseconds)
TIMEOUT 50

# Add custom boot entry
LABEL my-custom-entry
    MENU LABEL My Custom Linux
    KERNEL /bzImage
    APPEND initrd=/initramfs custom_param=value
```

### Boot Parameters

Common kernel boot parameters:

```sh
quiet           # Suppress most boot messages
loglevel=7      # Verbose kernel messages
console=ttyS0   # Serial console output
ro              # Mount root read-only
rw              # Mount root read-write
```

## Adding Software

### Method 1: Bake into the Rootfs

Add packages (Alpine apk) to the `apk add` list in the `rootfs-builder` stage
of the `Dockerfile` — see [Rootfs Customization](#rootfs-customization).

### Method 2: Static Zig/Go/C Binaries

Cross-compile a static binary on your host, then inject it into the
initramfs:

```bash
make userspace init initramfs iso   # mkinitramfs copies everything from userspace/zig-out/bin/ into /usr/local/bin/
```

For your own binaries, drop them into `userspace/zig-out/bin/` (they will
land in `/usr/local/bin/` of the initramfs), or extend
`scripts/mkinitramfs.sh`.

### Method 3: Install Inside the Guest

Boot and use `apk add` (the rootfs ships `apk` and DHCP on eth0). Nothing
built this way survives a reboot (the initramfs is in RAM) — bake permanent
changes into the Dockerfile instead.

### Example: Add Python

```dockerfile
# In the rootfs-builder stage of the Dockerfile:
RUN apk add --no-cache python3
```

## Network Configuration

The Alpine rootfs ships `ifupdown` with this `/etc/network/interfaces`
(written in the `rootfs-builder` stage):

```sh
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

In QEMU, make sure the NIC driver is in the kernel (`CONFIG_E1000=y` is in
`linux.config`) and boot with networking:

```bash
make qemu-network
```

### Static IP (inside the guest)

```bash
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### DHCP (inside the guest)

```bash
udhcpc -i eth0
```

## Advanced Customization

### Different Kernel Version

Override the `LINUX_VERSION` build argument of the `kernel-builder` stage:

```bash
docker build --target kernel-builder \
    --build-arg LINUX_VERSION=v6.7 \
    -t distrox:kernel .
docker create --name distrox-kernel distrox:kernel
mkdir -p build
docker cp distrox-kernel:/build/linux/arch/x86/boot/bzImage build/bzImage
docker rm distrox-kernel
```

Then continue with `make initramfs iso`. The default in the Dockerfile is
`ARG LINUX_VERSION=master`.

### Adding System Users

Bake into the rootfs (Dockerfile, `rootfs-builder` stage):

```dockerfile
RUN echo 'user:x:1000:1000:user:/home/user:/bin/ash' >> /etc/passwd && \
    mkdir -p /home/user && chown 1000:1000 /home/user
```

### Custom Welcome Message

Write `/etc/motd` in the `rootfs-builder` stage:

```dockerfile
RUN cat > /etc/motd << 'EOF'
╔═══════════════════════════════════════╗
║   Welcome to Custom Linux System      ║
║   Built with distrox                  ║
╚═══════════════════════════════════════╝
EOF
```

`ash` shows `/etc/motd` on login automatically.

### Persistent Storage

Mount a persistent volume:

```bash
# inside the guest
mkdir -p /data
mount /dev/sda1 /data
```

In QEMU:

```bash
qemu-img create -f raw data.img 1G

qemu-system-x86_64 \
    -cdrom build/output.iso \
    -m 2048M \
    -drive file=data.img,format=raw
```

## Testing Customizations

### Build and Test

```bash
make build       # full chain: kernel + rootfs + userspace + init + initramfs + iso
make qemu-nographic
```

### Quick Iteration

Only some steps changed? Re-run just those (each is cached):

```bash
make rootfs initramfs iso     # after Dockerfile rootfs changes
make userspace initramfs iso  # after userspace/ changes
make iso                      # after syslinux.cfg changes (no rebuild needed)
```

After a kernel config change:

```bash
make kernel initramfs iso
```

### Inspect the initramfs directly

```bash
mkdir -p /tmp/initramfs && cd /tmp/initramfs
gunzip -c ../../build/initramfs | bsdtar -xf -
# inspect / init script, /usr/local/bin (Zig tools), etc.
```

Or iterate inside QEMU directly — the guest ships `apk` and a root shell as
PID 1 host, so you can prototype changes live and port them into the
Dockerfile / Zig sources once they work (RAM-only, nothing persists).

## Best Practices

1. **Test incrementally** — re-run only the affected make targets
2. **Keep backups** — save working configurations (`linux.config`, syslinux.cfg, Dockerfile)
3. **Document changes** — comment your modifications
4. **Use version control** — track configuration changes with Git
5. **Start simple** — add complexity gradually
6. **Remember ephemerality** — the initramfs is RAM-only; bake permanent changes into the Dockerfile / Zig sources

## Resources

- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)
- [Alpine Wiki](https://wiki.alpinelinux.org/wiki/Main_Page)
- [OpenRC](https://wiki.gentoo.org/wiki/OpenRC)
- [Syslinux Documentation](https://wiki.syslinux.org/)
- [Linux From Scratch](http://www.linuxfromscratch.org/)

## Need Help?

- Check existing issues on GitHub
- Open a new issue with details
- Include your configuration files
- Share error messages and logs
