#!/bin/bash
set -u

NEWROOT=$(mktemp -d)
FIFO=$(mktemp -u)
IMAGE="$1"

setup_child() {
    childpid="$(cat $FIFO)"
    subuids="$(grep "$USER" < /etc/subuid)"
    subgids="$(grep "$USER" < /etc/subgid)"
    newuidmap "$childpid" 0 $UID 1 \
        1 "$(cut -d: -f2 <<< $subuids)" "$(cut -d: -f3 <<< $subuids)"
    # FIXME handle case where $GROUPS contains multiple values
    newgidmap "$childpid" 0 $GROUPS 1 \
        1 "$(cut -d: -f2 <<< $subgids)" "$(cut -d: -f3 <<< $subgids)"
    echo done > $FIFO
}

cat > "${NEWROOT}"/init << EOF
#!/bin/bash
echo \$\$ > $FIFO
cat $FIFO > /dev/null
mount -t tmpfs sandboxroot "${NEWROOT}"

#mkdir -p "${NEWROOT}"/var/lib/pacman
mkdir -m 0755 -p "${NEWROOT}"/var/{cache/pacman/pkg,lib/pacman,log} \
    "${NEWROOT}"/{dev,run,etc/pacman.d} \
    "${NEWROOT}"/etc/pacman.d/hooks
mkdir -m 1777 -p "${NEWROOT}"/tmp
mkdir -m 0555 -p "${NEWROOT}"/{sys,proc}

mount -t tmpfs tmp "${NEWROOT}"/tmp
mount -o rbind,ro,nodev,nousid,noexec /sys "${NEWROOT}"/sys
mount -o rbind,ro,nodev,nousid,noexec /run "${NEWROOT}"/run

mount -t tmpfs udev "${NEWROOT}"/dev
ln -s /proc/self/fd/0 "${NEWROOT}"/dev/stdin
ln -s /proc/self/fd/1 "${NEWROOT}"/dev/stdout
ln -s /proc/self/fd/2 "${NEWROOT}"/dev/stderr
for dev in null full urandom tty
do
    touch "${NEWROOT}"/dev/"\${dev}"
    mount --bind /dev/"\${dev}" "${NEWROOT}"/dev/"\${dev}"
done

#cat > "${NEWROOT}"/install.sh << EOFEOF
##!/bin/sh
#mount -t proc proc "${NEWROOT}"/proc
#packages="base linux"
#pacman -r "${NEWROOT}" --noconfirm --hookdir "${NEWROOT}"/etc/pacman.d/hooks -Sy base linux
#EOFEOF
#chmod +x "${NEWROOT}"/install.sh
#unshare --pid --fork "${NEWROOT}"/install.sh

mkdir -m 0755 -p "${NEWROOT}"/var/lib/pacman/sync
cp /var/lib/pacman/sync/*.db "${NEWROOT}"/var/lib/pacman/sync

unshare --pid --fork /bin/bash << EOFEOF
mount -t proc proc "${NEWROOT}"/proc
packages="base linux"
pacman -r "${NEWROOT}" --noconfirm --hookdir "${NEWROOT}"/etc/pacman.d/hooks -S \\\$packages
EOFEOF

umount -l dev sys proc run tmp
blksize=512
start=2048
offset=\$((blksize*start))
partsize=10240
#image="/tmp/img.img"
truncate -s \$((partsize + offset/1024/1024))MiB "$IMAGE"
sfdisk "$IMAGE" <<< "type=83, start=\${start}, size=\${partsize}MiB"
mke2fs -E offset=\$offset -d "${NEWROOT}" "$IMAGE" "\${partsize}M"

cd "${NEWROOT}"
bash -i
EOF
chmod +x "${NEWROOT}"/init

mkfifo $FIFO
setup_child &
unshare --cgroup --ipc --uts --mount --user --keep-caps "${NEWROOT}"/init

rm "${NEWROOT}"/init
rmdir "${NEWROOT}"
rm "$FIFO"
