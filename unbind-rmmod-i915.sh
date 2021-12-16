#!/bin/bash

set -e

vga="0300"
display="0380"
pci_vendor="8086"

while read -r pci_slot class devid xxx; do
	sysdev=/sys/bus/pci/devices/0000:$pci_slot/power/control

	echo "Unbinding /sys/bus/pci/devices/0000:$pci_slot ($devid)"
	echo -n auto > ${sysdev}
	if ! echo -n "0000:$pci_slot" > /sys/bus/pci/drivers/i915/unbind; then
		driver="$(basename $(readlink -f /sys/bus/pci/devices/0000:$pci_slot/driver))" || true
		if [ $driver == i915 ]; then
			echo "ERROR: could not unbind driver" > /dev/stderr
		fi
	fi
done <<<$(lspci -d ${pci_vendor}::${display} -n; lspci -d ${pci_vendor}::${vga} -n )

modprobe -r i915
