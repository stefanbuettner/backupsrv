#!/bin/bash
# ----------------------------------------------------------------------
# mikes handy rotating-filesystem-snapshot utility: daily snapshots
# ----------------------------------------------------------------------
# intended to be run daily as a cron job when hourly.3 contains the
# midnight (or whenever you want) snapshot; say, 13:00 for 4-hour snapshots.
# ----------------------------------------------------------------------

unset PATH

# ------------- system commands used by this script --------------------
ID=/usr/bin/id;
ECHO=/bin/echo;

MOUNT=/bin/mount;
FINDMNT=/bin/findmnt
RM=/bin/rm;
MV=/bin/mv;
CP=/bin/cp;

TOUCH=/usr/bin/touch

# ------------- pase CLI parameters ------------------------------------

function printHelp {
	$ECHO ""
	$ECHO "USAGE:"
	$ECHO ""
	$ECHO "    $0 --host <host> --turnus <turnus> [--count <integer>] [--turnus-fast <turnus>] [--count-fast <integer>] [-h | --help]"
	$ECHO ""
	$ECHO "    Removes /snapshots/<host>/<turnus>.<count> and rotates /snapshots/<host>/<turnus>.<i-1> to /snapshots/<host>/<turnus>.<i>."
	$ECHO "    If no fast turnus is given, it copies the new <turnus>.2 to <turnus>.1.
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
		*)
			$ECHO "Unknown parameter $arg. Try --help for more information."
		exit 1
	esac
	shift
done

if [ "$HOST" == "" ]; then
	$ECHO "No host given. See --help for more information."
	exit 1
fi

if [ "$TURNUS" == "" ]; then
	$ECHO "No turnus given. See --help for more information."
	exit 1
fi

if [ $COUNT -le 0 ]; then
	$ECHO "--count must be positive!"
	exit 1
fi

$ECHO "Host   : $HOST"
$ECHO "Turnus : $TURNUS"
$ECHO "Count  : $COUNT"

# ------------- file locations -----------------------------------------

# Mount point of the backup destination. Has to be specified in /etc/fstab
SNAPSHOT_RW=/root/snapshots;

# The actual backup directory
HOST_BACKUP=$SNAPSHOT_RW/$HOST

# List of patterns which to exclude. See rsync manual.
EXCLUDES=/root/backupexcludes.txt

# The backup lock file
BACKUP_LOCK=$HOST_BACKUP/.backup.lock

# Logfile
GLOBAL_LOG=/var/log/backupsrv.log
LOG=/tmp/backupsrv-$HOST.log

# ------------- a custom exit function ---------------------------------

function backupExit {
	FAIL=$1

	# now remount the RW snapshot mountpoint as readonly
	$MOUNT -o remount,ro $SNAPSHOT_RW &>> $LOG ;
	if (( $? )); then
	{
		$ECHO "snapshot: could not remount $SNAPSHOT_RW readonly" >> $LOG ;
		FAIL=1
	} fi;

	STATUS="done"
	if (( $FAIL )); then
		STATUS="FAILED"
	fi
	$ECHO "$($DATE) Backup $STATUS for $HOST." >> $LOG
	# If an error occurred, print the log to stderr so that the cron job sends an email.
	if (( $FAIL )); then
		$CAT $LOG 1>&2 ;
	fi
	$CAT $LOG >> $GLOBAL_LOG
	$RM $LOG
	exit $FAIL
}

# ------------- the script itself --------------------------------------

# make sure we're running as root
if (( `$ID -u` != 0 )); then { $ECHO "Sorry, must be root.  Exiting..."; exit; } fi

# Ensure that the snapshots device is mounted
$FINDMNT $SNAPSHOT_RW > /dev/null ;
if [ "$?" -ne 0 ]; then
	# If not, try to mount it.
	# If this doesn't succeed, exit.
	$MOUNT --target $SNAPSHOT_RW &>> $LOG ;
	if (( $? )); then
		backupExit 1;
	fi
else
	echo "$SNAPSHOT_RW is mounted" &>> $LOG ;
fi

# Check if another backup process is still active
if [ -f $BACKUP_LOCK ]; then
	$ECHO "Another backup process still seems to be active." >> $LOG ; 
	backupExit 1;
fi

# attempt to remount the RW mount point as RW; else abort
$MOUNT -o remount,rw --target $SNAPSHOT_RW &>> $LOG ;
if (( $? )); then
{
	$ECHO "snapshot: could not remount $SNAPSHOT_RW readwrite" >> $LOG ;
	backupExit 1;
}
fi;

# Just hope, that in the meantime no other process locked.
$TOUCH $BACKUP_LOCK &>> $LOG ;

# step 1: delete the oldest snapshot, if it exists:
if [ -d $SNAPSHOT_RW/daily.2 ] ; then			\
	$RM -rf $SNAPSHOT_RW/daily.2 ;			\
fi ;

# step 2: shift the middle snapshots(s) back by one, if they exist
if [ -d $SNAPSHOT_RW/daily.1 ] ; then			\
	$MV $SNAPSHOT_RW/daily.1 $SNAPSHOT_RW/daily.2 ;	\
fi;
if [ -d $SNAPSHOT_RW/daily.0 ] ; then			\
	$MV $SNAPSHOT_RW/daily.0 $SNAPSHOT_RW/daily.1;	\
fi;

# step 3: make a hard-link-only (except for dirs) copy of
# hourly.3, assuming that exists, into daily.0
if [ -d $SNAPSHOT_RW/hourly.3 ] ; then			\
	$CP -al $SNAPSHOT_RW/hourly.3 $SNAPSHOT_RW/daily.0 ;	\
fi;

# note: do *not* update the mtime of daily.0; it will reflect
# when hourly.3 was made, which should be correct.

$RM $BACKUP_LOCK &>> $LOG ;

# now remount the RW snapshot mountpoint as readonly

$MOUNT -o remount,ro $SNAPSHOT_RW &>> $LOG ;
if (( $? )); then
{
	$ECHO "snapshot: could not remount $SNAPSHOT_RW readonly" >> $LOG ;
	backupExit 1;
} fi;
