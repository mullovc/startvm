#!/bin/bash
set -u

datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
layerdir="$datadir/layers"
tagdir="$datadir/tags"
partsize=10G

if [[ $# -eq 3 ]]; then
    from="$1"
    tag="$2"
    buildcontext="$3"

    layeruuid="$(uuidgen)"
    upperimage="$layerdir/$layeruuid.ext2"
    emptydir=$(mktemp -d)

    mke2fs -L "$tag" -U "$layeruuid" -d "${emptydir}" "${upperimage}" "${partsize}"

    cp -i "$tagdir/$from" "$tagdir/$tag"
    echo "$layeruuid" >> "$tagdir/$tag"
else
    tag="$1"
    buildcontext="$2"
fi

./startvm-tag.sh -s -M -a quiet \
    -a "systemd.unit=basic.target" \
    -a "systemd.wants=builder.service" \
    -F "$buildcontext" \
    "$tag"
