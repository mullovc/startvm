#!/bin/bash
set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
config="${SCRIPT_DIR}/initcpio/mkinitcpio.conf"
kernel="/boot/vmlinuz-linux"
datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
bootfiledir="$datadir/boot"
imagename="initrd-virtio+virtiofs.img"

tmpdir="$(mktemp -d)"

unshare --map-auto --map-root-user mkinitcpio \
    -g "$tmpdir/${imagename}" \
    -k "${kernel}" \
    -c "${config}" \
    -D "${SCRIPT_DIR}/initcpio" -D "/etc/initcpio" -D "/usr/lib/initcpio"

. /etc/os-release
./distributions/"$ID"/mkskeleton "$tmpdir/dist-files.cpio.zst"
find copy_to_root/ |
    cpio -H newc -o --owner="+0:+0" |
    zstd > "$tmpdir/baseconfig.cpio.zst"

mkdir -p "$bootfiledir"
cat "$tmpdir/$imagename" "$tmpdir/dist-files.cpio.zst" "$tmpdir/baseconfig.cpio.zst" > "$bootfiledir/$imagename"

rm "$tmpdir/$imagename" "$tmpdir/dist-files.cpio.zst" "$tmpdir/baseconfig.cpio.zst"
rmdir "$tmpdir"
