# =============================================================================
# Makefile for distrox
#
# The pipeline is split into heavy Docker stages (kernel, rootfs) and
# fast local steps (userspace, initramfs, iso):
#
#   make kernel   # Docker: compile bzImage                    (~20 min once)
#   make rootfs   # Docker: slim Alpine rootfs -> rootfs.tar.gz (~2 min once)
#   make userspace# Local:  zig build x86_64-linux-musl bins   (seconds)
#   make init     # Local:  zig build x86_64-linux-musl PID 1  (seconds)
#   make initramfs# Local:  rootfs.tar + zig bins + init -> cpio (seconds)
#   make iso      # Local:  bzImage + initramfs -> output.iso  (seconds)
#   make build    # everything above
#   make qemu     # boot output.iso
# =============================================================================

.PHONY: help build kernel rootfs userspace init initramfs syslinux iso \
        qemu qemu-nographic qemu-network clean check-deps

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
IMAGE_NAME    := distrox
DOCKER_TAG    := latest
QEMU_MEMORY   := 2048M
SYSLINUX_VER  := 6.03

# Local artifacts
BUILD_DIR     := build
BZIMAGE       := $(BUILD_DIR)/bzImage
ROOTFS_TAR    := $(BUILD_DIR)/rootfs.tar.gz
INITRAMFS     := $(BUILD_DIR)/initramfs
ISO_OUTPUT    := $(BUILD_DIR)/output.iso
ISOFILES_DIR  := $(BUILD_DIR)/isofiles
SYSLINUX_DIR  := $(BUILD_DIR)/syslinux
ZIG_OUT       := userspace/zig-out/bin
INIT_BIN      := init/zig-out/bin/init
ZIG_0151      := /Users/mac/.zvm/0.15.1/zig
ZIG_0160      := /Users/mac/.zvm/0.16.0/zig

XORRISO       := $(shell command -v xorriso 2>/dev/null)

