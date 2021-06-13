#!/bin/bash
set -u

BIOS=/usr/share/ovmf/x64/OVMF.fd
VGA=virtio
image_basedir="$HOME/VMs"

memory=4096
ncpus=1

hostkernel=
hostinitrd=
cmdline=()

show_usage() {
    cat << EOF
usage: $0 [options] [VM name]

start a KVM virtual machine

    -h      print this help and exit
    -H      use host kernel and initrd image
    -a      append to kernel commandline (implied -H)
    -A      audio
    -s      non-graphical mode (serial port)
    -S      immutable VM (snapshot mode)

EOF
}

# array containing additional runtime dependent parameters
declare -a additional_params

use_hostkernel() {
    # TODO make sure parameters are present only once
    hostkernel="/boot/vmlinuz-linux"
    # non-fallback initrd doesn't contain necessary bock device drivers
    hostinitrd="$image_basedir/initrd-virtio.img"
    #rootdevice="/dev/sda2"
    rootdevice="UUID=2b82b51a-c465-4575-819f-7e12b1d1b919"
    cmdline+=("root=$rootdevice rw")
    additional_params+=(-drive if=virtio,file="$HOME/VMs/kernelmodules.ext2")
    additional_params+=(-kernel "$hostkernel" -initrd "$hostinitrd")
}




OPTIND=1
while getopts 'hHSsAa:F:' opt
do
    case "$opt" in
        h)
            show_usage
            exit 0
            ;;
        H)
            use_hostkernel
            ;;
        a)
            [[ $hostkernel ]] || use_hostkernel
            cmdline+=("${OPTARG}")
            ;;
        A)
            additional_params+=(-device ES1370)
            ;;
        s)
            VGA=none
            [[ $hostkernel ]] || use_hostkernel
            cmdline+=("console=ttyS0 panic=1")
            additional_params+=(-nographic -serial mon:stdio -no-reboot)
            ;;
        S)
            additional_params+=(-snapshot)
            ;;
        F)
            additional_params+=(-hdb "fat:rw:${OPTARG}")
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# find a free port for SSH forwarding, starting with 2222
sshport=2222
while lsof -tnPi TCP:"$sshport" -s TCP:LISTEN > /dev/null
do
    sshport=$((sshport+1))
done


vmname="${1:-xorg}"
image="${image_basedir}/${vmname}.qcow2"

[[ $VGA = none ]] || additional_params+=(-display gtk,gl=on)
[[ ${#cmdline[@]} > 0 ]] && additional_params+=(-append "${cmdline[*]}")


qemu-system-x86_64 \
    -machine accel=kvm,vmport=off \
    -cpu host \
    -smp ${ncpus} \
    -m ${memory} \
    -bios "$BIOS" \
    -sandbox on \
    -nic user,model=virtio-net-pci,hostfwd="tcp:127.0.0.1:$sshport-:22" \
    -vga "$VGA" \
    -usbdevice tablet \
    -drive if=virtio,file="${image}" "${additional_params[@]}"
