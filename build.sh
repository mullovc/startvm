#!/bin/bash
set -u

datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
imagedir="$datadir/images"

if [[ $# -eq 3 ]]; then
    base="$1"
    image="$2"
    buildcontext="$3"

    imagefile="$imagedir/$image.qcow2"
    # relative paths are looked up relative to $imagefile
    backingformat=qcow2
    backingfile="$base.$backingformat"
    qemu-img create -F "$backingformat" -f qcow2 -b "$backingfile" "$imagefile"
else
    # TODO write changes to qcow2 snapshot and commit upon successful build
    image="$1"
    buildcontext="$2"
fi

startvm.sh -s -M -a quiet \
    -a "systemd.unit=basic.target" \
    -a "systemd.wants=builder.service" \
    -v "$buildcontext" \
    "$image"
