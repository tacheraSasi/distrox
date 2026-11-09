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
ZIG           := anyzig
ZIG_OUT       := userspace/zig-out/bin
INIT_BIN      := init/zig-out/bin/init
ZIG_USPACE    := 0.15.1
ZIG_INIT      := 0.16.0

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
	@printf "$(COLOR_BOLD)distrox Build System$(COLOR_RESET)\n"
	@printf "\n"
	@printf "$(COLOR_BOLD)Targets:$(COLOR_RESET)\n"
	@printf "  $(COLOR_GREEN)build$(COLOR_RESET)      - Full build: kernel+rootfs+userspace+init+initramfs+iso\n"
	@printf "  $(COLOR_GREEN)kernel$(COLOR_RESET)      - Build bzImage via Docker\n"
	@printf "  $(COLOR_GREEN)rootfs$(COLOR_RESET)      - Build Alpine rootfs.tar.gz via Docker\n"
	@printf "  $(COLOR_GREEN)userspace$(COLOR_RESET)   - Compile Zig userspace (x86_64-linux-musl)\n"
	@printf "  $(COLOR_GREEN)init$(COLOR_RESET)         - Compile Zig PID 1 init (x86_64-linux-musl)\n"
	@printf "  $(COLOR_GREEN)initramfs$(COLOR_RESET)   - Pack rootfs + Zig bins + init into initramfs\n"
	@printf "  $(COLOR_GREEN)iso$(COLOR_RESET)         - Assemble output.iso locally\n"
	@printf "  $(COLOR_GREEN)qemu$(COLOR_RESET)        - Boot ISO in QEMU (GUI)\n"
	@printf "  $(COLOR_GREEN)qemu-nographic$(COLOR_RESET) - Boot ISO in QEMU (serial console)\n"
	@printf "  $(COLOR_GREEN)qemu-network$(COLOR_RESET)   - Boot ISO with user-mode networking\n"
	@printf "  $(COLOR_GREEN)clean$(COLOR_RESET)       - Remove build artifacts\n"
	@printf "  $(COLOR_GREEN)check-deps$(COLOR_RESET)  - Verify local tooling\n"
	@printf "\n"
	@printf "$(COLOR_BOLD)Examples:$(COLOR_RESET)\n"
	@printf "  make build && make qemu-nographic   # everything + boot\n"

# -----------------------------------------------------------------------------
# Full build
# -----------------------------------------------------------------------------
build: kernel rootfs userspace init initramfs iso
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Build complete: $(ISO_OUTPUT)$(COLOR_RESET)\n"

# -----------------------------------------------------------------------------
# Kernel (Docker)
# -----------------------------------------------------------------------------
kernel:
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Building kernel...$(COLOR_RESET)\n"
	@mkdir -p $(BUILD_DIR)
	docker build --target kernel-builder -t $(IMAGE_NAME):kernel .
	@docker create --name distrox-kernel $(IMAGE_NAME):kernel > /dev/null
	@docker cp distrox-kernel:/build/linux/arch/x86/boot/bzImage $(BZIMAGE)
	@docker rm distrox-kernel > /dev/null
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Kernel: $(BZIMAGE)$(COLOR_RESET)\n"

# -----------------------------------------------------------------------------
# Rootfs (Docker)
# -----------------------------------------------------------------------------
rootfs:
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Building Alpine rootfs...$(COLOR_RESET)\n"
	@mkdir -p $(BUILD_DIR)
	docker build --target rootfs-builder -t $(IMAGE_NAME):$(DOCKER_TAG) .
	@docker rm -f distrox-rootfs 2>/dev/null || true
	@docker create --name distrox-rootfs $(IMAGE_NAME):$(DOCKER_TAG) > /dev/null
	@docker cp distrox-rootfs:/build/rootfs.tar.gz $(ROOTFS_TAR)
	@docker rm distrox-rootfs > /dev/null
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Rootfs: $(ROOTFS_TAR)$(COLOR_RESET)\n"
	@ls -lh $(ROOTFS_TAR)

# -----------------------------------------------------------------------------
# Zig userspace (local)
# -----------------------------------------------------------------------------
userspace:
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Building Zig userspace...$(COLOR_RESET)\n"
	cd userspace && $(ZIG) $(ZIG_USPACE) build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast
	@ls -la $(ZIG_OUT) 2>/dev/null || printf "$(COLOR_YELLOW)! no binaries in $(ZIG_OUT)$(COLOR_RESET)\n"

# -----------------------------------------------------------------------------
# Zig init PID 1 (local)
# -----------------------------------------------------------------------------
init:
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Building Zig init...$(COLOR_RESET)\n"
	cd init && $(ZIG) $(ZIG_INIT) build --release=small -Dtarget=x86_64-linux-musl
	@ls -lh $(INIT_BIN) 2>/dev/null || printf "$(COLOR_YELLOW)! init binary not found$(COLOR_RESET)\n"

