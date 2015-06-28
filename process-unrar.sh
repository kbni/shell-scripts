#!/bin/bash
# Script: process-unrar.sh
# Author: Alex Wilson <alex@kbni.net>
#   Loops over files in proc_dir and unrars completed downloads
#   Throw in crontab to run every minute (or run inside screen)

temp_dir="/mnt/raid5/store1/temp"
proc_dir="/mnt/raid5/store1/processing"

trap "rm -f /tmp/process_unrar.lock" SIGINT SIGTERM
if [ -e /tmp/process_unrar.lock ]; then
	exit 0 
else
	touch /tmp/process_unrar.lock
	find "$proc_dir" | grep -E '\.(r00?1|rar)$' | while read line; do
		echo "line: $line"
		dir=$(dirname "$line")
		dir_bn=$(basename "$line")
		file=$(basename "$line")
		temp="${temp_dir}/unrar-${dir_bn}-${file}"
		ls "$dir"/*.lftp-pget-status &>/dev/null && continue # if still downloading - skip
		ls "$temp" &>/dev/null && continue # if temp directory already exists, we already won - skip
		mkdir "$temp" || echo "Unable to create directory: $temp" > /dev/stderr
		cd "$temp" || exit 1
		if unrar -y -o- x "$line"; then
			echo "Extracted $line"
			mv -v "$temp"/* "$dir"/
		else
			rm -rf "$temp"/*
		fi
		rm -rf "$temp"/*
	done
fi

rm -f /tmp/process_unrar.lock
trap - SIGINT SIGTERM
exit 0
