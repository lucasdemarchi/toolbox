#!/bin/bash

set -eu

DEST=${DEST:-gta@dut}
MODULE=${MODULE:-i915}

if [ ! -z ${1+x} ]; then
	m=$1
elif [ -f build64/drivers/gpu/drm/$MODULE/$MODULE.ko ]; then
	m=build64/drivers/gpu/drm/$MODULE/$MODULE.ko
elif [ -f drivers/gpu/drm/$MODULE/$MODULE.ko ]; then
	m=drivers/gpu/drm/$MODULE/$MODULE.ko
fi


SHA=$(sha256sum ${m} | cut -d' ' -f1)
rsync ${m} ${DEST}:$MODULE.ko
ssh -q -t ${DEST} <<:
	sudo cp $MODULE.ko \$(modinfo -n $MODULE)
	echo "kernel: \$(uname -r)"
	echo "DUT:    \$(hostname)"
	echo $SHA \$(modinfo -n $MODULE) | sha256sum --check
	sync
:
