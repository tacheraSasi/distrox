# syntax=docker/dockerfile:1.4
# =============================================================================
# Multi-stage Dockerfile for Building Custom Linux Distribution
#
# Two stages only:
#   - kernel-builder: compiles the Linux kernel -> bzImage
#   - rootfs-builder: slim Alpine userspace rootfs -> rootfs.tar.gz
#
# ISO assembly, initramfs packing and QEMU testing happen locally
# (see Makefile). Docker is only used for the heavy compiles.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage: kernel-builder
# -----------------------------------------------------------------------------
FROM debian:sid-slim AS kernel-builder

ARG LINUX_VERSION=master
ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_JOBS=

LABEL maintainer="distrox-project"
LABEL description="Custom Linux distribution kernel builder"
LABEL version="2.0.0"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
    build-essential \
    git \
    make \
    gcc \
    libncurses-dev \
    flex \
    bison \
    bc \
    cpio \
    libelf-dev \
    libssl-dev \
    xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN mkdir -p /build/sources /build/cache

WORKDIR /build/sources

# Clone Linux (shallow, branch/tag from ARG), cached across builds
RUN --mount=type=cache,target=/build/cache \
    if [ ! -d /build/cache/linux ]; then \
    git clone --depth 1 --branch "${LINUX_VERSION}" https://github.com/torvalds/linux.git linux || \
    git clone --depth 1 https://github.com/torvalds/linux.git linux; \
    cp -r linux /build/cache/linux; \
    else \
    cp -r /build/cache/linux linux; \
    fi

# Kernel config + build
COPY linux.config /build/linux/.config
WORKDIR /build/linux
# NOTE: do NOT strip arch/x86/boot/bzImage — it is a raw binary with an
# embedded EFI stub, and binutils "successfully" rewrites it as a PE file,
# corrupting the boot sector (breaks the AA55/HdrS kernel header).
RUN make olddefconfig && \
    make -j"${BUILD_JOBS:-$(nproc)}"

# -----------------------------------------------------------------------------
# Stage: rootfs-builder
# -----------------------------------------------------------------------------
FROM alpine:latest AS rootfs-builder

# Minimal userspace: no toolchain, no git, no GUI. Dev tools can be
# re-installed inside the running system with `apk add` later.
RUN apk add --no-cache \
        alpine-base \
        openrc \
        bash \
        coreutils \
        findutils \
        grep \
        sed \
        gawk \
        curl \
        wget \
        openssh-client \
    && rm -rf /var/cache/apk/*

# Enable the standard OpenRC runlevels (sysinit/boot/default).
# mdev handles device nodes; hwdrivers loads modules (none shipped - harmless).
RUN rc-update add devfs sysinit \
    && rc-update add dmesg sysinit \
    && rc-update add mdev sysinit \
    && rc-update add hwdrivers sysinit \
    && rc-update add hwclock boot \
    && rc-update add modules boot \
    && rc-update add sysctl boot \
    && rc-update add hostname boot \
    && rc-update add bootmisc boot \
    && rc-update add syslog boot \
    && rc-update add networking boot

# Auto root shell on the VGA console (askfirst) and the serial console.
RUN sed -i 's|^tty1::.*|tty1::askfirst:-/bin/ash|' /etc/inittab \
    && printf 'ttyS0::respawn:-/bin/ash\n' >> /etc/inittab

# Loopback + DHCP on eth0 (works if the kernel ships the NIC driver)
RUN printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n' \
        > /etc/network/interfaces

# Root profile with PATH and useful aliases
RUN printf 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\nalias ll="ls -lah"\nalias la="ls -A"\nalias l="ls -CF"\n' \
        > /root/.profile

# PID 1 wrapper: mounts the basics, then execs /sbin/init
COPY init.sh /init
RUN chmod +x /init

# Pack the rootfs as a tarball (uncompressed tree), excluding runtime
# pseudo/filesystem dirs that are recreated at boot by OpenRC/mdev.
RUN mkdir -p /build && \
    cd / && \
    tar --exclude='./proc' --exclude='./sys' --exclude='./dev' \
        --exclude='./run' --exclude='./tmp' --exclude='./build' \
        --exclude='./etc/resolv.conf' --exclude='./etc/hostname' \
        --exclude='./etc/hosts' \
        -czf /build/rootfs.tar.gz .