# syntax=docker/dockerfile:1.4
# =============================================================================
# Multi-stage Dockerfile for Building Custom Linux Distribution
# =============================================================================

FROM debian:sid-slim AS builder-base

ARG LINUX_VERSION=master
ARG SYSLINUX_VERSION=6.03
ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_JOBS=

LABEL maintainer="handbuilt-linux-project"
LABEL description="Custom Linux distribution builder"
LABEL version="1.0.0"

# Install build dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
    build-essential \
    bzip2 \
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
    syslinux-common \
    dosfstools \
    genisoimage \
    wget \
    curl \
    ca-certificates \
    xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# -----------------------------------------------------------------------------
# Stage: source-downloader
# -----------------------------------------------------------------------------
FROM builder-base AS source-downloader

ARG LINUX_VERSION=master
ARG SYSLINUX_VERSION=6.03

RUN mkdir -p /build/initramfs && \
    mkdir -p /build/myiso/isolinux && \
    mkdir -p /build/sources && \
    mkdir -p /build/cache

WORKDIR /build/sources

# Clone Linux (shallow, branch/tag from ARG)
RUN --mount=type=cache,target=/build/cache \
    if [ ! -d /build/cache/linux ]; then \
    git clone --depth 1 --branch "${LINUX_VERSION}" https://github.com/torvalds/linux.git linux || \
    git clone --depth 1 https://github.com/torvalds/linux.git linux; \
    cp -r linux /build/cache/linux; \
    else \
    cp -r /build/cache/linux linux; \
    fi

# Download and extract Syslinux (tries multiple URLs)
WORKDIR /build/sources
RUN set -eux; \
    tried=0; \
    for url in \
    "https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-${SYSLINUX_VERSION}.tar.gz" \
    "https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-${SYSLINUX_VERSION}.tar.gz" \
    "https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/Testing/${SYSLINUX_VERSION}/syslinux-${SYSLINUX_VERSION}.tar.gz"; do \
    echo "Trying $url"; \
    if curl -fsSL -o syslinux.tar.gz "$url"; then \
    tried=1; \
    break; \
    else \
    echo "Failed to download from $url"; \
    fi; \
    done; \
    if [ "$tried" -ne 1 ]; then \
    echo "ERROR: Unable to download syslinux ${SYSLINUX_VERSION}" >&2; \
    exit 22; \
    fi; \
    tar xzf syslinux.tar.gz && rm syslinux.tar.gz && mv "syslinux-${SYSLINUX_VERSION}" syslinux

# -----------------------------------------------------------------------------
# Stage: kernel-builder
# -----------------------------------------------------------------------------
FROM builder-base AS kernel-builder

ARG BUILD_JOBS
ARG LINUX_VERSION=master

COPY --from=source-downloader /build/sources/linux /build/linux
# If you have a linux.config in repo, it will be copied by the build context
COPY linux.config /build/linux/.config

WORKDIR /build/linux
# NOTE: do NOT strip arch/x86/boot/bzImage — it is a raw binary with an
# embedded EFI stub, and binutils "successfully" rewrites it as a PE file,
# corrupting the boot sector (breaks the AA55/HdrS kernel header).
RUN make olddefconfig && \
    make -j"${BUILD_JOBS:-$(nproc)}"

# -----------------------------------------------------------------------------
# Stage: alpine-rootfs-builder
# -----------------------------------------------------------------------------
FROM alpine:latest AS alpine-rootfs-builder

# Install the userspace: base suite, OpenRC, CLI tools, and the dev
# toolchain we care about (Go + Zig). Keep it text-only — no GUI packages.
RUN apk add --no-cache \
        alpine-base \
        openrc \
        bash \
        coreutils \
        findutils \
        grep \
        sed \
        gawk \
        git \
        curl \
        wget \
        go \
        zig \
        build-base \
        musl-dev \
        linux-headers \
        openssh-client \
        vim \
        cpio \
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

# Our PID 1 wrapper: mounts the basics, then execs /sbin/init
COPY init.sh /init
RUN chmod +x /init

# Pack the entire rootfs into an initramfs (kernel unpacks it into RAM)
WORKDIR /build
RUN cd / && find . -xdev -print0 | cpio --null --create --format=newc | gzip -9 > /build/initramfs.cpio.gz \
    && ls -lh /build/initramfs.cpio.gz

# -----------------------------------------------------------------------------
# Stage: iso-builder
# -----------------------------------------------------------------------------
FROM builder-base AS iso-builder

ARG SYSLINUX_VERSION=6.03

COPY --from=source-downloader /build/sources/syslinux /build/syslinux
COPY --from=kernel-builder /build/linux/arch/x86/boot/bzImage /build/myiso/bzImage
COPY --from=alpine-rootfs-builder /build/initramfs.cpio.gz /build/myiso/initramfs

WORKDIR /build
RUN mkdir -p /build/myiso/isolinux && \
    cp /build/syslinux/bios/core/isolinux.bin /build/myiso/isolinux/ && \
    cp /build/syslinux/bios/com32/elflink/ldlinux/ldlinux.c32 /build/myiso/isolinux/

COPY syslinux.cfg /build/myiso/isolinux/isolinux.cfg

WORKDIR /build
RUN mkisofs \
    -J \
    -R \
    -o output.iso \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    myiso

# -----------------------------------------------------------------------------
# Stage: export-stage
# -----------------------------------------------------------------------------
FROM scratch AS export-stage

COPY --from=iso-builder /build/output.iso /output.iso
COPY --from=kernel-builder /build/linux/arch/x86/boot/bzImage /bzImage
COPY --from=alpine-rootfs-builder /build/initramfs.cpio.gz /initramfs

# -----------------------------------------------------------------------------
# Stage: runtime
# -----------------------------------------------------------------------------
FROM alpine:latest AS runtime

RUN apk add --no-cache qemu-system-x86_64 qemu-img \
    && rm -rf /var/cache/apk/*

RUN addgroup -S distro && \
    adduser -S -G distro -h /distro -s /bin/sh distro && \
    mkdir -p /distro && \
    chown -R distro:distro /distro

COPY --from=iso-builder /build/output.iso /distro/output.iso
COPY --from=kernel-builder /build/linux/arch/x86/boot/bzImage /distro/bzImage
COPY --from=alpine-rootfs-builder /build/initramfs.cpio.gz /distro/initramfs

COPY --chown=distro:distro build.sh /distro/build.sh
RUN chmod +x /distro/build.sh

WORKDIR /distro
USER distro
ENV DISTRO_HOME=/distro
ENV PATH="${DISTRO_HOME}:${PATH}"

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD [ -f "/distro/output.iso" ] || exit 1

CMD ["/bin/sh"]