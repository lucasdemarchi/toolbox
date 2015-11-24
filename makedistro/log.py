# -*- coding: utf-8 -*-

from __future__ import print_function


class Log(object):
    COLOR_RED = "\033[31m"
    COLOR_LIGHTBLUE = "\033[34;1m"
    COLOR_YELLOW = "\033[33;1m"
    COLOR_ORANGE = "\033[0;33m"
    COLOR_WHITE = "\033[37;1m"
    COLOR_RESET = "\033[0m"

    def err(self, s, *args, **kwargs):
        print('{}### {}{}'.format(self.COLOR_RED, s, self.COLOR_RESET), *args, **kwargs)

    def warn(self, s, *args, **kwargs):
        print('{}### {}{}'.format(self.COLOR_ORANGE, s, self.COLOR_RESET), *args, **kwargs)

    def notice(self, s, *args, **kwargs):
        print('{}### {}{}'.format(self.COLOR_YELLOW, s, self.COLOR_RESET), *args, **kwargs)

    def info(self, s, *args, **kwargs):
        print('{}### {}{}'.format(self.COLOR_WHITE, s, self.COLOR_RESET), *args, **kwargs)
