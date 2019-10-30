#!/bin/bash

display_controller_class="0300"
# assume we have only one for now
read dev xxx <<<$(lspci -d ::$display_controller_class)
sysdev=/sys/bus/pci/devices/0000:$dev/power/control

echo -n auto > ${sysdev}
echo -n "0000:$dev" > /sys/bus/pci/drivers/i915/unbind
modprobe -r i915
