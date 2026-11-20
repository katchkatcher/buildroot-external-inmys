# Makefile in buildroot-external-inmys/burn/
#
# Assembles br_2024.02_rk3568.dd from Buildroot output/images/:
#   - rootfs.ext2         (from output/images/)
#   - u-boot-rockchip.bin (from output/images/)
#   - p2.ext2             (generated: empty ext4 image labeled STORE)
#   - mbr.dat             (generated: MBR with p1 rootfs + p2 STORE)
#
# Usage:
#   make                  build everything (incremental)
#   make force-rootfs all force-rebuild rootfs.ext2 and rebuild .dd
#   make clean            remove generated artifacts in burn/
#   make force            clean and rebuild everything from scratch

CURDIR     := $(shell pwd)
BR_DIR     := $(CURDIR)/../..
OUTPUT     := $(BR_DIR)/output
OUT_IMG    := $(OUTPUT)/images

ROOTFS_IN  := $(OUT_IMG)/rootfs.ext2
UBOOT_IN   := $(OUT_IMG)/u-boot-rockchip.bin

ROOTFS     := $(CURDIR)/rootfs.ext2
UBOOT      := $(CURDIR)/u-boot-rockchip.bin
P2         := $(CURDIR)/p2.ext2
MBR        := $(CURDIR)/mbr.dat
DD         := $(CURDIR)/br_2024.02_rk3568.dd

P1_START   := 32768
P2_SIZE_MB := 2048
P2_SECTORS := $(shell echo $$(( $(P2_SIZE_MB) * 2048 )))
DISK_ID    := 0x35680001

# Helper shell snippet: computes ROOTFS_SECTORS, P2_START, and TOTAL_SECTORS
define CALC_LAYOUT
	ROOTFS_SECTORS=$$(stat -c%s "$(ROOTFS)" | awk '{print int(($$1+511)/512)}'); \
	P2_START=$$(( $(P1_START) + $$ROOTFS_SECTORS )); \
	TOTAL_SECTORS=$$(( $$P2_START + $(P2_SECTORS) ))
endef

all: $(DD)

# 1) Build Buildroot artifacts (rootfs.ext2, u-boot-rockchip.bin, Image, dtb)
$(ROOTFS_IN):
	$(MAKE) -C $(OUTPUT)

$(UBOOT_IN): | $(ROOTFS_IN)

$(ROOTFS): $(ROOTFS_IN)
	cp -f $< $@

$(UBOOT): $(UBOOT_IN)
	cp -f $< $@

# 2) Create empty ext4 image for partition 2 (STORE)
$(P2):
	@echo "[*] Creating $(P2_SIZE_MB) MiB ext4 image ($@) with label STORE"
	dd if=/dev/zero of=$@ bs=1M count=$(P2_SIZE_MB) status=progress
	mkfs.ext4 -F -q -L STORE $@
	@echo "[+] $@ ready"

# 3) Generate MBR partition table (p1: rootfs, p2: STORE)
$(MBR): $(ROOTFS) $(P2)
	@$(CALC_LAYOUT); \
	echo "[*] Generating $@: p1=$$ROOTFS_SECTORS sectors (start=$(P1_START)), p2=$(P2_SECTORS) sectors (start=$$P2_START)"; \
	rm -f $@.tmp; \
	dd if=/dev/zero of=$@.tmp bs=512 count=$$TOTAL_SECTORS status=none; \
	{ printf "label: dos\nlabel-id: $(DISK_ID)\n1: start=$(P1_START), size=$$ROOTFS_SECTORS, type=83, bootable\n2: start=$$P2_START, size=$(P2_SECTORS), type=83\n" | sfdisk -u S $@.tmp; } || { rm -f $@.tmp; exit 1; }; \
	dd if=$@.tmp of=$@ bs=512 count=1 status=none; \
	rm -f $@.tmp; \
	fdisk -l -u $@ | grep -q "mbr.dat1" || { echo "ERROR: partition 1 missing in $@"; exit 1; }; \
	fdisk -l -u $@ | grep -q "mbr.dat2" || { echo "ERROR: partition 2 missing in $@"; exit 1; }; \
	echo "[+] $@ OK"

# 4) Assemble final bootable disk image (.dd)
$(DD): $(MBR) $(ROOTFS) $(P2) $(UBOOT)
	@$(CALC_LAYOUT); \
	echo "[*] Assembling disk image $@ ($$TOTAL_SECTORS sectors)"; \
	dd if=/dev/zero of=$@ bs=512 count=$$TOTAL_SECTORS status=progress; \
	dd if=$(MBR)    of=$@ bs=512 seek=0           conv=notrunc status=none; \
	dd if=$(UBOOT)  of=$@ bs=512 seek=64          conv=notrunc status=none; \
	dd if=$(ROOTFS) of=$@ bs=512 seek=$(P1_START) conv=notrunc status=progress; \
	dd if=$(P2)     of=$@ bs=512 seek=$$P2_START  conv=notrunc status=progress; \
	echo "[*] Verifying $@"; \
	fdisk -l -u $@ | grep -q "dd1" || { echo "ERROR: partition 1 missing in $@"; exit 1; }; \
	fdisk -l -u $@ | grep -q "dd2" || { echo "ERROR: partition 2 missing in $@"; exit 1; }; \
	UB=$$(dd if=$@ bs=512 skip=64 count=1 2>/dev/null | xxd -p | head -c 8); \
	[ "$$UB" = "524b4e53" ] || { echo "ERROR: RKNS header not found at sector 64 in $@"; exit 1; }; \
	ls -lh $@; \
	echo "[+] Done: $@"

force-rootfs:
	rm -f $(ROOTFS_IN) $(ROOTFS)
	$(MAKE) -C $(OUTPUT)

clean:
	rm -f $(DD) $(MBR) $(P2) $(ROOTFS) $(UBOOT) mbr.dat.tmp

force: clean all

.PHONY: all clean force force-rootfs