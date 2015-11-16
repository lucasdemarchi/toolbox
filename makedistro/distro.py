# -*- coding: utf-8 -*-


class Distro(object):
    rootfs = None
    long_name = None
    name = None

    def list_hooks(self):
        """List available hooks of this distro"""
        pass

    def update_database(self):
        pass

    def bootstrap(self):
        """Bootstrap distro on rootfs, which is already mounted"""
        pass

    def bootstrap_phase2(self):
        """Install additional packages that are not possible to be installed
           in the initial bootstrap without all (kernel) filesystems mounted"""
        pass

    def setup_locale(self):
        """Generate locale files"""
        pass

    def install_bootloader(self):
        """Install bootloader following the BootloaderSpec"""
        pass

    def install_kernel(self):
        pass

    def customize_image(self):
        pass

    def setup_network(self):
        pass
