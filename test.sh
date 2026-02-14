#!/bin/bash

SESSID="dxlr02"

CFG1="$1"
CFG2="$2"

FLG="$3"

#------------------------------------------------------------------------------
# cli sanity check
#
[[ -z $CFG2 ]] && {
	echo "Use: $0 <device1.config> <device2.config> [-skip]"
	echo "  Device config can take a while, and survives a reboot; so it only"
	echo "  needs to be done once ... -skip skips the config phase, but"
	echo "  the config files are still required for Serial Port setup."
	exit 1
}

#------------------------------------------------------------------------------
# required tools check
#
type tmux >/dev/null 2>&1 && type minicom >/dev/null 2>&1 || {
	echo "sudo apt install tmux picocom"
	exit 1
}

#------------------------------------------------------------------------------
# sanity check - kill old session
#
>/dev/null 2>&1 tmux kill-session -t ${SESSID} || true

#------------------------------------------------------------------------------
# extract the details we will need from the config files
#
DEV1="$(grep '^DEV=' ${CFG1} | cut -d\' -f2)"
STTY1="$(grep '^STTY=' ${CFG1} | cut -d\' -f2)"
BAUD1=$(cut -d\  -f1 <<<${STTY1})

DEV2="$(grep '^DEV=' ${CFG2} | cut -d\' -f2)"
STTY2="$(grep '^STTY=' ${CFG2} | cut -d\' -f2)"
BAUD2=$(cut -d\  -f1 <<<${STTY2})

echo -e "# Using:  ${CFG1}\t-> "${DEV1} @ ${STTY1}
echo -e "          ${CFG2}\t-> "${DEV2} @ ${STTY2}

#------------------------------------------------------------------------------
# check the devices are visible
#
err=0
[[ ! -r ${DEV1} ]] || [[ ! -w ${DEV1} ]] && {
	echo "! ${DEV1} not visible"
	err=1
}
[[ ! -r ${DEV2} ]] || [[ ! -w ${DEV2} ]] && {
	echo "! ${DEV2} not visible"
	err=1
}
((err)) && {
	echo "--- Device list ---"
	ls -l /dev/tty[^0-9]*

	echo "--- Your group memberships ---"
	groups

	exit 250
}

echo "" ; read -p "Power cycle the devices. Then press <CR> to continue..."

#------------------------------------------------------------------------------
# run the config scripts
#
[[ $FLG != -skip ]] && {  # NOT skip
	echo "--------------------------------------------"
	./dxlr02.sh  ${CFG1}

	echo "--------------------------------------------"
	./dxlr02.sh  ${CFG2}
}

#------------------------------------------------------------------------------
cat <<EOF

# What you type in one pane will be transmitted to the other pane

# Keys while in tmux:
    ^B  <-  : select the left pane
    ^B  ->  : select the right pane
    ^B  d   : detach from tmux

Using tmux (or other NOHUP session manager) we can "detach" and
  leave the session running in the background.
Then re-attach at any time and see what has been happening.

# Commands when detached:
    tmux ls                      : list all active tmux sessions
    tmux attach       -t ${SESSID}  : re-attach to the lora session
    tmux kill-session -t ${SESSID}  : kill the lora session

***
These devices are really flaky ... If the sessions do not open properly:
  o quit with ^B d
  o restart with: $0 $CFG1 $CFG2 -skip
...Give it 4 or 5 goes before you give up!
***

EOF

read -p "Press <CR> to continue..." ; echo ""

#------------------------------------------------------------------------------
# o Start a detached session with the first pane
# o Now split horizontally and run second pane
# o Arrange panes evenly
# o Attach
#
# TODO: extract parity and stopbits from TTY
#

set -x
tmux new-session  -d -s ${SESSID} "picocom --baud ${BAUD1} --parity n --stopbits 1 ${DEV1}"
tmux split-window -h -t ${SESSID} "picocom --baud ${BAUD2} --parity n --stopbits 1 ${DEV2}"
tmux select-layout   -t ${SESSID} even-horizontal
tmux attach          -t ${SESSID}