# Colors
COLOR_RESET  := \033[0m
COLOR_BOLD   := \033[1m
COLOR_GREEN  := \033[32m
COLOR_BLUE   := \033[34m
COLOR_YELLOW := \033[33m

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
help:
	@echo "$(COLOR_BOLD)distrox Build System$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Targets:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)build$(COLOR_RESET)      - Full build: kernel+rootfs+userspace+init+initramfs+iso"
	@echo "  $(COLOR_GREEN)kernel$(COLOR_RESET)      - Build bzImage via Docker"
	@echo "  $(COLOR_GREEN)rootfs$(COLOR_RESET)      - Build Alpine rootfs.tar.gz via Docker"
	@echo "  $(COLOR_GREEN)userspace$(COLOR_RESET)   - Compile Zig userspace (x86_64-linux-musl)"
	@echo "  $(COLOR_GREEN)init$(COLOR_RESET)         - Compile Zig PID 1 init (x86_64-linux-musl)"
	@echo "  $(COLOR_GREEN)initramfs$(COLOR_RESET)   - Pack rootfs + Zig bins + init into initramfs"
	@echo "  $(COLOR_GREEN)iso$(COLOR_RESET)         - Assemble output.iso locally"
	@echo "  $(COLOR_GREEN)qemu$(COLOR_RESET)        - Boot ISO in QEMU (GUI)"
	@echo "  $(COLOR_GREEN)qemu-nographic$(COLOR_RESET) - Boot ISO in QEMU (serial console)"
	@echo "  $(COLOR_GREEN)qemu-network$(COLOR_RESET)   - Boot ISO with user-mode networking"
	@echo "  $(COLOR_GREEN)clean$(COLOR_RESET)       - Remove build artifacts"
	@echo "  $(COLOR_GREEN)check-deps$(COLOR_RESET)  - Verify local tooling"
	@echo ""
	@echo "$(COLOR_BOLD)Examples:$(COLOR_RESET)"
	@echo "  make build && make qemu-nographic   # everything + boot"

# -----------------------------------------------------------------------------
# Full build
# -----------------------------------------------------------------------------
build: kernel rootfs userspace init initramfs iso
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Build complete: $(ISO_OUTPUT)$(COLOR_RESET)"

# -----------------------------------------------------------------------------
# Kernel (Docker)
# -----------------------------------------------------------------------------
kernel:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Building kernel...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)
	docker build --target kernel-builder -t $(IMAGE_NAME):kernel .
	@docker create --name distrox-kernel $(IMAGE_NAME):kernel > /dev/null
	@docker cp distrox-kernel:/build/linux/arch/x86/boot/bzImage $(BZIMAGE)
	@docker rm distrox-kernel > /dev/null
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Kernel: $(BZIMAGE)$(COLOR_RESET)"

# -----------------------------------------------------------------------------
# Rootfs (Docker)
# -----------------------------------------------------------------------------
rootfs:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Building Alpine rootfs...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)
	docker build --target rootfs-builder -t $(IMAGE_NAME):$(DOCKER_TAG) .
	@docker rm -f distrox-rootfs 2>/dev/null || true
	@docker create --name distrox-rootfs $(IMAGE_NAME):$(DOCKER_TAG) > /dev/null
	@docker cp distrox-rootfs:/build/rootfs.tar.gz $(ROOTFS_TAR)
	@docker rm distrox-rootfs > /dev/null
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Rootfs: $(ROOTFS_TAR)$(COLOR_RESET)"
	@ls -lh $(ROOTFS_TAR)

# -----------------------------------------------------------------------------
# Zig userspace (local)
# -----------------------------------------------------------------------------
userspace:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Building Zig userspace...$(COLOR_RESET)"
	@if command -v $(ZIG_0151) >/dev/null 2>&1; then \
		cd userspace && $(ZIG_0151) build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast; \
	else \
		echo "$(COLOR_YELLOW)! $(ZIG_0151) not found - skipping userspace (binaries from $(ZIG_OUT) still get packed if present)$(COLOR_RESET)"; \
	fi
	@ls -la $(ZIG_OUT) 2>/dev/null || echo "$(COLOR_YELLOW)! no binaries in $(ZIG_OUT)$(COLOR_RESET)"

# -----------------------------------------------------------------------------
# Zig init PID 1 (local)
# -----------------------------------------------------------------------------
init:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Building Zig init...$(COLOR_RESET)"
	@if command -v $(ZIG_0160) >/dev/null 2>&1; then \
		cd init && $(ZIG_0160) build --release=small -Dtarget=x86_64-linux-musl; \
	else \
		echo "$(COLOR_YELLOW)! $(ZIG_0160) not found$(COLOR_RESET)"; exit 1; \
	fi
	@ls -lh $(INIT_BIN) 2>/dev/null || echo "$(COLOR_YELLOW)! init binary not found$(COLOR_RESET)"

# -----------------------------------------------------------------------------
# Initramfs (local)
# -----------------------------------------------------------------------------
initramfs: rootfs userspace init
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Packing initramfs...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)
	@bash scripts/mkinitramfs.sh $(ROOTFS_TAR) $(ZIG_OUT) $(INITRAMFS) $(INIT_BIN)
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Initramfs: $(INITRAMFS)$(COLOR_RESET)"
	@ls -lh $(INITRAMFS)

# -----------------------------------------------------------------------------
# Syslinux (local, downloaded once)
# -----------------------------------------------------------------------------
$(SYSLINUX_DIR)/isolinux.bin:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Downloading syslinux $(SYSLINUX_VER)...$(COLOR_RESET)"
	@mkdir -p $(SYSLINUX_DIR)
	@curl -fsSL -o /tmp/syslinux-$(SYSLINUX_VER).tar.gz \
		https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-$(SYSLINUX_VER).tar.gz
	@tar xzf /tmp/syslinux-$(SYSLINUX_VER).tar.gz -C /tmp
	@cp /tmp/syslinux-$(SYSLINUX_VER)/bios/core/isolinux.bin \
		/tmp/syslinux-$(SYSLINUX_VER)/bios/com32/elflink/ldlinux/ldlinux.c32 \
		/tmp/syslinux-$(SYSLINUX_VER)/bios/mbr/isohdpfx.bin \
		$(SYSLINUX_DIR)/
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Syslinux files in $(SYSLINUX_DIR)$(COLOR_RESET)"

# -----------------------------------------------------------------------------
# ISO (local)
# -----------------------------------------------------------------------------
iso: $(SYSLINUX_DIR)/isolinux.bin
	@test "$(XORRISO)" != "" || { echo "$(COLOR_RED)✗ xorriso not found — brew install xorriso$(COLOR_RESET)"; exit 1; }
	@test -f $(BZIMAGE) || { echo "$(COLOR_RED)✗ $(BZIMAGE) missing — run: make kernel$(COLOR_RESET)"; exit 1; }
	@test -f "$(INITRAMFS)" || { echo "$(COLOR_RED)✗ $(INITRAMFS) missing — run: make initramfs$(COLOR_RESET)"; exit 1; }
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Assembling ISO...$(COLOR_RESET)"
	@rm -rf $(ISOFILES_DIR) && mkdir -p $(ISOFILES_DIR)/isolinux
	@cp $(BZIMAGE) $(ISOFILES_DIR)/bzImage
	@cp $(INITRAMFS) $(ISOFILES_DIR)/initramfs
	@cp syslinux.cfg $(ISOFILES_DIR)/isolinux/isolinux.cfg
	@cp $(SYSLINUX_DIR)/isolinux.bin $(SYSLINUX_DIR)/ldlinux.c32 $(ISOFILES_DIR)/isolinux/
	@xorriso -as mkisofs \
		-isohybrid-mbr $(SYSLINUX_DIR)/isohdpfx.bin \
		-J -R \
		-o $(ISO_OUTPUT) \
		-b isolinux/isolinux.bin \
		-c isolinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$(ISOFILES_DIR)
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ ISO: $(ISO_OUTPUT)$(COLOR_RESET)"
	@ls -lh $(ISO_OUTPUT)

# -----------------------------------------------------------------------------
# QEMU
# -----------------------------------------------------------------------------
qemu:
	@test -f $(ISO_OUTPUT) || { echo "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)"; exit 1; }
	@echo "$(COLOR_YELLOW)Press Ctrl+Alt+2 for QEMU console, Ctrl+Alt+1 to return$(COLOR_RESET)"
	qemu-system-x86_64 -cdrom $(ISO_OUTPUT) -m $(QEMU_MEMORY)

qemu-nographic:
	@test -f $(ISO_OUTPUT) || { echo "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)"; exit 1; }
	@echo "$(COLOR_YELLOW)Press Ctrl+A then X to exit$(COLOR_RESET)"
	qemu-system-x86_64 -cdrom $(ISO_OUTPUT) -m $(QEMU_MEMORY) -nographic

qemu-network:
	@test -f $(ISO_OUTPUT) || { echo "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)"; exit 1; }
	@echo "$(COLOR_YELLOW)Press Ctrl+A then X to exit$(COLOR_RESET)"
	qemu-system-x86_64 \
		-cdrom $(ISO_OUTPUT) \
		-m $(QEMU_MEMORY) \
		-netdev user,id=net0 \
		-device e1000,netdev=net0 \
		-nographic

# -----------------------------------------------------------------------------
# Cleanup / deps
# -----------------------------------------------------------------------------
clean:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	@rm -rf $(BUILD_DIR)
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Cleaned$(COLOR_RESET)"

check-deps:
	@echo "$(COLOR_BOLD)Checking dependencies...$(COLOR_RESET)"
	@command -v docker >/dev/null 2>&1 || { echo "$(COLOR_RED)✗ docker not found$(COLOR_RESET)"; exit 1; }
	@command -v qemu-system-x86_64 >/dev/null 2>&1 || echo "$(COLOR_YELLOW)! qemu-system-x86_64 not found (optional)$(COLOR_RESET)"
	@command -v xorriso >/dev/null 2>&1 || echo "$(COLOR_YELLOW)! xorriso not found — brew install xorriso$(COLOR_RESET)"
	@command -v zig >/dev/null 2>&1 || echo "$(COLOR_YELLOW)! zig not found (needed for make userspace)$(COLOR_RESET)"
	@command -v $(ZIG_0151) >/dev/null 2>&1 || echo "$(COLOR_YELLOW)! $(ZIG_0151) not found (userspace)$(COLOR_RESET)"
	@command -v $(ZIG_0160) >/dev/null 2>&1 || echo "$(COLOR_YELLOW)! $(ZIG_0160) not found (init)$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Done$(COLOR_RESET)"
