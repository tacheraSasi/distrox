# Quick Start Guide

Get up and running with distrox!

## Prerequisites

- Docker (for the kernel + rootfs compiles)
- `xorriso` for ISO assembly (`brew install xorriso`)
- `zig` for building the userspace (`brew install zig` or zvm)
- (Optional) QEMU for testing

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
make userspace   # zig: compile Zig userland locally
make initramfs   # local: pack rootfs + Zig bins
make iso         # local: assemble output.iso with xorriso
```

### 3. Run

```bash
make qemu              # QEMU with GUI
make qemu-nographic    # QEMU serial console (Ctrl+A X to exit)
```

## Customizing the userland

Zig sources live in `userspace/`. `make userspace` cross-compiles them to
`x86_64-linux-musl` static binaryes; `make initramfs` copies everything from
`userspace/zig-out/bin/` into `/usr/local/bin/` of the rootfs.

## Common Commands

```bash
make build             # full chain
make clean             # wipe build/
make check-deps        # verify local tooling
make help              # all targets
```

## What's Included

- **Linux Kernel**: latest from Linus Torvalds (config in `linux.config`)
- **Alpine userspace + OpenRC** as the base system
- **Zig userland** (in `userspace/`) injected into the initramfs
- **Syslinux 6.03**: bootloader (isolinux.bin + ldlinux.c32, downloaded once)

## Troubleshooting

**ISO misses kernel/initramfs?**

```bash
rm -rf build && make build
```

**"xorriso not found"?** `brew install xorriso`

**QEMU not found?**

```bash
brew install qemu
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