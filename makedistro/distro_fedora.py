# -*- coding: utf-8 -*-

from .distro import Distro


class DistroFedora(Distro):

    def __init__(self):
        self.name = 'fedora'
        self.long_name = 'Fedora (WIP)'
