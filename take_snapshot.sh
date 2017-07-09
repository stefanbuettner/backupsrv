#!/bin/bash
# ----------------------------------------------------------------------
# mikes handy rotating-filesystem-snapshot utility
# ----------------------------------------------------------------------
# this needs to be a lot more general, but the basic idea is it makes
# rotating backup-snapshots of /home whenever called
# ----------------------------------------------------------------------
# This file is based on the following article
#   http://www.mikerubel.org/computers/rsync_snapshots/#Isolation
# with adaptions using these:
#    http://jonmoore.duckdns.org/index.php/linux-articles/39-backup-with-rsync-or-dd
#    https://wiki.ubuntuusers.de/NFS/
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
	$ECHO "    Takes a snapshots of the given host to /snapshots/<hostname>/<turnus>.0"
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

# ------------- file locations -----------------------------------------

# Mount point of the backup destination. Has to be specified in /etc/fstab
SNAPSHOT_RW=/root/snapshots;

# The actual backup directory
HOST_BACKUP=$SNAPSHOT_RW/$HOST

# List of patterns which to exclude. See rsync manual.
EXCLUDES="${SCRIPT_DIR}/backupexcludes.txt"

# The backup lock file
BACKUP_LOCK=$HOST_BACKUP/.backup.lock

# The rw mount lock
MOUNT_LOCK=$SNAPSHOT_RW/.backup.lock

# Logfile
GLOBAL_LOG=/var/log/backupsrv.log
LOG=/tmp/backupsrv-$HOST.log

# ------------- the script itself --------------------------------------
$ECHO "===============================================================================" >> $LOG ;
$ECHO "$($DATE): Beginning backup for $HOST" >> $LOG ;

$ECHO "Turnus : $TURNUS" >> $LOG ;
$ECHO "Count  : $COUNT" >> $LOG ;

source "$SCRIPT_DIR/backupsrv_utility.sh"
prepareBackup ;

# rotating snapshots of / (fixme: this should be more general)
unset TURNUS_FAST # Just to be save.
rotateSnapshots ;

# Ensure that the destination dir really exists.
# It may not in the first run.
DST="$HOST_BACKUP/$TURNUS.1"
$ECHO "Ensuring that $DST exists." &>> $LOG
if [ ! $DRY_RUN ]; then
	$MKDIR -p "$DST" &>> $LOG ;
fi

# step 4: rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
if [ "$DRY_RUN" == true ]; then
	RSYNC_DRYRUN_ARG="--dry-run"
fi
$ECHO "Syncing to $DST" >> $LOG ;
$RSYNC								\
	-va --delete --delete-excluded				\
	--exclude-from="$EXCLUDES"				\
	--compress						\
	$RSYNC_DRYRUN_ARG					\
	$HOST::backupsrc/ "$DST" > /dev/null 2>> $LOG ;

if (( $? )); then
	$ECHO "rsync exited with: $?" >> $LOG ;
	FAIL=1
fi

# step 5: update the mtime of hourly.0 to reflect the snapshot time
$ECHO "Updating $DST timestamp." &>> $LOG
if [ ! $DRY_RUN ]; then
	$TOUCH "$DST" &>> $LOG ;
fi

# and thats it.

backupExit $FAIL;

