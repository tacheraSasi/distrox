#!/usr/bin/env bash
# =============================================================================
# mkinitramfs.sh Pack the Alpine rootfs + Zig userland into an initramfs
#
# Usage:
#   ./scripts/mkinitramfs.sh <rootfs.tar.gz> <zig-out-bin-dir> <output>
#
# Steps:
#   1. Unpack the rootfs tarball into a staging dir
#   2. Copy any locally-built Zig binaries into /usr/local/bin
#   3. Repack the whole tree as a newc cpio archive, gzip compressed
#
# Uses bsdtar for the newc archive (works on macOS and Linux; the kernel
# accepts newc without padding issues).
# =============================================================================

set -euo pipefail

ROOTFS_TAR="${1:?usage: mkinitramfs.sh <rootfs.tar.gz> <zig-bin-dir> <output>}"
ZIG_BIN_DIR="${2:-}"
OUTPUT="${3:?usage: mkinitramfs.sh <rootfs.tar.gz> <zig-bin-dir> <output>}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "[mkinitramfs] unpacking ${ROOTFS_TAR}"
tar -xzf "${ROOTFS_TAR}" -C "${STAGE}"

# Alpine installs some setuid helpers (e.g. /bin/bbsuid) execute-only;
# bsdtar needs read permission to archive them, so grant it in the
# staging copy (the packed rootfs keeps whatever mode tar stored).
find "${STAGE}" -type f ! -perm -u+r -exec chmod u+r {} +

if [[ -d "${ZIG_BIN_DIR}" ]] && compgen -G "${ZIG_BIN_DIR}/*" > /dev/null; then
    echo "[mkinitramfs] injecting Zig binaries from ${ZIG_BIN_DIR}"
    mkdir -p "${STAGE}/usr/local/bin"
    cp "${ZIG_BIN_DIR}"/* "${STAGE}/usr/local/bin/"
elif [[ -n "${ZIG_BIN_DIR}" ]]; then
    echo "[mkinitramfs] note: no binaries in ${ZIG_BIN_DIR} (zig build not run?)"
fi

echo "[mkinitramfs] packing ${OUTPUT}"
( cd "${STAGE}" && bsdtar --format newc -cf - . ) | gzip -9 > "${OUTPUT}"

echo "[mkinitramfs] done: $(du -sh "${OUTPUT}" | cut -f1)"
