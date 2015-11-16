# -*- coding: utf-8 -*-

from __future__ import print_function

import argparse
import os
import os.path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

from .distro_arch import DistroArch
from .distro_fedora import DistroFedora
from .log import Log
from .toolbox import sh, sh_out, sh_pipe

device = None

distro_manager = None
# TODO: add option for distros that make sense
arch = 'x86_64'

log = Log()


def isblk(p):
    try:
        mode = os.stat(p).st_mode
        return stat.S_ISBLK(mode)
    except FileNotFoundError:
        return False


def cleanup():
    try:
        if distro_manager and distro_manager.part_mount['root']:
            rootfs = distro_manager.part_mount['root']
            sh(['umount', '-R', rootfs], ignore_errors=True)
            shutil.rmtree(rootfs, ignore_errors=True)

        if device and device.startswith('/dev/loop'):
            sh(['losetup', '-d', device])
    except subprocess.CalledProcessError:
        # ignore exceptions on cleanup
        pass


def sig_handler(signum, frame):
    cleanup()
    log.err('FAILED TO GENERATE IMAGE', file=sys.stderr)


def setup_device(image):
    global device

    log.info('setting up device for {}'.format(image))

    if image.startswith('/dev/') and not isblk(image):
        log.err('Couldn\'t find block device ' + image, file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(image) or os.path.isfile(image):
        # truncate file to 4G
        sh(['dd', 'if=/dev/null', 'of=' + image, 'bs=1M', 'seek=4096'])
        device = sh_out(['losetup', '-f', '--show', image]).strip()
    else:
        device = image

    mode = os.stat(device).st_mode
    if not stat.S_ISBLK(mode):
        s = '{} is not a block device'.format(device)
        log.err(s)
        raise ValueError(s)


def wipe_device():
    global device

    log.info('erasing {}'.format(device))

    sh(['wipefs', '-a', device])
    sh(['dd', 'if=/dev/zero', 'of=' + device, 'bs=1M', 'count=4'])


class DistroManager(object):
    DISTROS = []
    part_device = {'boot': None, 'root': None}
    part_mount = {'boot': None, 'root': None}

    def __init__(self):
        self.DISTROS += [DistroArch()]
        self.DISTROS += [DistroFedora()]

    def print_distros(self):
        for d in self.DISTROS:
            print('{}:\t{}'.format(d.name, d.long_name))

    def create_partitions(self):
        global device, arch

        log.info('Creating partitions')

        if arch == 'x86_64':
            root_guid = '4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709'
        elif arch == 'x86':
            root_guid = '44479540-F297-41B2-9AF7-D131D5F0458A'
        else:
            root_guid = '0FC63DAF-8483-4772-8E79-3D69D8477DE4'

        sh_pipe(['sfdisk', device],
                """label: gpt
size=511MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=ESP, bootable
name=System, type={root_guid}, name=System
""".format(root_guid=root_guid))

        # point self.part_device to right partitions
        try:
            self.part_device['boot'] = next(
                (p for p in [device + '1', device + 'p1'] if isblk(p)))
            self.part_device['root'] = next(
                (p for p in [device + '2', device + 'p2'] if isblk(p)))
        except StopIteration as err:
            log.err('Could not get boot and root partitions from {}'.format(device))
            raise

        # format partitions
        sh(['wipefs', '-a', self.part_device['boot']])
        sh(['mkfs.vfat', '-n', 'ESP', '-F32', self.part_device['boot']])

        sh(['wipefs', '-a', self.part_device['root']])
        sh(['mkfs.ext4', '-L', 'System', self.part_device['root']])

    def mount_partitions(self):
        log.info('mounting partitions')

        self.part_mount['root'] = tempfile.mkdtemp(prefix='make-distro-')
        self.part_mount['boot'] = os.path.join(self.part_mount['root'], 'boot')

        sh(['mount', self.part_device['root'], self.part_mount['root']])
        os.makedirs(self.part_mount['boot'])
        sh(['mount', self.part_device['boot'], self.part_mount['boot']])

    def mount_kernel_partitions(self):
        sh(['mount', '--bind', '/proc', self.part_mount['root'] + '/proc'])
        sh(['mount', '--bind', '/dev', self.part_mount['root'] + '/dev'])
        sh(['mount', '--bind', '/sys', self.part_mount['root'] + '/sys'])

        try:
            sh(['findmnt',  self.part_mount['root'] + '/boot'])
        except:
            sh(['mount', self.part_mount['boot'], self.part_mount['boot']])

        sh(['mount', '-t', 'tmpfs', 'none', self.part_mount['root'] + '/run'])

    def run(self, distro, image):
        # from now on we always cleanup ourselves after finishing
        signal.signal(signal.SIGINT, sig_handler)

        setup_device(image)
        wipe_device()

        self.create_partitions()
        self.mount_partitions()

        d = next(d for d in self.DISTROS if d.name == distro)

        # set rootfs location and start installing
        d.rootfs = self.part_mount['root']

        log.info('Updating distro database')
        d.update_database()

        log.info('Bootstrap distro \'{}\''.format(d.long_name))
        d.bootstrap()

        log.info('Mounting kernel partitions')
        self.mount_kernel_partitions()

        log.info('Bootstrap distro (phase 2) \'{}\''.format(d.long_name))
        d.bootstrap_phase2()

        log.info('Setting up locale')
        d.setup_locale()

        log.info('Installing bootloader')
        d.install_bootloader()

        log.info('Installing kernel')
        d.install_kernel()

        log.info('Customizing image')
        d.customize_image()

        log.info('Setting up network')
        d.setup_network()

        # finish installation
        log.info('Finishing installation')
        os.sync()

        uid = os.getenv('SUDO_UID', '')
        guid = os.getenv('SUDO_GUID', '')
        if os.path.isfile(image) and uid != '':
            uid = int(uid)
            if guid == '':
                guid = None
            else:
                guid = int(guid)
            shutil.chown(image, uid, guid)

        return 0


def main():
    global device, distro_manager

    mgr = DistroManager()
    distro_manager = mgr

    parser = argparse.ArgumentParser(description='Create a rootfs for distros')
    parser.add_argument('-l', '--list-distros', action='store_true',
                        help='list available distros and exit')
    parser.add_argument('-d', '--distro', choices=[n.name for n in mgr.DISTROS],
                        help='install distro')

    parser.add_argument('image', action='store', nargs='?', default=None,
                        help='file or block device in which rootfs is generated')

    args = parser.parse_args()

    if args.list_distros:
        mgr.print_distros()
        sys.exit(0)

    if not args.image:
        print('Missing image argument', file=sys.stderr)
        parser.print_help(file=sys.stderr)
        sys.exit(1)

    try:
        mgr.run(args.distro, args.image)
    except Exception as err:
        print(err)
        sig_handler(signal.SIGINT, None)
        sys.exit(1)

    log.info('Image generated succesfully: {}'.format(args.image))
    cleanup()
