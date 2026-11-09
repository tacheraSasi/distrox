# Architecture Overview

This document describes the architecture and design decisions of the distrox project.

## System Architecture

```sh
┌───────────────────────────────────────────────────────────────┐
│                         Build Pipeline                        │
├──────────────────────┬────────────────────────────────────────┤
│  Docker (heavy)      │  Local (fast, Makefile)                │
├──────────────────────┼────────────────────────────────────────┤
│  kernel-builder      │  make userspace (zig coreutils)        │
│  (debian + torvalds  │  make init      (zig PID 1)            │
│   linux -> bzImage)  │  make initramfs (rootfs + zig + init)  │
│                      │  make iso       (xorriso + isolinux)   │
│  rootfs-builder      │                                        │
│  (alpine ->          │                                        │
│   rootfs.tar.gz)     │                                        │
└──────────────────────┴────────────────────────────────────────┘
```

## Component Overview

### 1. Build System

#### Dockerfile

Multi-stage build with exactly 2 stages:

1. **kernel-builder** (debian:sid-slim): shallow-clones torvalds/linux,
   applies `linux.config` via `make olddefconfig`, compiles `bzImage` with
   `make -j$(nproc)`. The kernel source tree is cached in a BuildKit cache
   mount (`/build/cache`).
2. **rootfs-builder** (alpine): installs Alpine base + OpenRC, configures
   runlevels, `/etc/inittab` (auto root shell on tty1 + ttyS0), networking
   (loopback + DHCP on eth0), and packs the tree as `rootfs.tar.gz`
   (excluding proc/sys/dev/run/tmp and runtime config files).

Everything else happens locally on the host via the Makefile:

- `make userspace` — `anyzig 0.15.1` cross-compiles `userspace/` to static
  `x86_64-linux-musl` binaries (`userspace/zig-out/bin/`, ReleaseFast)
- `make init` — `anyzig 0.16.0` builds the Zig PID 1 from `init/`
  (`init/zig-out/bin/init`)
- `make initramfs` — `scripts/mkinitramfs.sh` unpacks `rootfs.tar.gz`,
  injects the Zig binaries into `/usr/local/bin`, writes profile aliases,
  replaces `/init` with the Zig PID 1, and repacks as a newc cpio.gz
  (archived with `bsdtar`)
- `make iso` — downloads syslinux 6.03 once into `build/syslinux/`, then
  assembles a hybrid ISOLINUX bootable ISO with `xorriso -as mkisofs`

NOTE: `bzImage` must NOT be stripped — it is a raw binary with an embedded
EFI stub, and binutils rewrites it as a PE file, corrupting the boot sector
(breaks the AA55/HdrS kernel header and the initramfs inside it).

#### Benefits

- **Layer caching**: faster rebuilds; the kernel tree survives between builds
- **Split build**: kernel/rootfs compiles in Docker (minutes); userspace,
  init, initramfs and ISO assembly are local and take seconds
- **Reproducible-ish**: kernel config is versioned in `linux.config`

### 2. Linux Kernel

**Source**: torvalds/linux (latest `master` by default; override with
`LINUX_VERSION=<tag>` build arg)

**Configuration**: `linux.config`

- Minimal feature set
- x86_64 architecture
- Required drivers only (including e1000 for QEMU networking)
- No unnecessary modules

**Build Process** (in the kernel-builder stage):

```bash
make olddefconfig
make -j$(nproc)
```

**Output**: `build/bzImage` (~15MB, extracted from the container via
`docker create` + `docker cp`)

### 3. Alpine Userspace

**Source**: Alpine Linux packages (`apk add alpine-base openrc ...`) in the
`rootfs-builder` stage

- `alpine-base` (BusyBox shell + core tools)
- OpenRC init (standard sysinit/boot runlevels enabled, mdev for device nodes)
- bash, coreutils, findutils, grep, sed, gawk, curl, wget, openssh-client
- No toolchain, no git, no GUI — install inside the guest later with `apk add`

**Output**: `build/rootfs.tar.gz` (~40MB), unpacked into the initramfs

### 4. Init System

**File**: `init/` → compiled Zig binary becomes `/init` (PID 1) in the
initramfs. See `init/README.md`.

**Responsibilities**:

- Reap child processes via a SIGCHLD handler (no zombies when shells exit)
- Mount essential filesystems: devtmpfs on /dev, /dev/pts, /proc, /sys, tmpfs /tmp and /run
- Create fallback device nodes and POSIX symlinks (/dev/fd etc.)
- Set hostname, PATH, HOME
- Spawn a root shell (`ash -l`) on tty1 / ttyS0, then `pause()` in a loop

If the Zig init binary is missing at pack time, `scripts/mkinitramfs.sh`
keeps the shell-script fallback `init.sh` (also copied into the rootfs by
the Dockerfile) as `/init`.

**Design Philosophy**:

- Simple and transparent
- No complex service management
- Easy to understand and modify (single Zig file)
- Minimal dependencies (statically linked musl)

### 5. Bootloader

**Technology**: Syslinux/ISOLINUX 6.03 (isolinux.bin + ldlinux.c32,
downloaded once from kernel.org into `build/syslinux/`)

**Configuration**: `syslinux.cfg`

**Boot Process**:

1. BIOS (via the isohybrid MBR) loads isolinux
2. Bootloader loads kernel (bzImage) + initramfs
3. Kernel decompresses and initializes
4. Kernel mounts the initramfs as /
5. Kernel executes /init (Zig PID 1)
6. Init mounts filesystems, sets up the environment
7. Root shell on tty1 / ttyS0

### 6. Build Scripts

#### build.sh (legacy)

Creates a bootable FAT disk image (`boot.img`) with syslinux instead of an
ISO. Private helper; requires root for loop mounting.

