#!/bin/bash
set -u

# default configuration options
BIOS="/usr/share/qemu/bios-256k.bin"
VGA=virtio
memory=4096
ncpus=1
fullscreen=off
datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
#datadir="."
imagedir="$datadir/images"
bootfiledir="$datadir/boot"
defaultimage=base
usekernel=y
kernel="/boot/vmlinuz-linux"
initrd="$bootfiledir/initrd-virtio+virtiofs.img"
#rootdevice="LABEL=vmroot"
rootdevice="rootfs"
cmdline=()
additional_params=()

# user configuration
if [[ -f "${XDG_CONFIG_DIR:-$HOME/.config}/startvm/config" ]]; then
    source "${XDG_CONFIG_DIR:-$HOME/.config}/startvm/config"
fi
rootdevice="rootfs"

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


#vmname="${1:-$defaultimage}"
#if [[ -f ${imagedir}/${vmname}.qcow2 ]]; then
#    image="${imagedir}/${vmname}.qcow2"
#else
#    image="${imagedir}/${vmname}.ext2"
#fi

[[ ${mutable:-} = y ]] || additional_params+=(-snapshot)
[[ $VGA = none ]] || additional_params+=(-display gtk,gl=on,full-screen="$fullscreen")

cmdline+=("systemd.set_credential=passwd.hashed-password.root:$(openssl passwd -6 root)")
cmdline+=("systemd.set_credential=firstboot.locale:C.UTF-8")
cmdline+=("systemd.set_credential=firstboot.timezone:Europe/Berlin")

if [[ ${usekernel:-} = y ]]; then
    cmdline+=("rootfstype=tmpfs root=$rootdevice rw")
    #additional_params+=(-drive if=virtio,snapshot=on,file="$bootfiledir/kernelmodules.ext2")
    #additional_params+=(-drive if=virtio,readonly=on,file="$bootfiledir/kernelmodules.ext2")
    additional_params+=(-kernel "$kernel" -initrd "$initrd")
    additional_params+=(-append "${cmdline[*]}")
fi

socket="$(mktemp -u)"
/usr/lib/virtiofsd --socket-path=$socket --shared-dir /usr --rlimit-nofile=16384 &

qemu-system-x86_64 \
    -chardev socket,id=char0,path="$socket" \
    -device vhost-user-fs-pci,chardev=char0,tag=myfs \
    -object memory-backend-memfd,id=mem,size=4G,share=on \
    -numa node,memdev=mem \
    -device virtio-keyboard-pci \
    -machine accel=kvm,vmport=on \
    -cpu host \
    -smp ${ncpus} \
    -m ${memory} \
    -bios "$BIOS" \
    -sandbox on,spawn=deny \
    -nodefaults \
    -nic user,model=virtio-net-pci,hostfwd="tcp:127.0.0.1:$sshport-:22" \
    -vga "$VGA" \
    "${additional_params[@]}"
    #-drive if=virtio,file="${image}" "${additional_params[@]}"
    #-fw_cfg name=opt/com.name.domain.your.example,string=1 \

# mount -oro /dev/vda /usr/lib/modules/5.18.9-arch1-1/
# mount -t tmpfs rootfs /new_root/
# mkdir /new_root/usr
# mount -t virtiofs myfs /new_root/usr/
# umount /usr/lib/modules/5.18.9-arch1-1/
# cd new_root/
# mkdir run tmp var opt srv etc boot dev sys root proc
# ln -s usr/lib lib64
# ln -s usr/bin usr/sbin usr/lib .
# ln -s ../run var/run
# exec env -i TERM=$TERM /usr/bin/switch_root /new_root/ /usr/bin/init
