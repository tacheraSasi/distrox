# Distrox (temporary placeholder name)

A minimal, customizable Linux distribution built from scratch.

**Note:** "Distrox" is only a temporary placeholder name. The final name will be chosen later.

The long-term goal of this project is to completely replace the traditional userspace (BusyBox / Alpine tools) with a custom implementation written in Zig, following the approach of [zig-coreutils](https://github.com/tacheraSasi/zig-coreutils).

Currently the system uses Alpine (BusyBox + OpenRC) as the base userspace plus a custom Zig PID 1 and Zig coreutils injected into the initramfs.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-ready-brightgreen.svg)](Dockerfile)
[![Linux](https://img.shields.io/badge/kernel-latest-orange.svg)](https://github.com/torvalds/linux)

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building Step by Step](#building-step-by-step)
- [Manual Docker Extraction](#manual-docker-extraction)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Userspace Direction](#userspace-direction)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- Minimal footprint
- Built from the Linux kernel and a simple initramfs
- Split build: heavy kernel/rootfs compiles in Docker, fast local steps for the rest
- Bootable ISO (ISOLINUX, assembled with xorriso)
- Zig PID 1 (with a shell-based fallback) and Zig coreutils in the initramfs
- Simple and transparent boot process
- Easy testing with QEMU
- Configurable kernel
- Parallel compilation
- Planned complete replacement of userspace with custom Zig tools (based on [zig-coreutils](https://github.com/tacheraSasi/zig-coreutils))

## Prerequisites

- **Docker** (uses BuildKit cache mounts; Docker 20.10+ with BuildKit is fine) — for the kernel and rootfs compiles
- **Local tooling** for the fast steps:
  - `anyzig` ([Zig version manager](https://github.com/sno2/anyzig)) — the Makefile pins Zig 0.15.1 (userspace) and 0.16.0 (init)
  - `xorriso` — ISO assembly
  - `bsdtar` (libarchive) — initramfs packing
  - `curl` — one-time syslinux download
- **QEMU** (optional) — testing

Verify everything with:

```bash
make check-deps
```

## Quick Start

```bash
# 1. Build everything: kernel + rootfs + userspace + init + initramfs + ISO
make build

# 2. Boot it
make qemu              # QEMU with GUI
make qemu-nographic    # QEMU serial console (Ctrl+A X to exit)
```

**Build time**: ~20-30 minutes for the first kernel compile, then cached. After that, `make userspace initramfs iso` iterates in seconds.

All artifacts land in `build/`:

```text
build/bzImage         # Linux kernel
build/rootfs.tar.gz   # Alpine rootfs produced by Docker
build/initramfs       # Final initramfs (rootfs + Zig bins + Zig init)
build/output.iso      # Bootable ISO
```

## Building Step by Step

Each heavy step runs in Docker, each light step runs locally:

```bash
make kernel      # Docker: compile bzImage                       (~20 min once)
make rootfs      # Docker: Alpine rootfs -> rootfs.tar.gz        (~2 min once)
make userspace   # local: Zig coreutils, x86_64-linux-musl       (seconds)
make init        # local: Zig PID 1 init, x86_64-linux-musl      (seconds)
make initramfs   # local: rootfs + Zig bins + init -> cpio       (seconds)
make iso         # local: bzImage + initramfs -> output.iso      (seconds)
make build       # everything above in order
```

Also useful:

```bash
make clean             # wipe build/
make check-deps        # verify local tooling
make help              # all targets
```

### Docker Compose

`docker-compose.yml` only wraps the `rootfs-builder` stage (the kernel is built separately with `make kernel`):

```bash
docker compose up --build          # build rootfs and copy rootfs.tar.gz to ./build/
docker compose run --rm dev        # interactive shell inside the rootfs (profile: dev)
```

## Manual Docker Extraction

If you don't want to use the Makefile, the Docker stages can be driven by hand. The Dockerfile has exactly two stages:

```bash
# Kernel stage -> distrox:kernel
docker build --target kernel-builder -t distrox:kernel .

docker create --name distrox-kernel distrox:kernel
mkdir -p build
docker cp distrox-kernel:/build/linux/arch/x86/boot/bzImage build/bzImage
docker rm distrox-kernel

# Rootfs stage -> distrox:latest
docker build --target rootfs-builder -t distrox:latest .

docker create --name distrox-rootfs distrox:latest
docker cp distrox-rootfs:/build/rootfs.tar.gz build/rootfs.tar.gz
docker rm distrox-rootfs
```

Or use the helper script (same thing):

```bash
./scripts/extract.sh                      # -> ./build/
./scripts/extract.sh distrox:kernel distrox:latest ./output
```

ISO assembly, initramfs packing, and the Zig builds are not done in Docker — run `make userspace init initramfs iso` for those.

## Usage

### Running with QEMU

**Boot from ISO (what `make iso` produces):**

```bash
qemu-system-x86_64 -cdrom build/output.iso -m 2048M
```

Or just use the Makefile wrappers:

```bash
make qemu              # GUI window
make qemu-nographic    # serial console (Ctrl+A X to exit)
make qemu-network      # serial console + user-mode networking
```

**Boot from kernel and initramfs directly:**

```bash
qemu-system-x86_64 \
  -kernel build/bzImage \
  -initrd build/initramfs \
  -append "console=ttyS0" \
  -nographic \
  -m 2048M
```

### Creating a Bootable USB (Optional)

The ISO is hybrid (`xorriso -as mkisofs -isohybrid-mbr ...`), so you can `dd` it straight to a USB stick:

```bash
# Replace /dev/sdX with your USB device (BE CAREFUL!)
sudo dd if=build/output.iso of=/dev/sdX bs=4M status=progress
sudo sync
```

### Legacy boot.img Helper

`./build.sh` is an older helper that builds a small FAT-formatted disk image with syslinux instead of an ISO. It requires `mkfs.fat`/`syslinux` and root privileges (it mounts a loop device with sudo), and it expects paths that must be given explicitly since the default `./myiso/` layout no longer exists:

```bash
./build.sh \
  -k build/bzImage \
  -i build/initramfs \
  -c syslinux.cfg \
  -o boot.img
./build.sh --help    # all options (-s size, -v verbose, ...)
```

Prefer `make iso` for normal workflows.

## Project Structure

```text
distrox/
├── Dockerfile              # kernel-builder + rootfs-builder stages
├── docker-compose.yml      # rootfs builder + dev shell
├── Makefile                # main build entrypoint
├── QUICKSTART.md
├── linux.config            # kernel config
├── syslinux.cfg            # ISOLINUX boot menu
│
├── init/                   # Zig PID 1 init (built with anyzig)
├── userspace/              # Zig coreutils (busybox-style multi-call binary)
│
├── init.sh                 # shell PID 1 fallback copied into the rootfs image
├── build.sh                # legacy boot.img (FAT disk image) helper
│
├── scripts/
│   ├── mkinitramfs.sh      # packs rootfs + Zig bins + init into the initramfs
│   ├── extract.sh          # extracts kernel/rootfs artifacts from Docker
│   ├── test.sh             # sanity checks on build artifacts
│   └── clean.sh            # cleanup (+ --docker / --all)
│
└── docs/
    ├── ARCHITECTURE.md
    ├── CUSTOMIZATION.md
    └── CONTRIBUTING.md
```

## Configuration

### Kernel Configuration

The kernel is configured from `linux.config` (fed to `make olddefconfig` in the `kernel-builder` stage). To tweak it interactively:

```bash
docker run -it --rm -v "$(pwd):/work" distrox:kernel bash
# inside the container:
cd /build/linux
make menuconfig
cp .config /work/linux.config
```

Then rebuild: `make kernel && make iso`.

### Init System

`init/` contains the Zig PID 1 that becomes `/init` in the initramfs (see `init/README.md`). It mounts the essential filesystems, sets hostname/PATH, spawns a root shell on each console, and reaps zombies.

If `init/zig-out/bin/init` is missing, `scripts/mkinitramfs.sh` keeps the shell-script fallback from `init.sh` instead.

### Rootfs Packages

Edit the `apk add` list in the `rootfs-builder` stage of the `Dockerfile` to change what's in the Alpine rootfs. Dev tools are intentionally excluded — install them inside the guest with `apk add` after boot.

### Bootloader

Edit `syslinux.cfg` to change timeout, kernel parameters, and boot menu options.

## Userspace Direction

The current system still relies on BusyBox and Alpine packages for a usable environment.

The explicit goal of this project is to **completely replace** the traditional userspace with a custom Zig implementation.

The reference implementation being followed is:

- https://github.com/tacheraSasi/zig-coreutils

`make userspace` cross-compiles `userspace/` to static `x86_64-linux-musl` binaries; `make initramfs` copies them into `/usr/local/bin/` of the rootfs and generates profile aliases (the Zig binary dispatches on argv[0]/first argument, busybox stays the default for scripts).

Implemented commands so far: `basename`, `clear`, `dirname`, `false`, `groups`, `nproc(s)`, `touch`, `true`, `uname`, `unlink`, `whoami`, `yes`. See `userspace/README.md` for the full list.

## Advanced Usage

### Adding Custom Binaries

Drop static Zig/Go/C binaries into the initramfs via `scripts/mkinitramfs.sh` (it copies everything from `userspace/zig-out/bin/` into `/usr/local/bin/`), or bake them into `rootfs-builder` in the `Dockerfile`.

### Persistent Storage

```bash
qemu-img create -f raw data.img 1G
qemu-system-x86_64 \
  -cdrom build/output.iso \
  -m 2048M \
  -drive file=data.img,format=raw
```

## Troubleshooting

**Build fails with "out of space":**

```bash
docker system prune -a
docker builder prune -f
```

**`xorriso` / `bsdtar` / `anyzig` not found?**

```bash
sudo pacman -S libisoburn libarchive              # Arch (omarchy)
brew install xorriso libarchive                   # macOS
sudo apt install xorriso libarchive-tools         # Debian/Ubuntu
# anyzig: https://github.com/sno2/anyzig
```

**ISO missing kernel/initramfs?**

```bash
rm -rf build && make build
```

**QEMU shows black screen:**

```bash
qemu-system-x86_64 -cdrom build/output.iso -nographic
```

**Kernel panic on boot:**

```bash
file build/initramfs
# Should show gzip compressed data
```

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

Quick version: fork, branch (`git checkout -b feature/your-feature`), commit, push, open a Pull Request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Linux Kernel](https://kernel.org/)
- [BusyBox](https://busybox.net/)
- [Syslinux](https://www.syslinux.org/)
- [Alpine Linux](https://alpinelinux.org/)
- [zig-coreutils](https://github.com/tacheraSasi/zig-coreutils)
- [QEMU](https://www.qemu.org/)

## Resources

- [Linux From Scratch](http://www.linuxfromscratch.org/)
- [Kernel Build Documentation](https://www.kernel.org/doc/html/latest/kbuild/index.html)
- [BusyBox Documentation](https://busybox.net/docs/)
- [Syslinux Wiki](https://wiki.syslinux.org/)
