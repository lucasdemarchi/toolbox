# -*- coding: utf-8 -*-

import subprocess
import sys

from subprocess import PIPE, STDOUT


def sh_out(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
    except subprocess.CalledProcessError as err:
        sys.stderr.write(err.output.decode('utf-8'))
        raise


def sh(cmd, **kwargs):
    try:
        stderr = subprocess.STDOUT
        if kwargs.get('ignore_errors', False):
            stderr = subprocess.DEVNULL
        return subprocess.check_call(cmd, stderr=stderr)
    except subprocess.CalledProcessError as err:
        if not kwargs.get('ignore_errors', False):
            # sys.stderr.write(err.output.decode('utf-8'))
            raise
        pass


def sh_pipe(cmd, inp):
    try:
        p = subprocess.Popen(cmd, stdout=PIPE, stdin=PIPE, stderr=STDOUT)
        return p.communicate(input=inp.encode('utf-8'))[0].decode('utf-8')
    except subprocess.CalledProcessError as err:
        sys.stderr.write(err.output.decode('utf-8'))
        raise


def write_file(path, s):
    with open(path, 'w') as f:
        f.write(s)


def read_file(path):
    with open(path, 'r') as f:
        return f.readlines()
