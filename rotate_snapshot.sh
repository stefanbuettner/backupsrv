#!/bin/bash
# ----------------------------------------------------------------------
# mikes handy rotating-filesystem-snapshot utility: daily snapshots
# ----------------------------------------------------------------------
# intended to be run daily as a cron job when hourly.3 contains the
# midnight (or whenever you want) snapshot; say, 13:00 for 4-hour snapshots.
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

# ------------- file locations -----------------------------------------

# Mount point of the backup destination. Has to be specified in /etc/fstab
SNAPSHOT_RW=/root/snapshots;

# The actual backup directory
HOST_BACKUP=$SNAPSHOT_RW/$HOST

# List of patterns which to exclude. See rsync manual.
EXCLUDES=/root/backupexcludes.txt

# The backup lock file
BACKUP_LOCK=$HOST_BACKUP/.backup.lock

# The rw mount lock
MOUNT_LOCK=$SNAPSHOT_RW/.backup.lock

# Logfile
GLOBAL_LOG=/var/log/backupsrv.log
LOG=/tmp/backupsrv-$HOST.log

# ------------- the script itself --------------------------------------
$ECHO "===============================================================================" >> $LOG ;
$ECHO "$($DATE): Rotating for $HOST" >> $LOG ;
if [ $DRY_RUN ]; then
	$ECHO "RUNNING DRY!" >> $LOG ;
fi

$ECHO "Turnus      : $TURNUS" >> $LOG ;
$ECHO "Count       : $COUNT" >> $LOG ;
$ECHO "Fast Turnus : $TURNUS_FAST" >> $LOG ;
$ECHO "Fast Count  : $COUNT_FAST" >> $LOG ;

source "$SCRIPT_DIR/backupsrv_utility.sh"
prepareBackup ;

# step 1: delete the oldest snapshot, if it exists:
SRC="$HOST_BACKUP/$TURNUS.$COUNT"
$ECHO "Step 1: Deleting oldest snapshot '$SRC'." &>> $LOG
if [ -d "$SRC" ] ; then
	if [ ! $DRY_RUN ]; then
		$RM -rf "$HOST_BACKUP/$TURNUS.$COUNT" &>> $LOG
	fi
else
	$ECHO "Skipping because $SRC was not found." &>> $LOG
fi

# step 2: shift the middle snapshots(s) back by one, if they exist
$ECHO "Step 2: Shifting middle snapshots." &>> $LOG
for ((i = $COUNT - 1; i > 0; i--));
do
	SRC="$HOST_BACKUP/$TURNUS.$i"
	DST="$HOST_BACKUP/$TURNUS.$((i+1))"
	if [ -d "$SRC" ]; then
		$ECHO "Move $SRC to $DST" &>> $LOG ;
		if [ ! $DRY_RUN ]; then
			$MV "$SRC" "$DST" &>> $LOG ;
		fi
	fi
done

# step 3: make a hard-link-only (except for dirs) copy of
# either turnus.2 or turnus-fast.count, assuming that exists,
# into turnus.1
$ECHO "Step 3: Saving most recent $TURNUS." &>> $LOG
DST="$HOST_BACKUP/${TURNUS}.1"
if [ $TURNUS_FAST ]; then
	SRC="$HOST_BACKUP/$TURNUS_FAST.$COUNT_FAST"
else
	SRC="$HOST_BACKUP/$TURNUS.2"
fi
if [ -d "$SRC" ]; then
	$ECHO "Copying $SRC to $DST" &>> $LOG
	if [ ! $DRY_RUN ]; then
		$CP -al "$SRC" "$DST" &>> $LOG
	fi
else
	$ECHO "Skipping because $SRC does not exit." &>> $LOG
fi

backupExit 0
