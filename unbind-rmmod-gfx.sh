#!/bin/bash

set -e

vga="0300"
display="0380"
pci_vendor="8086"

# pass "xe" as param to unbind/rmmod xe
driver=${1:-i915}

while read -r pci_slot class devid xxx; do
	sysdev=/sys/bus/pci/devices/0000:$pci_slot/power/control

	echo "Unbinding /sys/bus/pci/devices/0000:$pci_slot ($devid)"
	echo -n auto > ${sysdev}

	if ! echo -n "0000:$pci_slot" > /sys/bus/pci/drivers/$driver/unbind; then
		d="$(basename $(readlink -f /sys/bus/pci/devices/0000:$pci_slot/driver))" || true
		if [ $driver == $d ]; then
			echo "ERROR: could not unbind $d driver" > /dev/stderr
		fi
	fi
done <<<$(lspci -d ${pci_vendor}::${display} -n; lspci -d ${pci_vendor}::${vga} -n )

modprobe -r $driver
