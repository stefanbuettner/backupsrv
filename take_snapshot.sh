#!/bin/bash
# ----------------------------------------------------------------------
# This file is based on the following article
#   http://www.mikerubel.org/computers/rsync_snapshots/#Isolation
# with adaptions using these:
#    http://jonmoore.duckdns.org/index.php/linux-articles/39-backup-with-rsync-or-dd
#    https://wiki.ubuntuusers.de/NFS/
# ----------------------------------------------------------------------
# Stefan Büttner, 2017
# ----------------------------------------------------------------------

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
unset PATH	# suggestion from H. Milz: avoid accidental use of $PATH

# ------------- system commands used by this script --------------------

ID=/usr/bin/id;
ECHO=/bin/echo;

MOUNT=/bin/mount;
FINDMNT=/bin/findmnt
RM=/bin/rm;
MV=/bin/mv;
CP=/bin/cp;
TOUCH=/usr/bin/touch;
DATE=/bin/date
CAT=/bin/cat
MKDIR=/bin/mkdir

RSYNC=/usr/bin/rsync;

# ------------- pase CLI parameters ------------------------------------

function printHelp {
	$ECHO ""
	$ECHO "USAGE:"
	$ECHO ""
	$ECHO "    $0 --host <host> --turnus <turnus> [--count <integer>] [--dry-run] [-h | --help]"
	$ECHO ""
	$ECHO "    Takes a snapshots of the given host to /snapshots/<host>/<turnus>.1"
	$ECHO "    If count is given, rotates all snapshots from 1 to count before taking"
    $ECHO "    the snapshot."
	$ECHO ""
}

HOST=""
TURNUS=""
COUNT=1

while (($#))
do
	case $1 in
		--help | -h)
			printHelp ;
			exit ;
		;;
		--host)
			shift
			HOST="$1"
		;;
		--turnus)
			shift
			TURNUS="$1"
		;;
		--count)
			shift
			COUNT=$1
		;;
		--dry-run)
			DRY_RUN=true
		;;
		*)
			$ECHO "Unknown parameter $arg. Try --help for more information."
		exit 1
	esac
	shift
done

if [ "$HOST" == "" ]; then
	$ECHO "No host given."
	printHelp
	exit 1
fi

if [ "$TURNUS" == "" ]; then
	$ECHO "No turnus given."
	printHelp
	exit 1
fi

if [ $COUNT -le 0 ]; then
	$ECHO "--count must be positive!"
	exit 1
fi

# ------------- global variables -----------------------------------------

# Sets variables such as LOG and HOST_BACKUP
source "$SCRIPT_DIR/backupsrv_utility.sh"

# ------------- the script itself --------------------------------------
$ECHO "===============================================================================" >> "$LOG"
$ECHO "$($DATE): Beginning backup for $HOST" >> "$LOG"

$ECHO "Turnus : $TURNUS" >> "$LOG"
$ECHO "Count  : $COUNT" >> "$LOG"

prepareBackup
FAIL=$?
if [ "$FAIL" -ne 0 ]; then
	backupExit $FAIL
fi

# rotating snapshots of / (fixme: this should be more general)
unset TURNUS_FAST # Just to be save.
rotateSnapshots
FAIL=$?
if [ "$FAIL" -ne 0 ]; then
	backupExit $FAIL
fi

# Ensure that the destination dir really exists.
# It may not in the first run.
DST="$HOST_BACKUP/$TURNUS.1"
if [ ! -d $DST ]; then
	$ECHO "Creating $DST." &>> "$LOG"
	if [ ! $DRY_RUN ]; then
		$MKDIR -p "$DST" &>> "$LOG"
		if [ "$?" -ne 0 ]; then
			backupExit $ERR_GENERAL
		fi
	fi
fi

# step 4: rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
if [ "$DRY_RUN" == true ]; then
	RSYNC_DRYRUN_ARG="--dry-run"
fi
$ECHO "Syncing to $DST" >> "$LOG"
$RSYNC								\
	-va --delete --delete-excluded				\
	--exclude-from="$EXCLUDES"				\
	--compress						\
	$RSYNC_DRYRUN_ARG					\
	$HOST::backupsrc/ "$DST" > /dev/null 2>> "$LOG"

RSYNC_RESULT=$?
if  [ "$RSYNC_RESULT" -ne 0 -a "$RSYNC_RESULT" -ne 10 ]; then
	$ECHO "rsync exited with: $RSYNC_RESULT" >> "$LOG"
	FAIL=$ERR_GENERAL
fi

# step 5: update the mtime of hourly.0 to reflect the snapshot time
$ECHO "Updating $DST timestamp." &>> "$LOG"
if [ ! $DRY_RUN ]; then
	$TOUCH "$DST" &>> "$LOG"
fi

# and thats it.
backupExit $FAIL;

