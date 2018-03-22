#!/bin/bash

echo -n auto > /sys/bus/pci/devices/0000\:00\:02.0/power/control
echo -n "0000:00:02.0" > /sys/bus/pci/drivers/i915/unbind
modprobe -r i915
