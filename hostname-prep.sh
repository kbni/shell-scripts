#!/bin/bash
# Script: hostname-prep.sh
# Author: Alex Wilson <alex@kbni.net>
#   Prepares a freshly booted Debian Linux system, generates new hostname
#   by combining a unique portion, hostname prefix and suffix. I use this
#   to run up test machines at home

uniq_portion=$(/sbin/ifconfig -a | grep eth0 | sed 's/.*HWaddr ..:..:..//; s/://g; s/ //g')
new_hostname_prefix="kbni-bne-"
new_domain_suffix="in.kbni.net"

prep_file="/usr/local/etc/hostname-prep-portion"

if [ "$1" = "" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	echo "$(basename "$0") - alex@kbni.net"
	echo "options:"
	echo "  -h --help  Display this message"
	echo "     --save  Store the unique string to ${prep_file}"
	echo "     --show  Show the unique string for this machine"
	echo "     --prep  Prepare this host (call via rc.local)"
	exit 1    
fi

if [ "$1" = "--show" ]; then
	uniq_portion_cmd="$(grep ^uniq_portion= "$0" | sed 's/uniq_portion=//; s/^..//; s/.$//')"
	echo "the unique string for this hostname is ${uniq_portion}"
	echo "generated by: ${uniq_portion_cmd}"
	
	if [ ! -f "$prep_file" ]; then
		echo "no unique string is stored, use --save"
		exit 0
	fi

	in_prep_file="$(cat "$prep_file" 2>&1)"

	if [ "$in_prep_file" = "$uniq_portion" ]; then
		echo "unique string is saved so this host cannot be hostname-prepped."
		exit 0
	else
		echo "unique string differs from saved string (${in_prep_file})."
		exit 0
	fi
fi

if [ "$1" = "--save" ]; then
	echo "${uniq_portion}" > "$prep_file"
	echo "saved ${uniq_portion} to ${prep_file}"
	exit 0
fi

if [ "$1" = "--prep" ]; then
	in_prep_file="$(cat "$prep_file")"
	if [ "$in_prep_file" = "$uniq_portion" ]; then
		echo "This is the master image (${uniq_portion}). We won't prep this."
		exit 0
	else
		if [ "$(hostname)" = "debian" ]; then
			new_hostname="${new_hostname_prefix}${uniq_portion}"
			new_fqdn="${new_hostname}.${new_domain_suffix}"
			echo "new fqdn: ${new_fqdn}"
			if [ $UID -gt 0 ]; then
				echo "Not root.. exiting"
				exit 1
			fi
			rm -fv /etc/ssh/ssh_host_*
			/usr/sbin/dpkg-reconfigure openssh-server
			echo "${new_hostname}" > /etc/hostname
			sed -i "s/debian/${new_fqdn} ${new_hostname}/" /etc/hosts
			rm -fv /root/.bash_history /home/*/.bash_history
			systemctl enable ssh
			rm -fv /etc/ssh/sshd_not_to_be_run
			/sbin/reboot
			exit 0
		else
			# hostname-prep doesn't need to do anything
			exit 0
		fi
	fi
fi

exit 1 # how did we get here?

