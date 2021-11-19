#!/bin/bash
set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
config="${SCRIPT_DIR}/initcpio/mkinitcpio.conf"
kernel="/boot/vmlinuz-linux"
datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
bootfiledir="$datadir/boot"
imagename="initrd-virtio.img"

modulesimage="${bootfiledir}/kernelmodules.ext2"
modulessize="512M"
kernelversion="${1:-$(uname -r)}"


# copied from /usr/lib/initcpio/functions
kver() {
    # this is intentionally very loose. only ensure that we're
    # dealing with some sort of string that starts with something
    # resembling dotted decimal notation. remember that there's no
    # requirement for CONFIG_LOCALVERSION to be set.
    local kver re='^[[:digit:]]+(\.[[:digit:]]+)+'

    # scrape the version out of the kernel image. locate the offset
    # to the version string by reading 2 bytes out of image at at
    # address 0x20E. this leads us to a string of, at most, 128 bytes.
    # read the first word from this string as the kernel version.
    local offset=$(hexdump -s 526 -n 2 -e '"%0d"' "$1")
    [[ $offset = +([0-9]) ]] || return 1

    read kver _ < \
        <(dd if="$1" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)

    [[ $kver =~ $re ]] || return 1

    printf '%s' "$kver"
}

mkdir -p "$bootfiledir"

unshare -r mkinitcpio \
    -g "${bootfiledir}/${imagename}" \
    -k "${kernel}" \
    -c "${config}" \
    -D "${SCRIPT_DIR}/initcpio" -D "/etc/initcpio" -D "/usr/lib/initcpio"

#source /usr/lib/initcpio/functions
kernelversion="$(kver "$kernel")"

mke2fs \
    -L "kernel_modules" \
    -d "/usr/lib/modules/${kernelversion}" \
    "${modulesimage}" \
    "${modulessize}"
