#!/bin/bash
set -u

image="$1"
buildcontext="$2"

./startvm.sh -s -M -a quiet \
    -a "systemd.unit=basic.target" \
    -a "systemd.wants=builder.service" \
    -F "$buildcontext" \
    "$image"
