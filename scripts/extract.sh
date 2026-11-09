#!/usr/bin/env bash

# =============================================================================
# Extract Build Artifacts from Docker
# =============================================================================
# Extracts the kernel bzImage from the kernel-builder image and the Alpine
# rootfs tarball from the rootfs-builder image, mirroring the `make kernel`
# and `make rootfs` Makefile targets.
#
# Usage:
#   ./scripts/extract.sh [kernel-image] [rootfs-image] [output-dir]
#
# Defaults to distrox:kernel / distrox:latest -> ./build
# Run `make kernel` and `make rootfs` first (or docker build the targets
# yourself), then this script pulls the artifacts out of the images.
# =============================================================================

set -euo pipefail

readonly KERNEL_IMAGE="${1:-distrox:kernel}"
readonly ROOTFS_IMAGE="${2:-distrox:latest}"
readonly OUTPUT_DIR="${3:-./build}"

readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

mkdir -p "${OUTPUT_DIR}"

# Extract kernel
echo -e "${BLUE}Extracting kernel from ${KERNEL_IMAGE}...${NC}"
docker create --name distrox-kernel-extract "${KERNEL_IMAGE}" > /dev/null
docker cp distrox-kernel-extract:/build/linux/arch/x86/boot/bzImage "${OUTPUT_DIR}/bzImage"
docker rm distrox-kernel-extract > /dev/null
echo -e "${GREEN}✓ Kernel extracted: ${OUTPUT_DIR}/bzImage${NC}"

# Extract rootfs
echo -e "${BLUE}Extracting rootfs from ${ROOTFS_IMAGE}...${NC}"
docker rm -f distrox-rootfs-extract 2> /dev/null || true
docker create --name distrox-rootfs-extract "${ROOTFS_IMAGE}" > /dev/null
docker cp distrox-rootfs-extract:/build/rootfs.tar.gz "${OUTPUT_DIR}/rootfs.tar.gz"
docker rm distrox-rootfs-extract > /dev/null
echo -e "${GREEN}✓ Rootfs extracted: ${OUTPUT_DIR}/rootfs.tar.gz${NC}"

echo -e "${GREEN}All artifacts extracted to ${OUTPUT_DIR}/${NC}"
echo "Next steps: make userspace init initramfs iso"
