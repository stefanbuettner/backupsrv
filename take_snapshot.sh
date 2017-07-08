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
	$ECHO "    $0 --host <host> --turnus <turnus> [--count <integer>] [-h | --help]"
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
$ECHO "===============================================================================" >> $LOG ;
$ECHO "$($DATE): Beginning backup for $HOST" >> $LOG ;

$ECHO "Turnus : $TURNUS" >> $LOG ;
$ECHO "Count  : $COUNT" >> $LOG ;

# make sure we're running as root
#if (( `$ID -u` != 0 )); then { $ECHO "Sorry, must be root.  Exiting..." >> $LOG; backupExit 1; } fi

# Ensure that the snapshots device is mounted
$FINDMNT $SNAPSHOT_RW &> /dev/null ;
if [ "$?" -ne 0 ]; then
	# If not, try to mount it.
	# If this doesn't succeed, exit.
	$MOUNT --target $SNAPSHOT_RW
	if (( $? )); then
		$ECHO "Could not mount $SNAPSHOT_RW" >> $LOG
		backupExit 1;
	fi
else
	$ECHO "$SNAPSHOT_RW is mounted" >> $LOG;
fi

# Check if another backup process is still active
if [ -f $BACKUP_LOCK ]; then
	$ECHO "Another backup process still seems to be active." >> $LOG;
	backupExit 1;
fi

# Attempt to remount the RW mount point as RW; else abort
$MOUNT -o remount,rw --target $SNAPSHOT_RW ;
if (( $? )); then
{
	$ECHO "snapshot: could not remount $SNAPSHOT_RW readwrite" >> $LOG;
	backupExit 1;
}
fi;

# Ensure that the host's folder exists
$MKDIR -p $HOST_BACKUP &>> $LOG

# Just hope, that in the meantime no other process locked.
$TOUCH $BACKUP_LOCK &>> $LOG

# rotating snapshots of / (fixme: this should be more general)

# step 1: delete the oldest snapshot, if it exists:
if [ -d $HOST_BACKUP/$TURNUS.3 ] ; then			\
	$ECHO "Removing $TURNUS.3" >> $LOG		\
	$RM -rf $HOST_BACKUP/$TURNUS.3 &>> $LOG;			\
fi ;

# step 2: shift the middle snapshots(s) back by one, if they exist
if [ -d $HOST_BACKUP/$TURNUS.2 ] ; then			\
	$ECHO "Shifting $TURNUS.2 → $TURNUS.3" >> $LOG	\
	$MV $HOST_BACKUP/$TURNUS.2 $HOST_BACKUP/$TURNUS.3 &>> $LOG;	\
fi;
if [ -d $HOST_BACKUP/$TURNUS.1 ] ; then			\
	$ECHO "Shifting $TURNUS.1 → $TURNUS.2" >> $LOG	\
	$MV $HOST_BACKUP/$TURNUS.1 $HOST_BACKUP/$TURNUS.2 &>> $LOG;	\
fi;

# step 3: make a hard-link-only (except for dirs) copy of the latest snapshot,
# if that exists
if [ -d $HOST_BACKUP/$TURNUS.0 ] ; then			\
	$ECHO "Copy (hard linked) $TURNUS.0 → $TURNUS.1" >> $LOG	\
	$CP -al $HOST_BACKUP/$TURNUS.0 $HOST_BACKUP/$TURNUS.1 &>> $LOG;	\
fi;

# Ensure that the destination dir really exists.
# It may not in the first run.
$MKDIR -p $HOST_BACKUP/$TURNUS.0 &>> $LOG ;

# step 4: rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
$ECHO "Syncing to $HOST_BACKUP/$TURNUS.0" >> $LOG ;
$RSYNC								\
	-va --delete --delete-excluded				\
	--exclude-from="$EXCLUDES"				\
	$HOST::system/ $HOST_BACKUP/$TURNUS.0 > /dev/null 2>> $LOG ;

if (( $? )); then
	$ECHO "rsync exited with: $?" >> $LOG ;
	FAIL=1
fi

# step 5: update the mtime of hourly.0 to reflect the snapshot time
$TOUCH $HOST_BACKUP/$TURNUS.0 &>> $LOG ;

$RM $BACKUP_LOCK &>> $LOG ;

# and thats it.

backupExit $FAIL;

