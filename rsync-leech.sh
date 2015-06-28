#!/usr/bin/env bash
#
###############################################################################
## File: rsync-leech.sh - rsync tool for slurping directory from a server    ##
## Author: Alex Wilson <alex@kbni.net>                Updated: 2014-01-07    ##
##                                                                           ##
## Configure by updating the following variables:                            ##
##                                                                           ##
## RSYNC_LEECH_TMPDIR:                                                       ##
##   Just a dedicated TMPDIR for this script, do not use $HOME and do not    ##
##   use a path that other scripts may expect to use. Unsure? Leave it be.   ##
##                                                                           ##
## RSYNC_REMOTE_HOST:                                                        ##
##   Hostname to connect to. Recommend using a host set in  ~/.ssh/config    ##
##                                                                           ##
## RSYNC_REMOTE_DIR:                                                         ##
##   Directory on remote server to slurp files from. Relative to login dir.  ##
##                                                                           ##
## RSYNC_LEECH_INCOMING_DIR:                                                 ##
##   Where to keep files currently being leeched.                            ##
##                                                                           ##
## RSYNC_LEECH_COMPLETED_DIR:                                                ##
##   Where to move files after their completition.                           ##
##                                                                           ##
## RSYNC_LEECH_ALREADY_GOT_DIR:                                              ##
##   Make an empty file here for each completed file. This is so when you    ##
##   move a file out of the COMPLETED_DIR it doesn't try to redownload.      ##
##                                                                           ##
## RSYNC_LEECH_PRIORITY_RE:                                                  ##
##   If a line matches against this RE, it goes to the top of the queue.     ##
##                                                                           ##
## RSYNC_LEECH_SCREEN_TITLE_PREFIX:                                          ##
##   (purely cosmetic) Set a prefix for your screen window title.            ##
##   (You are running this in screen, aren't you?)                           ##
##                                                                           ##
## Important notes:                                                          ##
##   Each line is the remote directory listing is a queue item. That could   ##
##   be a single file, or a very large directory. This method does not allow ##
##   for a great deal of additional drill-down save for what you can pass to ##
##   rsync (by updating RSYNC_LEECH_RSYNC_OPTS). Exercise caution though. :) ##
##                                                                           ##
###############################################################################

RSYNC_LEECH_TMPDIR="$HOME/.rsync-leech/.temp"
RSYNC_LEECH_REMOTE_HOST="rto"
RSYNC_LEECH_REMOTE_DIR="complete"
RSYNC_LEECH_INCOMING_DIR="/archive/new-downloads"
RSYNC_LEECH_COMPLETED_DIR="/archive/new-downloads/complete"
RSYNC_LEECH_ALREADY_GOT_DIR="/archive/new-downloads/.already-got"
RSYNC_LEECH_PRIORITY_RE='([Kk][Ee][Yy]|\.avi|\.mkv)'
RSYNC_LEECH_SCREEN_TITLE_PREFIX="rsync-leech:"

#########  Advanced options, you will likely never need to change.  ###########

RSYNC_LEECH_SSH_OPTS=""
RSYNC_LEECH_RSYNC_OPTS="-arvz --times --modify-window 1 --partial --size-only --stats --progress"

######### On to the actual script.                                  ###########
###############################################################################

# If the below file exists, we'll source it (potentially overwriting variables above)
[[ -f "$HOME/.gs3" ]] && source "$HOME/.gs3" # gs3 = global Shell Script Settings :)

tmp_avail="$RSYNC_LEECH_TMPDIR/rsync-leech-available.txt"  # list of available files
tmp_queue="$RSYNC_LEECH_TMPDIR/rsync-leech-queue.txt"      # generated queue (after sorted/prioritising)

# sst() - Set Screen Title - Update screen title
function sst() {
    [[ "$TERM" = "screen" ]] && echo -ne "\033k${RSYNC_LEECH_SCREEN_TITLE_PREFIX}${@}\033\\"
}

while :; do

    # Clean previous temp directory, then remake (along with download directory)
    [[ -d "$RSYNC_LEECH_TMPDIR" ]] && rm -rf "$RSYNC_LEECH_TMPDIR"
    mkdir -p "$RSYNC_LEECH_TMPDIR" "$RSYNC_LEECH_COMPLETED_DIR"

    # Download available file listing
    sst "getting available files"
    ssh $RSYNC_LEECH_SSH_OPTS "$RSYNC_LEECH_REMOTE_HOST" ls -1 "$RSYNC_LEECH_REMOTE_DIR" > "$tmp_avail"

    # Check that we haven't previously gotten $line
    while read -r line; do
        if [ ! -e "${RSYNC_LEECH_ALREADY_GOT_DIR}/${line}" ]; then
            echo "${line}" >> "$tmp_queue"
        fi
    done < "$tmp_avail"

    if [ ! -f "$tmp_queue" ]; then
        sst "nothing to download.."
        sleep 2
    fi

    grep -Ev "$RSYNC_LEECH_PRIORITY_RE" "$tmp_queue" > "${tmp_queue}.sorted" # send non-priority items to file
    grep -E "$RSYNC_LEECH_PRIORITY_RE" "$tmp_queue" >> "${tmp_queue}.sorted" # append priority items to file

    for arg in $@; do
        # Additional options:
        #   --skip RE_PATTERN - Skip lines matching RE_PATTERN
        #   --only RE_PATTERN - Only download lines matching RE_PATTERN
        shift
        if [ "$arg" == "--skip" ]; then
            sed -i "/${1}/d" "${tmp_queue}.sorted" || exit $?
        elif [ "$arg" == "--only" ]; then
            sed -i -n "/${1}/p" "${tmp_queue}.sorted" || exit $?
        fi
    done

    sed -e 's/^/queuing up item: /' "${tmp_queue}.sorted"

    while read -r line; do
        if [ -e "${RSYNC_LEECH_ALREADY_GOT_DIR}/${line}" ]; then
            echo "dupe: $line"
        else
            echo "fetching item: $line"
            sst "fetching $line"
            rsync $RSYNC_LEECH_RSYNC_OPTS "${RSYNC_LEECH_REMOTE_HOST}:\"${RSYNC_LEECH_REMOTE_DIR}/${line}\"" "${RSYNC_LEECH_INCOMING_DIR}/"
            if [ $? = 0 ]; then
                echo "Successfully fetched $line"
                touch "${RSYNC_LEECH_ALREADY_GOT_DIR}/${line}"
                mv "${RSYNC_LEECH_INCOMING_DIR}/${line}" "${RSYNC_LEECH_COMPLETED_DIR}/${line}"
            else
                sst "encountered error fetching $line"
                echo "Encountered an issue fetching $line" > /dev/stderr
                sleep 3 # wait and continue..
            fi
        fi
    done < "${tmp_queue}.sorted"

    # do it all again (:
done

