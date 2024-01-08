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
usekernel=y
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
    -N      don't use host kernel and initrd image
    -a      append to kernel commandline
    -A      audio
    -s      non-graphical mode (serial port)
    -M      mutable VM
    -v      expose directory inside VM
    -Q      additional Qemu parameters
    -m      amount of virtual memory

EOF
}

OPTIND=1
while getopts 'hNMsAa:v:Q:m:' opt
do
    case "$opt" in
        h)
            show_usage
            exit 0
            ;;
        N)
            usekernel=n
            ;;
        a)
            usekernel=y
            cmdline+=("${OPTARG}")
            ;;
        A)
            additional_params+=(-device virtio-sound-pci,audiodev=my_audiodev)
            additional_params+=(-audiodev pa,id=my_audiodev)
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
        v)
            IFS=: read -r volsource voltarget rorw <<< "$OPTARG"
            snapshot=on
            [[ ${rorw:-ro} = rw ]] && snapshot=off
            additional_params+=(-drive "if=virtio,snapshot=$snapshot,file=fat:${rorw:-ro}:$volsource")
            cmdline+=("voltarget=$voltarget")
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
[[ $VGA = virgl ]] && additional_params+=(-device virtio-gpu-gl-pci)
[[ $VGA = virtio ]] && additional_params+=(-device virtio-vga-gl)
if [[ $VGA = virgl-vhost-user ]]; then
    vgpuuuid="$(uuidgen)"
    additional_params+=(-chardev socket,id=vgpu,path=/var/tmp/vgpu-"$vgpuuuid".sock)
    additional_params+=(-device vhost-user-gpu-pci,chardev=vgpu)
    additional_params+=(-object memory-backend-memfd,id=mem,size=4G,share=on)
    additional_params+=(-numa node,memdev=mem)
    # XXX wait until socket creation finished?
    /usr/lib/qemu/vhost-user-gpu --virgl --socket-path /var/tmp/vgpu-"$vgpuuuid".sock &
fi

if [[ ${usekernel:-} = y ]]; then
    cmdline+=("root=$rootdevice rw")
    additional_params+=(-drive if=virtio,readonly=on,file="$bootfiledir/kernelmodules.ext2")
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
    -drive if=virtio,file="${image}" "${additional_params[@]}"
