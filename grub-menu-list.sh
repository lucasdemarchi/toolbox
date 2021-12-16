#!/bin/bash

set -eu

cols=$(tput cols)
saved_entry=-1
next_entry=-1

eval $(grub-editenv list)

echo "  *: default entry"
echo "-> : next entry"
echo

awk -v cols=$cols -v saved_entry=$saved_entry -v next_entry=$next_entry '
BEGIN {
	# reserve space for tab
	cols -= 8
	count = 0
}

/menuentry/ && /class/ {
	len = length($0)
	if (len >= cols)
		line = substr($0, 1, cols - 3) "..."
	else
		line = $0

	if (count == saved_entry) {
		if (saved_entry == next_entry)
			prefix = "->*"
		else
			prefix = "  *"
	} else if (count == next_entry) {
		prefix = "-> "
	} else {
		prefix = "   "
	}

	print prefix count ")\t" line
	count++
}' /boot/grub/grub.cfg
