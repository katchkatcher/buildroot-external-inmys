#!/bin/bash
# burn.sh — flash br_2024.02_rk3568.dd to eMMC (via Maskrom) or an SD card
#
#   sudo ./burn.sh emmc              full flash (MBR + U-Boot + p1 + p2)
#   sudo ./burn.sh emmc update       system update (MBR + U-Boot + p1), preserves p2 (/opt)
#   sudo ./burn.sh sd /dev/sdX       flash to SD card

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="${DIR}/br_2024.02_rk3568.dd"
MBR="${DIR}/mbr.dat"
UBOOT="${DIR}/u-boot-rockchip.bin"
ROOTFS="${DIR}/rootfs.ext2"
DDR="${DIR}/rk3568_ddr_1332MHz_v1.23.bin"
USBPLUG="${DIR}/rk356x_usbplug_v1.17.bin"
P1_START=32768

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }

[ "$(id -u)" -eq 0 ] || die "root privileges required (run with sudo)"

cmd_sd() {
    local dev="${1:-}"
    [ -n "$dev" ] || die "usage: $0 sd /dev/sdX"
    [ -b "$dev" ] || die "$dev is not a block device"
    [ -f "$IMG" ] || die "$IMG not found"

    local root_src
    root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
    case "$root_src" in
        "$dev"|"$dev"*) die "$dev contains the host root filesystem" ;;
    esac

    local isz dsz
    isz=$(stat -c%s "$IMG"); dsz=$(blockdev --getsize64 "$dev")
    [ "$dsz" -ge "$isz" ] || die "target device ($dsz bytes) is smaller than image ($isz bytes)"

    lsblk "$dev"; echo
    read -rp "DESTROY ALL DATA on $dev? Type the device path to confirm: " a
    [ "$a" = "$dev" ] || die "aborted"

    for p in "$dev"?*; do [ -e "$p" ] && umount "$p" 2>/dev/null || true; done

    dd if="$IMG" of="$dev" bs=4M conv=fsync status=progress
    sync
    ok "SD card is ready"
}

maskrom_init() {
    command -v xrock >/dev/null || die "xrock utility not found in PATH"
    [ -f "$DDR" ]     || die "$DDR not found"
    [ -f "$USBPLUG" ] || die "$USBPLUG not found"
    lsusb | grep -q "2207:350a" || die "RK3568 device in Maskrom mode not found"
    ok "board detected in Maskrom mode"
    xrock maskrom "$DDR" "$USBPLUG" --rc4-off || die "Maskrom initialization failed"
    sleep 2
}

verify() {
    local tmp; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    xrock flash read 0 1 "$tmp" >/dev/null
    [ "$(xxd -p "$tmp" | head -1)" != "$(printf '0%.0s' {1..1024})" ] || die "MBR verification failed (sector 0 is empty)"
    ok "MBR OK"
    xrock flash read 64 1 "$tmp" >/dev/null
    local u; u=$(xxd -p "$tmp" | head -1)
    [ "${u:0:8}" = "524b4e53" ] || die "U-Boot verification failed (missing RKNS magic at sector 64)"
    ok "U-Boot OK"
}

cmd_emmc() {
    local mode="${1:-full}"
    maskrom_init
    case "$mode" in
        full|"")
            [ -f "$IMG" ] || die "$IMG not found"
            info "full flash: $IMG"
            xrock flash write 0 "$IMG" || die "flash write failed"
            ;;
        update)
            [ -f "$MBR" ] && [ -f "$UBOOT" ] && [ -f "$ROOTFS" ] || die "missing mbr.dat, u-boot-rockchip.bin, or rootfs.ext2"
            info "update: MBR + U-Boot + p1 (preserving p2 /opt)"
            xrock flash write 0         "$MBR"    || die "failed to write MBR"
            xrock flash write 64        "$UBOOT"  || die "failed to write U-Boot"
            xrock flash write $P1_START "$ROOTFS" || die "failed to write rootfs (p1)"
            ;;
        *) die "unknown mode: $mode" ;;
    esac
    verify
    ok "done. Power off the board, remove jumper X2, and power on."
}

case "${1:-}" in
    emmc) shift; cmd_emmc "$@" ;;
    sd)   shift; cmd_sd "$@" ;;
    *)
        echo "Usage:"
        echo "  sudo $0 emmc             full flash to eMMC (MBR + U-Boot + p1 + p2)"
        echo "  sudo $0 emmc update      update eMMC system (preserves p2 /opt)"
        echo "  sudo $0 sd /dev/sdX      flash full image to SD card"
        exit 1 ;;
esac