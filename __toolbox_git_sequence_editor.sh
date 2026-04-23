#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later

set -euo pipefail

if [[ -v TOOLBOX_GIT_SEQUENCER_PREPEND ]]; then
	sed -i "1i $TOOLBOX_GIT_SEQUENCER_PREPEND" "$1"
fi

if [[ -v TOOLBOX_GIT_SEQUENCER_APPEND ]]; then
	sed -i "0,/^$/s/^$/$TOOLBOX_GIT_SEQUENCER_APPEND/" "$1"
fi

if [[ -v TOOLBOX_GIT_SEQUENCER_INTERACTIVE ]]; then
	editor="$(git var GIT_EDITOR)"
	exec sh -c "$editor $1"
fi
