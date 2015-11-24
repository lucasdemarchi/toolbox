# -*- coding: utf-8 -*-

import os
import os.path
import re

from .distro import Distro
from .toolbox import sh, sh_out, write_file


class DistroArch(Distro):
    pkgs = None

    def __init__(self):
        self.name = 'arch'
        self.long_name = 'Archlinux'
        self.cmdline = 'console=ttyS0,115200 console=tty0 rw quiet'

    def update_database(self):
        sh(['pacman', '-Sy'])

    def abspath(self, *args):
        return os.path.join(self.rootfs, *args)

    def bootstrap(self):
        s = sh_out(['pacman', '-Sg', 'base'])
        # Turn lines with 'base <pkg>' into a list with <pkg> entries
        pkgs = [x.split(' ')[1].strip() for x in s.splitlines() if len(x) > 1]

        pkg_remove = ['^linux$',
                      '^mdadm',
                      '^lvm2',
                      '^cryptsetup',
                      '^device-mapper',
                      '^xfsprogs',
                      '^reiserfsprogs',
                      '^jfsutils',
                      '^man-pages',
                      '^man-db',
                      '^pcmciautils',
                      '^inetutils',
                      '^dhcpcd',
                      '^netctl',
                      '^s-nail'
                      ]
        pkg_remove_combined = "(" + ")|(".join(pkg_remove) + ")"
        pkgs = list(filter(lambda x: not re.match(pkg_remove_combined, x), pkgs))

        self.pkgs = pkgs
        sh(['pacstrap', '-c', self.rootfs] + pkgs)

    def bootstrap_phase2(self):
        self.pkgs_phase2 = ['mkinitcpio', 'bash-completion', 'openssh']
        sh(['pacman', '--root', self.rootfs, '--noconfirm', '-S'] + self.pkgs_phase2)
        write_file(self.abspath('etc/fstab'),
                   'ROOT   /   auto    rw,relatime,data=ordered    0 0')

    def setup_locale(self):
        # TODO: add option for locale
        write_file(self.abspath('etc/locale.gen'), 'en_US.UTF-8 UTF-8')
        sh(['chroot', self.rootfs, 'locale-gen'])

    def install_bootloader(self):
        sh(['chroot', self.rootfs, 'bootctl', 'install', '--no-variables'])
        os.makedirs(self.abspath('boot/loader/entries'), exist_ok=True)
        write_file(self.abspath('boot/loader/entries/arch.conf'),
                   """title    Arch Linux
options  {cmdline}
linux    /vmlinuz-linux
initrd   /initramfs-linux.img""".format(cmdline=self.cmdline))

        write_file(self.abspath('boot/loader/entries/arch-fallback.conf'),
                   """title    Arch Linux Fallback Initrd
options  {cmdline}
linux    /vmlinuz-linux
initrd   /initramfs-linux.img""".format(cmdline=self.cmdline))

        write_file(self.abspath('boot/loader/loader.conf'),
                   """timeout 1
default arch-fallback""")

    def install_kernel(self):
        sh(['pacman', '--root', self.rootfs, '--noconfirm', '-S', 'linux'])

    def customize_image(self):
        # default to systemd
        sh(['systemctl', '--root', self.rootfs, 'set-default', 'multi-user.target'])

        # enable serial
        sh(['systemctl', '--root', self.rootfs, 'enable', 'serial-getty@ttyS0.service'])

        # enable ssh
        sh(['systemctl', '--root', self.rootfs, 'enable', 'sshd.socket'])

    def setup_network(self):
        # setup networkd
        sh(['systemctl', '--root', self.rootfs, 'enable', 'systemd-networkd.service'])
        sh(['systemctl', '--root', self.rootfs, 'enable', 'systemd-resolved.service'])

        try:
            os.remove(self.abspath('etc/resolv.conf'))
        except FileNotFoundError:
            pass
        os.symlink('/run/systemd/resolve/resolv.conf', self.abspath('etc/resolv.conf'))

        os.makedirs(self.abspath('usr/lib/systemd/network'), exist_ok=True)
        write_file(self.abspath('usr/lib/systemd/network/ether.network'),
                   """[Match]
Name=en*

[Network]
DHCP=yes""")
