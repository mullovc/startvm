#!/bin/bash
set -u

datadir="${XDG_DATA_DIR:-$HOME/.local/share}/startvm"
imagedir="$datadir/images"

NEWROOT=$(mktemp -d)
FIFO=$(mktemp -u)
IMAGE="$imagedir/${1:-base}.ext2"
PARTSIZE=10240M

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

mkdir -m 0755 -p "${NEWROOT}"/var/lib/pacman/sync
cp /var/lib/pacman/sync/*.db "${NEWROOT}"/var/lib/pacman/sync

# XXX do pacman-key --init/--populate instead?
# if there's a keyring on the host, copy it into the new root, unless it exists already
if [[ -d /etc/pacman.d/gnupg && ! -d ${NEWROOT}/etc/pacman.d/gnupg ]]; then
    cp -a /etc/pacman.d/gnupg "${NEWROOT}/etc/pacman.d/"
fi

unshare --pid --fork /bin/bash << EOFEOF
mount -t proc proc "${NEWROOT}"/proc
packages="base"
pacman -r "${NEWROOT}" --noconfirm --hookdir "${NEWROOT}"/etc/pacman.d/hooks -S \\\$packages
EOFEOF

# FIXME absolute path
cp -r baseconfig/* "${NEWROOT}"/
cp /etc/pacman.d/mirrorlist "${NEWROOT}"/etc/pacman.d/mirrorlist

umount -l dev sys proc run tmp

mke2fs -L vmroot -d "${NEWROOT}" "${IMAGE}" "${PARTSIZE}"
EOF
chmod +x "${NEWROOT}"/init

mkdir -p "$imagedir"

mkfifo $FIFO
setup_child &
unshare --cgroup --ipc --uts --mount --user --keep-caps "${NEWROOT}"/init

rm "${NEWROOT}"/init
rmdir "${NEWROOT}"
rm "$FIFO"
