function prepareBackup {
	
	# Make sure we're running as root.
	ensureRoot ;
	
	# Ensure that the snapshots device is mounted.
	ensureMounted $SNAPSHOT_RW ;

	# Check if another backup process is still active.
	ensureExclusivity ;

	# Make sure the backup device is writable.
	ensureWritable ;

	# Just hope that in the meantime no other process locked it.
	lockBackupFolder ;

}

# Cleanup everything which was done by prepareBackup.
function backupExit {

	unlockBackupFolder ;

	FAIL=$1

	# Now remount the RW snapshot mountpoint as readonly
	# if we are the last to access it.
	# Also if there is no mount lock file anymore, remount as
	# read only
	REMOUNT_RO=true
	if [ -f "$MOUNT_LOCK" ]; then
		NUM=$(CAT "$MOUNT_LOCK")
		NUM=$(( NUM - 1 ))
		if [ $NUM -gt 0 ]; then
			$ECHO "Still $NUM are accessing $SNAPSHOT_RW." &>> $LOG
			REMOUNT_RO=false
			if [ ! $DRY_RUN ]; then
				$ECHO $NUM > "$MOUNT_LOCK"
			fi
		else
			$ECHO "Unlocking $SNAPSHOT_RW." &>> $LOG
			if [ ! $DRY_RUN ]; then
				$RM "$MOUNT_LOCK" &>> $LOG
			fi
		fi
	fi

	if [ $REMOUNT_RO == true ]; then
		$ECHO "Remounting $SNAPSHOT_RW as read-only." &>> $LOG
		if [ ! $DRY_RUN ]; then
			$MOUNT -o remount,ro $SNAPSHOT_RW &>> $LOG
			if (( $? )); then
				$ECHO "snapshot: could not remount $SNAPSHOT_RW readonly" >> $LOG ;
				FAIL=1
			fi
		fi
	else
		$ECHO "Leaving $SNAPSHOT_RW mounted as rw." &>> $LOG
	fi

	STATUS="SUCCEEDED"
	if (( $FAIL )); then
		STATUS="FAILED"
	fi

	$ECHO "$($DATE) Backup $STATUS for $HOST." >> $LOG ;
	# If an error occurred, print the log to stderr so that the cron job sends an email.
	if (( $FAIL )); then
		$CAT $LOG 1>&2 ;
	fi

	$CAT $LOG &>> $GLOBAL_LOG
	if [ -f "$LOG" ]; then
		$RM $LOG ;
	fi

	exit $FAIL
}


# Ensure that the snapshots device is mounted
function ensureMounted {
	MOUNT_POINT="$1"
	$FINDMNT "$MOUNT_POINT" &> /dev/null ;
	if [ "$?" -ne 0 ]; then
		# If not, try to mount it.
		# If this doesn't succeed, exit.
		$ECHO "Mounting $MOUNT_POINT" &>> $LOG ;
		if [ ! $DRY_RUN ]; then
			$MOUNT --target "$MOUNT_POUNT" &>> $LOG ;
			if (( $? )); then
				backupExit 1;
			fi
		fi
	fi
}


# Attempt to remount the backup device as RW; else abort
# Check if SNAPSHOT_RW is already mounted rw by another backup.
# If so, increase the usage counter, otherwise create one.
function ensureWritable {
	if [ -f "$MOUNT_LOCK" ]; then
		NUM=$($CAT "$MOUNT_LOCK")
		$ECHO "$NUM backups accessing $SNAPSHOT_RW." &>> $LOG
		if [ ! $DRY_RUN ]; then
			$ECHO "Increasing by 1" &>> $LOG
			$ECHO "$(( $NUM + 1 ))" > "$MOUNT_LOCK"
		fi
	else
		$ECHO "Remounting $SNAPSHOT_RW writable." &>> $LOG ;
		if [ ! $DRY_RUN ]; then
			$MOUNT -o remount,rw --target $SNAPSHOT_RW &>> $LOG ;
			if (( $? )); then
			{
				$ECHO "snapshot: could not remount $SNAPSHOT_RW readwrite" >> $LOG ;
				backupExit 1;
			}
			fi
		fi
		$ECHO "Locking $SNAPSHOT_RW as writable." &>> $LOG
		if [ ! $DRY_RUN ]; then
			$ECHO "1" > "$MOUNT_LOCK"
		fi
	fi
}

# Check if another backup process is still active
function ensureExclusivity {
	if [ -f $BACKUP_LOCK ]; then
		$ECHO "Another backup process still seems to be active." >> $LOG ; 
		backupExit 1;
	fi
}

function lockBackupFolder {
	# Just hope, that in the meantime no other process locked.
	$ECHO "Locking $HOST_BACKUP" &>> $LOG ;
	if [ ! $DRY_RUN ]; then
		$TOUCH $BACKUP_LOCK &>> $LOG ;
	fi
}


function unlockBackupFolder {
	# note: do *not* update the mtime of daily.0; it will reflect
	# when hourly.3 was made, which should be correct.
	if [ -f "$BACKUP_LOCK" ]; then
		$ECHO "Unlocking $HOST_BACKUP." &>> $LOG
		if [ ! $DRY_RUN ]; then
			$RM $BACKUP_LOCK &>> $LOG ;
		fi
	fi
}


# make sure we're running as root
function ensureRoot {
	if (( `$ID -u` != 0 )); then { $ECHO "Sorry, must be root.  Exiting..." >> $LOG; backupExit 1; } fi
}

