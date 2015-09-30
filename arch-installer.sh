#!/bin/bash
#
# Copyright 2014 Kay Sievers
# Copyright 2015 Intel Corporation. All rights reserved.
#
# This script is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 2.1 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with systemd; If not, see <http://www.gnu.org/licenses/>.
#
# Based on Minimal Fedora Installer by Kay Sievers
# - standalone, fully bootable USB stick/mmc
# - text mode
# - UEFI-only
#
# Erase and reformat an entire disk:
#   $ ./arch-installer.sh /dev/sdc
#
# QEMU needs a UEFI firmware:
#   sudo qemu-system-x86_64 -machine accel=kvm -m 256 -bios /usr/share/qemu/bios-ovmf.bin /dev/sdc

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

usage() {
    echo "
Usage: $(basename $0) [OPTIONS] <disk or image file to re-format>

OPTIONS
    -x             comma-separated list of hooks to run as last step,
                   before unmounting directories. The hook can get the
                   rootfs location by reading the ROOTFS environment
                   variable. Each item can be a command or a path to a
                   file or directory. If a command, the directory
                   arch-installer-hooks is prepended to PATH environment
                   variable. In case of a directory it will be executed
                   by sorting the files alphabetically. This option may
                   be passed multiple times.

    -l             Force installation, not checking if network is available
                   using local pacman database and cache. This relies on all
                   packages being already present in host cache. If they
                   aren't the installer will fail later.

Examples:
    # using built-in hook \"overlay\" to append contents of files under
    # path/to/overlay to files under ROOTFS
    arch-installer -x \"overlay-append path/to/overlay\" /dev/sdx1

    # copying current system's pacman mirrorlist to the fresh new system
    arch-installer -x \"cp /etc/pacman.d/mirrorlist \\\$ROOTFS/etc/pacman.d/\" /dev/sdx1
" 1>&$1;
}

OPT_LOCAL=""

hooks=()

execute_hook() {
    export ROOTFS
    local hook=$1
    if [[ -f "$hook" ]]; then
        if [[ ! -x "$hook" ]]; then
            echo "Ignoring non-executable hook: \"$hook\"" >&2
            return
        fi
        bash "$hook"
    else
        bash -c "$hook"
    fi
}

args=0
while getopts "x:lh" o; do
    case "${o}" in
        x)
            IFS=, read -ra arg_hooks <<<"${OPTARG}"
            hooks+=("${arg_hooks[@]}")
            args=$[$args + 2] ;;
        l)
            OPT_LOCAL="-C $SCRIPT_DIR/arch-installer-files/pacman.conf"
            args=$[$args + 1] ;;
        h) usage 1; exit 0;;
        \?) usage 2; exit 1;;
    esac
done
shift $args

if [ -z "$1" ]; then
    usage 2
    exit 1
fi
echo $1

# make sure we have a current package database and working
# network connection
[ -n "$OPT_LOCAL" ] || pacman -Sy || {
    echo "Cannot update package database - is the network up and running?" >&2
    exit 1
}

trap '
    ret=$?;
    set +e;
    if [[ $ROOT ]]; then
        for i in /proc /run /boot /dev /sys ""; do
            umount /run/installer-$ROOT/system$i
        done
        rm -rf /run/installer-$ROOT
    fi
    [[ $DEV == /dev/loop* ]] && losetup -d $DEV
    if [[ $ret -ne 0 ]]; then
        echo FAILED TO GENERATE IMAGE >&2
    fi
    exit $ret;
    ' EXIT

# clean up after ourselves no matter how we die.
trap 'exit 1;' SIGINT

if [[ ! -e "$1" ]] && [[ "$1" == /dev/* ]]; then
    echo "Couldn't find block device $1" >&2
    exit 1
fi

if [[ ! -e "$1" ]] || [[ -f "$1" ]]; then
    dd if=/dev/null of="$1" bs=1M seek=4096
    DEV=$(losetup -f --show "$1")
else
    DEV="$1"
fi

if [[ ! -b "$DEV" ]]; then
    echo "$1 is not a block device" >&2
    exit 1
fi

ROOT=${DEV##*/}

printf "\n### erasing /dev/$ROOT\n"
# get rid of all signatures
wipefs -a /dev/$ROOT
dd if=/dev/zero of=/dev/$ROOT bs=1M count=4

printf "\n### formatting EFI System Partition\n"
parted /dev/$ROOT --script "mklabel gpt" "mkpart ESP fat32 1MiB 511Mib" "set 1 boot on"

BOOT_PART=/dev/${ROOT}1
[[ -b /dev/${ROOT}p1 ]] && BOOT_PART=/dev/${ROOT}p1

wipefs -a $BOOT_PART
mkfs.vfat -n EFI -F32 $BOOT_PART

printf "\n### formatting System Partition\n"
parted /dev/$ROOT --script "mkpart System ext4 512Mib -1Mib"

case "x`uname -m`" in
        xx86_64)
                ROOT_UUID=4f68bce3-e8cd-4db1-96e7-fbcaf984b709
                ;;
        xi686|xi586|xi486|xi386)
                ROOT_UUID=44479540-f297-41b2-9af7-d131d5f0458a
                ;;
        *)
                ROOT_UUID=0fc63daf-8483-4772-8e79-3d69d8477de4
                ;;
