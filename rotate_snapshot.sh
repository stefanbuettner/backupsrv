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
unset PATH

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

TOUCH=/usr/bin/touch

# ------------- pase CLI parameters ------------------------------------

function printHelp {
	$ECHO ""
	$ECHO "USAGE:"
	$ECHO ""
	$ECHO "    $0 --host <host> --turnus <turnus> [--count <integer>] [--turnus-fast <turnus>] [--count-fast <integer>] [--dry-run] [-h | --help]"
	$ECHO ""
	$ECHO "    Removes /snapshots/<host>/<turnus>.<count> and rotates /snapshots/<host>/<turnus>.<i-1> to /snapshots/<host>/<turnus>.<i>."
	$ECHO "    If no fast turnus is given, it copies the new <turnus>.2 to <turnus>.1."
	$ECHO "    Otherwise it copies <fast-turnus>.<count-fast> to <turnus>.1"
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
		--turnus-fast)
			shift
			TURNUS_FAST="$1"
		;;
		--count-fast)
			shift
			COUNT_FAST="$1"
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
	$ECHO "No host given.";
	printHelp ;
	exit 1
fi

if [ "$TURNUS" == "" ]; then
	$ECHO "No turnus given."
	printHelp ;
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
$ECHO "===============================================================================" >> $LOG ;
$ECHO "$($DATE): Rotating for $HOST" >> "$LOG"
if [ $DRY_RUN ]; then
	$ECHO "RUNNING DRY!" >> "$LOG"
fi

$ECHO "Turnus      : $TURNUS" >> "$LOG"
$ECHO "Count       : $COUNT" >> "$LOG"
$ECHO "Fast Turnus : $TURNUS_FAST" >> "$LOG"
$ECHO "Fast Count  : $COUNT_FAST" >> "$LOG"
prepareBackup
FAIL=$?
if [ "$FAIL" -ne 0 ]; then
	backupExit $FAIL
fi

rotateSnapshots
FAIL=$?
backupExit $FAIL

