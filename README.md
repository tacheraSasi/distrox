```markdown
# Distrox (temporary placeholder name)

A minimal, customizable Linux distribution built from scratch.

**Note:** "Distrox" is only a temporary placeholder name. The final name will be chosen later.

The long-term goal of this project is to completely replace the traditional userspace (BusyBox / Alpine tools) with a custom implementation written in Zig, following the approach of [zig-coreutils](https://github.com/tacheraSasi/zig-coreutils).

Currently the system still uses BusyBox + Alpine packages for practicality while the Zig userspace is being developed.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-ready-brightgreen.svg)](Dockerfile)
[![Linux](https://img.shields.io/badge/kernel-latest-orange.svg)](https://github.com/torvalds/linux)

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building from Source](#building-from-source)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- Minimal footprint
- Built from the Linux kernel and a simple initramfs
- Multi-stage Docker build with caching
- Bootable ISO
- Simple and transparent init process
- Easy testing with QEMU / UTM
- Configurable kernel
- Parallel compilation
- Planned complete replacement of userspace with custom Zig tools (based on [zig-coreutils](https://github.com/tacheraSasi/zig-coreutils))

## Prerequisites

### For Docker Build (Recommended)

- Docker 20.10 or later
- 4GB free disk space
- 2GB RAM minimum

### For Manual Build

- Linux system (Debian/Ubuntu recommended)
- Build tools: `gcc`, `make`, `bison`, `flex`
- Additional packages:

```bash
sudo apt-get install build-essential libncurses-dev bison flex \
  libssl-dev libelf-dev bc cpio git wget curl syslinux \
  dosfstools genisoimage qemu-system-x86
```

## Quick Start

### Using Docker (Recommended)

1. Clone the repository

```bash
git clone https://github.com/yourusername/distrox.git
cd distrox
```

2. Build the distribution

```bash
docker build -t distrox .
```

3. Extract the ISO

```bash
docker run --rm distrox cat /distro/output.iso > output.iso
```

4. Test with QEMU

```bash
qemu-system-x86_64 -cdrom output.iso -m 512M
```

### Using Docker Compose

```bash
docker-compose up --build
```

## Building from Source

### Step 1: Build with Docker

```bash
# Build the complete image
docker build -t distrox .

# Or build specific stages
docker build --target kernel-builder -t linux-kernel .
docker build --target alpine-rootfs-builder -t rootfs-build .
docker build --target iso-builder -t linux-iso .
```

### Step 2: Extract Build Artifacts

```bash
# Extract ISO
docker run --rm distrox cat /distro/output.iso > output.iso

# Extract kernel
docker run --rm distrox cat /distro/bzImage > bzImage

# Extract initramfs
docker run --rm distrox cat /distro/initramfs > initramfs
```

### Step 3: Create Bootable USB (Optional)

```bash
# Replace /dev/sdX with your USB device (BE CAREFUL!)
sudo dd if=output.iso of=/dev/sdX bs=4M status=progress
sudo sync
```

## Usage

### Running with QEMU

**Boot from ISO:**

```bash
qemu-system-x86_64 -cdrom output.iso -m 512M
```

**Boot from kernel and initramfs directly:**

```bash
qemu-system-x86_64 \
  -kernel bzImage \
  -initrd initramfs \
  -append "console=ttyS0" \
  -nographic \
  -m 512M
```

**With networking:**

```bash
qemu-system-x86_64 \
  -cdrom output.iso \
  -m 512M \
  -netdev user,id=net0 \
  -device e1000,netdev=net0
```

### Building a Boot Image

```bash
./build.sh
./build.sh --size 100
./build.sh --output my-boot.img
./build.sh --verbose
./build.sh --help
```

## Project Structure

```text
distrox/
├── Dockerfile
├── docker-compose.yml
├── Makefile
├── README.md
├── LICENSE
├── .gitignore
│
├── build.sh
├── init.sh
├── syslinux.cfg
│
├── linux.config
│
├── scripts/
│   ├── test.sh
│   ├── extract.sh
│   └── clean.sh
│
├── docs/
│   ├── BUILDING.md
│   ├── CUSTOMIZING.md
│   └── TROUBLESHOOTING.md
│
└── .github/
    └── workflows/
        └── build.yml
```

## Configuration

### Kernel Configuration

```bash
docker run -it --rm -v $(pwd):/work distrox bash
cd /build/linux
make menuconfig
cp .config /work/linux.config
```

### Init System

Edit `init.sh` to customize hostname, mounts, network, and startup behavior.

### Bootloader

Edit `syslinux.cfg` to change timeout, kernel parameters, and boot menu options.

## Userspace Direction

The current system still relies on BusyBox and Alpine packages for a usable environment.

The explicit goal of this project is to **completely replace** the traditional userspace with a custom Zig implementation.

The reference implementation being followed is:

- https://github.com/tacheraSasi/zig-coreutils

Over time, core utilities (`ls`, `cat`, `cp`, `mv`, `rm`, `echo`, `mkdir`, etc.) will be rewritten in pure Zig and the BusyBox/Alpine userspace will be removed.

## Advanced Usage

### Adding Custom Binaries

You can drop static Zig or Go binaries into the rootfs during the build.

### Persistent Storage

```bash
qemu-system-x86_64 \
  -cdrom output.iso \
  -m 512M \
  -drive file=data.img,format=raw
```

## Troubleshooting

**Build fails with "out of space":**

```bash
docker system prune -a
docker builder prune -f
```

**QEMU shows black screen:**

```bash
qemu-system-x86_64 -cdrom output.iso -nographic
```

**Kernel panic on boot:**

```bash
file initramfs
# Should show gzip compressed data
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

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
```