# -----------------------------------------------------------------------------
# Initramfs (local)
# -----------------------------------------------------------------------------
initramfs: rootfs userspace init
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Packing initramfs...$(COLOR_RESET)\n"
	@mkdir -p $(BUILD_DIR)
	@bash scripts/mkinitramfs.sh $(ROOTFS_TAR) $(ZIG_OUT) $(INITRAMFS) $(INIT_BIN)
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Initramfs: $(INITRAMFS)$(COLOR_RESET)\n"
	@ls -lh $(INITRAMFS)

# -----------------------------------------------------------------------------
# Syslinux (local, downloaded once)
# -----------------------------------------------------------------------------
$(SYSLINUX_DIR)/isolinux.bin:
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Downloading syslinux $(SYSLINUX_VER)...$(COLOR_RESET)\n"
	@mkdir -p $(SYSLINUX_DIR)
	@curl -fsSL -o /tmp/syslinux-$(SYSLINUX_VER).tar.gz \
		https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-$(SYSLINUX_VER).tar.gz
	@tar xzf /tmp/syslinux-$(SYSLINUX_VER).tar.gz -C /tmp
	@cp /tmp/syslinux-$(SYSLINUX_VER)/bios/core/isolinux.bin \
		/tmp/syslinux-$(SYSLINUX_VER)/bios/com32/elflink/ldlinux/ldlinux.c32 \
		/tmp/syslinux-$(SYSLINUX_VER)/bios/mbr/isohdpfx.bin \
		$(SYSLINUX_DIR)/
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Syslinux files in $(SYSLINUX_DIR)$(COLOR_RESET)\n"

# -----------------------------------------------------------------------------
# ISO (local)
# -----------------------------------------------------------------------------
iso: $(SYSLINUX_DIR)/isolinux.bin
	@test "$(XORRISO)" != "" || { printf "$(COLOR_RED)✗ xorriso not found — install: sudo pacman -S libisoburn$(COLOR_RESET)\n"; exit 1; }
	@test -f $(BZIMAGE) || { printf "$(COLOR_RED)✗ $(BZIMAGE) missing — run: make kernel$(COLOR_RESET)\n"; exit 1; }
	@test -f "$(INITRAMFS)" || { printf "$(COLOR_RED)✗ $(INITRAMFS) missing — run: make initramfs$(COLOR_RESET)\n"; exit 1; }
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Assembling ISO...$(COLOR_RESET)\n"
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
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ ISO: $(ISO_OUTPUT)$(COLOR_RESET)\n"
	@ls -lh $(ISO_OUTPUT)

# -----------------------------------------------------------------------------
# QEMU
# -----------------------------------------------------------------------------
qemu:
	@test -f $(ISO_OUTPUT) || { printf "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)\n"; exit 1; }
	@printf "$(COLOR_YELLOW)Press Ctrl+Alt+2 for QEMU console, Ctrl+Alt+1 to return$(COLOR_RESET)\n"
	qemu-system-x86_64 -cdrom $(ISO_OUTPUT) -m $(QEMU_MEMORY)

qemu-nographic:
	@test -f $(ISO_OUTPUT) || { printf "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)\n"; exit 1; }
	@printf "$(COLOR_YELLOW)Press Ctrl+A then X to exit$(COLOR_RESET)\n"
	qemu-system-x86_64 -cdrom $(ISO_OUTPUT) -m $(QEMU_MEMORY) -nographic

qemu-network:
	@test -f $(ISO_OUTPUT) || { printf "$(COLOR_RED)✗ ISO missing — run: make iso$(COLOR_RESET)\n"; exit 1; }
	@printf "$(COLOR_YELLOW)Press Ctrl+A then X to exit$(COLOR_RESET)\n"
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
	@printf "$(COLOR_BOLD)$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)\n"
	@rm -rf $(BUILD_DIR)
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Cleaned$(COLOR_RESET)\n"

check-deps:
	@printf "$(COLOR_BOLD)Checking dependencies...$(COLOR_RESET)\n"
	@command -v docker >/dev/null 2>&1 || { printf "$(COLOR_RED)✗ docker not found — install: sudo pacman -S docker$(COLOR_RESET)\n"; exit 1; }
	@command -v qemu-system-x86_64 >/dev/null 2>&1 || printf "$(COLOR_YELLOW)! qemu-system-x86_64 not found (optional) — install: sudo pacman -S qemu-desktop$(COLOR_RESET)\n"
	@command -v xorriso >/dev/null 2>&1 || printf "$(COLOR_YELLOW)! xorriso not found — install: sudo pacman -S libisoburn$(COLOR_RESET)\n"
	@command -v bsdtar >/dev/null 2>&1 || printf "$(COLOR_YELLOW)! bsdtar not found — install: sudo pacman -S libarchive$(COLOR_RESET)\n"
	@command -v $(ZIG) >/dev/null 2>&1 || printf "$(COLOR_YELLOW)! anyzig not found — install: cargo install anyzig (https://github.com/sno2/anyzig)$(COLOR_RESET)\n"
	@printf "$(COLOR_BOLD)$(COLOR_GREEN)✓ Done$(COLOR_RESET)\n"
