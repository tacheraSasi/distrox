#!/bin/sh

# =============================================================================
# Init Script for handbuilt-linux (Alpine)
# =============================================================================
# This is PID 1. It mounts the essential pseudo-filesystems, then hands
# control over to Alpine's init (/sbin/init = BusyBox init + OpenRC).
# =============================================================================

HOSTNAME="handbuilt-linux"

# Mount essential filesystems before OpenRC takes over
/bin/mount -t proc proc /proc 2>/dev/null || true
/bin/mount -t sysfs sysfs /sys 2>/dev/null || true
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

/bin/mkdir -p /dev/pts /dev/shm /tmp /run
/bin/mount -t devpts devpts /dev/pts 2>/dev/null || true
/bin/mount -t tmpfs tmpfs /tmp 2>/dev/null || true
/bin/mount -t tmpfs tmpfs /run 2>/dev/null || true

# Fallback device nodes if devtmpfs is unavailable
if [ ! -e /dev/console ]; then
    /bin/mknod /dev/console c 5 1 2>/dev/null || true
fi
if [ ! -e /dev/null ]; then
    /bin/mknod -m 666 /dev/null c 1 3 2>/dev/null || true
fi

# Standard /dev links
/bin/ln -sf /proc/self/fd /dev/fd 2>/dev/null || true
/bin/ln -sf /proc/self/fd/0 /dev/stdin 2>/dev/null || true
/bin/ln -sf /proc/self/fd/1 /dev/stdout 2>/dev/null || true
/bin/ln -sf /proc/self/fd/2 /dev/stderr 2>/dev/null || true

# The build container leaks its own /etc/hostname and /etc/hosts
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' "${HOSTNAME}" > /etc/hosts

# Hand off to Alpine's init system
exec /sbin/init