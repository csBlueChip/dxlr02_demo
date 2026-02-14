#!/bin/bash -e

CONF=$1
MAC=$2
DEV=$3

[[ -z $CONF ]] && {
	echo "! Use $0 <config.file> <mac,addr> <device>"
	exit 255
}

#+=============================================================================
lines=()
reply=

txrx() {
	local  cmd=$1
	local  mode=$2

	local  tmol=0.5  # timeout between lines
	local  tmoh=1.5  # timeout hexdump

	local  l
	local  line

	printf ">\e[0;1;32m%-13s\e[0m" "${cmd}"

	# SEND THE AT COMMAND
	printf "%s\r\n" "${cmd}" > ${DEV}

	# catch the reply
	[[ ${mode} == hex ]] && {
		# hex(dump) mode clearly shows the line terminators
		echo ""
		reply=$(timeout "${tmoh}" cat < "${DEV}" | tee >(stdbuf -o0 hexdump -C >&2))

	} || {
		lines=()
		while IFS= read -r -t ${tmol} line ; do
			line="${line//$'\r'/}"
			lines+=("$line")
		done < "$DEV"

		# dump the result (help is unique)
		[[ "${cmd}" == "AT+HELP" ]] && {
			echo "" ; for l in "${lines[@]}" ; do  echo "$l" ; done
		} || {
			for l in "${lines[@]}" ; do  echo -n ".. $l " ; done ; echo ""
		}
	}
}

#++============================================================================
# map command list to array
mapfile -t LIST < <(\grep -v '^#' ${CONF} | grep -v '^[[:space:]]*$')

# this really is a quick'n'dirty solution...
# the first two lines of the config file are the DEV and STTY variables
[[ ${LIST[0]} == DEV=* ]] && [[ ${LIST[1]} == STTY=* ]] || {
	echo "! Config file error"
	exit 254
}
[[ -z ${DEV} ]] && eval "${LIST[0]}"
eval "${LIST[1]}"

# debug
echo "# Found $((${#LIST[@]} -2)) commands"
#for ((i = 0;  i < ${#LIST[@]};  i++)) ; do
#	echo "$i : ${LIST[$i]}"
#done

# make sure we have read/write to the port
[[ ! -r ${DEV} ]] || [[ ! -w ${DEV} ]] && {
	echo "! ${DEV} not visible"
	ls -l /dev/tty[^0-9]*
	groups
	exit 250
}

# set tty baud (etc)
echo "# Config" ${DEV} ${STTY}
stty -F ${DEV} ${STTY} || {
	echo "! Fail. Retry or power-cycle"
	exit 251
}

# loop through all commands
for ((l = 2;  l < ${#LIST[@]};  l++)) ; do
	cmd="${LIST[$l]}"

	# NOT "+++" - echo results as text
	[[ "${cmd}" != "+++" ]] && {

		# override MAC address (with CLI value)
		[[ ${cmd} == AT+MAC?* ]] && [[ -n ${MAC} ]] && {
			echo -en "     \e[0;1;35mv- ${cmd} -> "
			cmd="AT+MAC${MAC}"
			echo -e "${cmd}\e[0m"
		}

		# abort command if it fails 5 times
		for ((i = 0;  i < 5;  i++)) ; do
			printf "%02d:%d" $((l-1)) $((i+1))
			txrx "${cmd}"
			[[ ${lines[0]} != ERROR* ]] && break 1
		done
		(( i == 5 )) && echo -e "    \e[0;1;31m ^- ABORTED : ${cmd} \e[0m" || true

	# IS "+++" - show results as hex (mostly so you get to see the line endings)
	} || {
		printf "%02d:%d" $((l-1)) 0
		txrx ${cmd} hex

		[[ "${reply:0:7}" == "Exit AT"  ]] && {
			echo "! Serial port ENabled" ; exit 253
		}

		[[ "${reply:0:8}" == "Entry AT" ]] || {
			echo "! AT Access denied" ; exit 252
		}

		echo "# AT Access granted"
	}
done

echo "# Done"
exit 0
