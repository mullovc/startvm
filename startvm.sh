#!/bin/bash
set -u

# default configuration options
BIOS="/usr/share/qemu/bios-256k.bin"
VGA=virtio
memory=4096
ncpus=1
fullscreen=off
datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
imagedir="$datadir/images"
bootfiledir="$datadir/boot"
defaultimage=base
kernel="/boot/vmlinuz-linux"
initrd="$bootfiledir/initrd-virtio.img"
rootdevice="LABEL=vmroot"
cmdline=()
additional_params=()

# user configuration
if [[ -f "${XDG_CONFIG_DIR:-$HOME/.config}/startvm/config" ]]; then
    source "${XDG_CONFIG_DIR:-$HOME/.config}/startvm/config"
fi

show_usage() {
    cat << EOF
usage: $0 [options] [VM name]

start a KVM virtual machine

    -h      print this help and exit
    -H      use host kernel and initrd image
    -a      append to kernel commandline (implied -H)
    -A      audio
    -s      non-graphical mode (serial port)
    -M      mutable VM
    -B      use Seabios firmware
    -Q      additional Qemu parameters
    -m      amount of virtual memory

EOF
}

OPTIND=1
while getopts 'hHMsAa:F:BQ:m:' opt
do
    case "$opt" in
        h)
            show_usage
            exit 0
            ;;
        H)
            usekernel=y
            ;;
        a)
            usekernel=y
            cmdline+=("${OPTARG}")
            ;;
        A)
            additional_params+=(-device ES1370)
            ;;
        s)
            VGA=none
            usekernel=y
            cmdline+=("console=ttyS0 panic=1")
            additional_params+=(-nographic -serial mon:stdio -no-reboot)
            ;;
        M)
            mutable=y
            ;;
        F)
            fatrorw=ro
            fatsnapshot=on
            [[ $fatrorw = rw ]] && fatsnapshot=off
            additional_params+=(-drive "if=virtio,snapshot=$fatsnapshot,file=fat:$fatrorw:${OPTARG}")
            ;;
        B)
            BIOS="/usr/share/qemu/bios-256k.bin"
            ;;
        Q)
            # explicitly do not escape
            additional_params+=(${OPTARG})
            ;;
        m)
            memory="${OPTARG}"
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


vmname="${1:-$defaultimage}"
image="${imagedir}/${vmname}.qcow2"

[[ ${mutable:-} = y ]] || additional_params+=(-snapshot)
[[ $VGA = none ]] || additional_params+=(-display gtk,gl=on,full-screen="$fullscreen")

if [[ ${usekernel:-} = y ]]; then
    cmdline+=("root=$rootdevice rw")
    additional_params+=(-drive if=virtio,snapshot=on,file="$bootfiledir/kernelmodules.ext2")
    additional_params+=(-kernel "$kernel" -initrd "$initrd")
    additional_params+=(-append "${cmdline[*]}")
fi


qemu-system-x86_64 \
    -machine accel=kvm,vmport=on \
    -cpu host \
    -smp ${ncpus} \
    -m ${memory} \
    -bios "$BIOS" \
    -sandbox on,spawn=deny \
    -nodefaults \
    -nic user,model=virtio-net-pci,hostfwd="tcp:127.0.0.1:$sshport-:22" \
    -vga "$VGA" \
    -drive if=virtio,file="${image}" "${additional_params[@]}"