#### scripts/

- `mkinitramfs.sh`: packs rootfs.tar.gz + Zig binaries + Zig init into the initramfs
- `extract.sh`: extracts kernel/rootfs artifacts from Docker
- `test.sh`: sanity checks (Docker image, artifacts)
- `clean.sh`: cleanup of `build/` (supports `--docker` / `--all`)

### 7. Automation

#### Makefile

The main entrypoint. Targets:

- `make build` — kernel + rootfs + userspace + init + initramfs + iso
- `make kernel` / `make rootfs` — Docker stages
- `make userspace` / `make init` — local Zig builds
- `make initramfs` / `make iso` — local packing/assembly
- `make qemu` / `make qemu-nographic` / `make qemu-network` — boot testing
- `make clean` / `make check-deps` / `make help`

#### docker-compose.yml

Defines services:

- `builder`: builds the rootfs stage and copies `rootfs.tar.gz` to `./build/`
- `dev`: interactive shell inside the rootfs (profile: dev)

#### CI

Not yet set up. The Makefile is the source of truth; a future GitHub Actions
workflow would call `make build` and publish `build/output.iso` as a release
artifact (see Planned Features).

## Data Flow

### Build Flow

```sh
linux.config + Dockerfile stage args
    ↓
kernel-builder (Docker)  ──→  bzImage          ┐
rootfs-builder (Docker)  ──→  rootfs.tar.gz    │
userspace/ (zig 0.15.1)  ──→  zig-out/bin/*    ├─→ mkinitramfs.sh ─→ initramfs
init/ (zig 0.16.0)       ──→  init             ┘
    ↓
bzImage + initramfs + isolinux ─→ xorriso ─→ output.iso (hybrid)
```

### Boot Flow

```sh
Power On
    ↓
BIOS (isohybrid MBR)
    ↓
ISOLINUX
    ↓
Load Kernel (bzImage) + initramfs
    ↓
Kernel Init
    ↓
Execute /init (Zig PID 1)
    ↓
Mount Filesystems (devtmpfs, /proc, /sys, /tmp, /run)
    ↓
Spawn root shell on tty1 / ttyS0
```

## Security Considerations

### Build-time Security

- Multi-stage builds isolate the build environment
- No build tools in the rootfs image
- Minimal dependencies
- Shallow source clones

### Runtime Security

- Rootfs userspace is minimal (no compilers, no servers installed)
- No network services enabled by default (DHCP on eth0 only)
- Small attack surface (BusyBox + emulated coreutils + Zig init)

### Supply Chain Security

- Kernel from the official torvalds repository
- Syslinux downloaded from mirrors.edge.kernel.org
- Package lists reviewable in the Dockerfile
- Checksum pinning possible (not yet implemented)

## Performance Optimizations

### Build Performance

- BuildKit layer + cache mounts for apt and the kernel tree
- Parallel compilation (`make -j$(nproc)`, `BUILD_JOBS` build arg)
- Fast local iteration: seconds for userspace/init/initramfs/iso

### Runtime Performance

- Statically linked Zig binaries + musl
- Minimal kernel
- Fast boot time (~1-2 seconds)
- Low memory footprint

### Size Optimizations

- `-Doptimize=ReleaseFast` / `--release=small` for the Zig builds
- Minimal kernel configuration
- Compressed initramfs (gzip -9, newc via bsdtar)
- Dev toolchains excluded from the rootfs

## Extensibility

### Adding Packages

Edit the `apk add` list in the `rootfs-builder` stage of the `Dockerfile`:

```dockerfile
RUN apk add --no-cache \
        alpine-base \
        openrc \
        python3      # add whatever you need
```

### Adding Custom Userland Tools

Add a Zig command to `userspace/src/` (keep
`userspace/src/commands/listing.zig` and the `ZIG_COMMANDS` list in
`scripts/mkinitramfs.sh` in sync), or drop any static binary into
`userspace/zig-out/bin/` before running `make initramfs`.

### Custom Init

Extend `init/src/main.zig` (PID 1) or, for the Alpine/OpenRC rootfs, use
`rc-update` runlevels configured in the `rootfs-builder` stage or scripts in
`/etc/init.d/`.

### Kernel Modules

Update `linux.config`:

```bash
docker run -it --rm -v "$(pwd):/work" distrox:kernel bash
# inside: cd /build/linux && make menuconfig && cp .config /work/linux.config
```

then rebuild: `make kernel initramfs iso`.

### Network Services

The rootfs ships an `ifupdown` + DHCP setup (`/etc/network/interfaces`,
`networking` runlevel). For anything more, add packages to the rootfs or
implement the service in the Zig userspace.

## Testing Strategy

### Sanity Tests

- `make check-deps` — local tooling present
- `./scripts/test.sh` — build artifact checks

### System Tests

- `make qemu-nographic` — boot the ISO in QEMU and verify the console
- `make qemu-network` — boot with user-mode networking and test connectivity

## Future Enhancements

### Planned Features

- [ ] UEFI boot support
- [ ] ARM architecture support
- [ ] GitHub Actions CI (build + publish ISO artifacts)
- [ ] Package manager integration
- [ ] Init service management
- [ ] Persistent storage support (built-in)

### Under Consideration

- [ ] Full Zig userspace (replace BusyBox entirely)
- [ ] Container runtime
- [ ] Full development environment
- [ ] Desktop environment option

## Resources

- [Linux From Scratch](http://www.linuxfromscratch.org/)
- [Kernel Build System](https://www.kernel.org/doc/html/latest/kbuild/)
- [BusyBox](https://busybox.net/docs/)
- [Syslinux](https://wiki.syslinux.org/)