esac

echo "t
2
$ROOT_UUID
w
y
q" | gdisk /dev/$ROOT

if test ${PIPESTATUS[1]} -ne 0; then
    echo "error paritioning disk" >&2
    exit 1
fi

SYSTEM_PART=/dev/${ROOT}2
[[ -b /dev/${ROOT}p2 ]] && SYSTEM_PART=/dev/${ROOT}p2

wipefs -a $SYSTEM_PART
# TODO: add options to select fs (and add proper packages)
mkfs.ext4 -L System $SYSTEM_PART

rm -rf /run/installer-$ROOT

ROOTFS="/run/installer-$ROOT/system"
#############################################################

echo "### installing Archlinux at /dev/$ROOT"

# mount System
mkdir -p $ROOTFS
mount $SYSTEM_PART $ROOTFS
# mount /boot
mkdir $ROOTFS/boot
mount $BOOT_PART $ROOTFS/boot

printf "\n### download and install base packages\n"
pacman -Sg base | cut -d ' ' -f 2 | \
    sed -e /^linux\$/d       \
        -e /^mdadm/d         \
        -e /^lvm2/d          \
        -e /^cryptsetup/d    \
        -e /^device-mapper/d \
        -e /^xfsprogs/d      \
        -e /^reiserfsprogs/d \
        -e /^jfsutils/d      \
        -e /^man-pages/d     \
        -e /^man-db/d        \
        -e /^pcmciautils/d   \
        -e /^inetutils/d     \
        -e /^dhcpcd/d        \
        -e /^netctl/d        \
        -e /^s-nail/d        \
    | pacstrap -c $OPT_LOCAL $ROOTFS -

# mount kernel filesystems and /boot again
mount --bind /proc $ROOTFS/proc
mount --bind /dev $ROOTFS/dev
mount --bind /sys $ROOTFS/sys
if ! findmnt $ROOTFS/boot >/dev/null; then
    mount $BOOT_PART $ROOTFS/boot
fi
mount -t tmpfs none $ROOTFS/run

# install additional packages
pacman --root=$ROOTFS --noconfirm -S \
    mkinitcpio      \
    bash-completion \
    openssh

# at bootup mount / read-writable
cat > $ROOTFS/etc/fstab <<EOF
ROOT       /               auto rw,relatime,data=ordered           0 0
EOF

# default locale to en_US utf-8.
# TODO: add options for locale
echo "en_US.UTF-8 UTF-8" >> $ROOTFS/etc/locale.gen
chroot $ROOTFS locale-gen

printf "\n### install boot loader\n"
chroot $ROOTFS bootctl install --no-variables

mkdir -p $ROOTFS/boot/loader/entries
read MACHINE_ID < $ROOTFS/etc/machine-id

CMDLINE="console=ttyS0,115200 console=tty0 rw quiet"

# TODO: Change Arch to use kernel-install
cat > $ROOTFS/boot/loader/entries/arch.conf <<EOF
title      Arch Linux
options    $CMDLINE
linux      /vmlinuz-linux
initrd     /initramfs-linux.img
EOF

cat > $ROOTFS/boot/loader/entries/arch-fallback.conf <<EOF
title      Arch Linux Fallback Initrd
options    $CMDLINE
linux      /vmlinuz-linux
initrd     /initramfs-linux-fallback.img
EOF

cat > $ROOTFS/boot/loader/loader.conf <<EOF
timeout 1
# enable below when using custom kernel
# default $MACHINE_ID-*
default arch-fallback
EOF

# configure for custom kernels
mkdir -p $ROOTFS/etc/kernel/install.d
cat > $ROOTFS/etc/kernel/cmdline <<EOF
$CMDLINE
EOF
sed -i 's/^HOOKS.*/HOOKS="systemd autodetect modconf block filesystems fsck"/' \
    $ROOTFS/etc/mkinitcpio.conf

printf "\n### install kernel\n"
pacman --root=$ROOTFS --noconfirm -S linux

printf "\n### customizing image\n"
# set default target
systemctl --root=$ROOTFS set-default multi-user.target
# serial
systemctl --root=$ROOTFS enable serial-getty@ttyS0.service
# ssh
systemctl --root=$ROOTFS enable sshd.socket

# networkd
systemctl --root=$ROOTFS enable systemd-networkd.service
systemctl --root=$ROOTFS enable systemd-resolved.service
ln -sf /run/systemd/resolve/resolv.conf $ROOTFS/etc/resolv.conf
# enable DHCP for all Ethernet interfaces
mkdir -p $ROOTFS/usr/lib/systemd/network
cat > $ROOTFS/usr/lib/systemd/network/ether.network <<EOF
[Match]
Name=en*

[Network]
DHCP=yes
EOF

for hook in "${hooks[@]}"; do
    if [ -d "$hook" ]; then
        for f in "$hook"/*; do
            execute_hook "$f"
        done
    elif [ -f "$hook" ]; then
        execute_hook "$hook"
    else
        # consider hook a command
        PATH=$SCRIPT_DIR/arch-installer-hooks:$PATH execute_hook "$hook"
    fi
done

sync

if [ -f "$1" -a -n "$SUDO_UID" ]; then
    chown $SUDO_UID:$SUDO_GID $1
fi

printf "\n### finished\n"
