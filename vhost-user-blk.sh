#!/bin/bash
set -euo pipefail

socket="/var/tmp/blk.sock"
if [[ $1 = -s || $1 = --socket-path ]]; then
    shift
    socket="$1"
    shift
fi

snapshot="${snapshot:-1}"
image="$1"
ro="on"

[[ $image =~ .qcow2$ ]] && format=qcow2 || format=raw

if (( $snapshot )); then
    # create temporary overlay similar to QEMU's
    # `block.c:bdrv_append_temp_snapshot()` when `-snapshot` option is set
    backingimage="$image"
    image="/var/tmp/vl.$(uuidgen).qcow2"
    qemu-img create -b "$backingimage" -F "$format" -f qcow2 "$image"
    format="qcow2"
    ro="off"
fi

[[ $ro = off ]] && writable=on || writable=off

qemu-storage-daemon \
   --blockdev driver=file,node-name=file,filename="$image",read-only="$ro" \
   --blockdev driver="$format",node-name=qcow2,file=file,read-only="$ro" \
   --export type=vhost-user-blk,id=export,addr.type=unix,addr.path="$socket",node-name=qcow2,writable="$writable"
