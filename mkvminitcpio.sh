#!/bin/bash
set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
config="${SCRIPT_DIR}/initcpio/mkinitcpio.conf"
kernel="/boot/vmlinuz-linux"
datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
bootfiledir="$datadir/boot"
imagename="initrd-virtio+virtiofs.img"


mkdir -p "$bootfiledir"

unshare --map-auto --map-root-user mkinitcpio \
    -g "${bootfiledir}/${imagename}" \
    -k "${kernel}" \
    -c "${config}" \
    -D "${SCRIPT_DIR}/initcpio" -D "/etc/initcpio" -D "/usr/lib/initcpio"
