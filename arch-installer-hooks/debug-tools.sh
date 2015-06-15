#!/bin/bash

pacman --root=$ROOTFS --noconfirm -S \
    valgrind \
    strace
