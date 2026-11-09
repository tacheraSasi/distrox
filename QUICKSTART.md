# Quick Start Guide

Get up and running with distrox!

## Prerequisites

- Docker (for the kernel + rootfs compiles)
- `anyzig` for building the userspace and init (pins Zig 0.15.1 / 0.16.0)
- `xorriso` for ISO assembly (`sudo pacman -S libisoburn` / `brew install xorriso` / `sudo apt install xorriso`)
- `bsdtar` from libarchive for initramfs packing
  (`sudo pacman -S libarchive` / `brew install libarchive` / `sudo apt install libarchive-tools`)
- (Optional) QEMU for testing

Verify with `make check-deps`.

## Three Simple Steps

### 1. Build

```bash
cd distrox

# Full build: kernel + rootfs + userspace + initramfs + ISO
make build
```

**Build time**: 20-30 minutes (first build, kernel compile), then cached. After
the first build, `make userspace initramfs iso qemu` iterates in seconds.

### 2. Rebuild individual pieces

```bash
make kernel      # Docker: compile bzImage
make rootfs      # Docker: Alpine rootfs.tar.gz
make userspace   # zig: compile Zig coreutils locally
make init        # zig: compile the Zig PID 1 init locally
make initramfs   # local: pack rootfs + Zig bins + init
make iso         # local: assemble output.iso with xorriso
```

### 3. Run

```bash
make qemu              # QEMU with GUI
make qemu-nographic    # QEMU serial console (Ctrl+A X to exit)
```

## Customizing the userland

Zig sources live in `userspace/` (coreutils) and `init/` (PID 1). `make
userspace` cross-compiles them to `x86_64-linux-musl` static binaries; `make
initramfs` copies everything from `userspace/zig-out/bin/` into
`/usr/local/bin/` of the rootfs and installs `init/zig-out/bin/init` as
`/init`. If the Zig init binary is missing, the shell fallback from
`init.sh` is used instead.

## Common Commands

```bash
make build             # full chain
make clean             # wipe build/
make check-deps        # verify local tooling
make help              # all targets
```

## What's Included

- **Linux Kernel**: latest from Linus Torvalds (config in `linux.config`)
- **Alpine userspace + OpenRC** as the base system (BusyBox stays the default
  for scripts)
- **Zig userland** (in `userspace/`) + **Zig PID 1** (in `init/`) injected into
  the initramfs
- **Syslinux 6.03**: bootloader (isolinux.bin + ldlinux.c32, downloaded once
  into `build/syslinux/`)

## Troubleshooting

**ISO misses kernel/initramfs?**

```bash
rm -rf build && make build
```

**"xorriso not found"?** `sudo pacman -S libisoburn`

**"bsdtar not found"?** `sudo pacman -S libarchive` (the Makefile's `mkinitramfs`
step packs the initramfs with bsdtar's newc format)

**"anyzig not found"?** Install [anyzig](https://github.com/sno2/anyzig) — it
pins the Zig versions the Makefile expects (0.15.1 for the userspace, 0.16.0
for the init).

**QEMU not found?**

```bash
sudo pacman -S qemu-desktop   # Arch (omarchy)
brew install qemu             # macOS
sudo apt install qemu-system-x86  # Debian/Ubuntu
```

**Rootfs bloat?** Reduce the `apk add` list in the `rootfs-builder` stage of
`Dockerfile`. Dev tools are intentionally excluded — install them inside the
guest with `apk add` after boot.

## File Locations

```bash
build/bzImage         # Linux kernel
build/rootfs.tar.gz   # Rootfs produced by Docker (base userspace)
build/initramfs       # Final initramfs (rootfs + Zig bins)
build/output.iso      # Bootable ISO image
```

## Resources

- Full documentation: [README.md](README.md)
- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)