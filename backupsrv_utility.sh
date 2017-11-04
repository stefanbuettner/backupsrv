# ----------------------------------------------------------------------
# This file is based on the following article
#   http://www.mikerubel.org/computers/rsync_snapshots/#Isolation
# with adaptions using these:
#    http://jonmoore.duckdns.org/index.php/linux-articles/39-backup-with-rsync-or-dd
#    https://wiki.ubuntuusers.de/NFS/
# ----------------------------------------------------------------------
# Stefan Büttner, 2017
# ----------------------------------------------------------------------

if [ -z "$SCRIPT_DIR" ]; then
	$ECHO "No script dir set. Exiting..."
	exit 1
fi
source "$SCRIPT_DIR/global_vars.sh"

# Removes HOST_BACKUP/TURNUS.COUNT and rotates HOST_BACKUP/TURNUS.(i-1) to HOST_BACKUP/TURNUS.i."
# If TURNUS_FAST is not set, it copies the new TURNUS.2 to TURNUS.1."
# Otherwise it copies TURNUS_FAST.COUNT_FAST to TURNUS.1"
function rotateSnapshots {

	# Ensure that we have the required variables set.
	# I assume that the other variables have been checked by prepareBackup already.
	# TODO: perhaps let prepareBackup set a variable that it was executed which we can check here.
	if [ -z "$TURNUS" ]; then
		$ECHO "rotateSnapshots: TURNUS not set. Returning." &>> "$LOG"
		return $ERR_GENERAL
	fi

	if [ -z "$COUNT" ]; then
		$ECHO "rotateSnapshots: COUNT not set. Returning." &>> "$LOG"
		return $ERR_GENERAL
	fi

	if [ -z "$HOST_BACKUP" ]; then
		$ECHO "rotateSnapshots: HOST_BACKUP not set. Returning." &>> "$LOG"
		return $ERR_GENERAL
	fi

	# step 1: delete the oldest snapshot, if it exists:
	local SRC="$HOST_BACKUP/$TURNUS.$COUNT"
	$ECHO "Step 1: Deleting oldest snapshot '$SRC'." &>> "$LOG"
	if [ -d "$SRC" ] ; then
		if [ ! $DRY_RUN ]; then
			$RM -rf "$SRC" &>> "$LOG"
			if [ "$?" -ne 0 ]; then
				return $ERR_GENERAL
			fi
		fi
	else
		$ECHO "Skipping because $SRC was not found." &>> $LOG
	fi
	
	# step 2: shift the middle snapshots(s) back by one, if they exist
	$ECHO "Step 2: Shifting middle snapshots." &>> $LOG
	for ((i = $COUNT - 1; i > 0; i--));
	do
		local SRC="$HOST_BACKUP/$TURNUS.$i"
		local DST="$HOST_BACKUP/$TURNUS.$((i+1))"
		if [ -d "$SRC" ]; then
			$ECHO "Move $SRC to $DST" &>> $LOG ;
			if [ ! $DRY_RUN ]; then
				$MV "$SRC" "$DST" &>> $LOG ;
				if [ "$?" -ne 0 ]; then
					return $ERR_GENERAL
				fi
			fi
		fi
	done
	
	# step 3: make a hard-link-only (except for dirs) copy of
	# either turnus.2 or turnus-fast.count, assuming that exists,
	# into turnus.1
	$ECHO "Step 3: Saving most recent $TURNUS." &>> $LOG
	local DST="$HOST_BACKUP/$TURNUS.1"

	# Check if most recent version can be created if TURNUS_FAST is given.
	if [ -n "$TURNUS_FAST" ]; then
		if [ -z "$COUNT_FAST" ]; then
			local TURNUS_FAST_SRC="$HOST_BACKUP/$TURNUS_FAST.1"
		else
			local TURNUS_FAST_SRC="$HOST_BACKUP/$TURNUS_FAST.$COUNT_FAST"
		fi
	fi

	# If TURNUS_FAST is given but the backup is not present,
	# copy the last TURNUS backup to TURNUS.1.
	if [ -d "$TURNUS_FAST_SRC" ]; then
		local SRC="$TURNUS_FAST_SRC"
	else
		local SRC="$HOST_BACKUP/$TURNUS.2"
	fi

	# SRC might still not exist, if no folders in this turnus ever existed.
	if [ -d "$SRC" ]; then
		$ECHO "Copying $SRC to $DST" &>> $LOG
		if [ ! $DRY_RUN ]; then
			$CP -al "$SRC" "$DST" &>> $LOG
			if [ "$?" -ne 0 ]; then
				return $ERR_GENERAL
			fi
		fi
	else
		$ECHO "Skipping because $SRC does not exit." &>> $LOG
	fi

	return 0
}


function prepareBackup {

	# Ensure that the required variables are set
	if [ -z "$ECHO" ]; then
		exit $ERR_GENERAL
	fi

	if [ -z "$LOG" ]; then
		$ECHO "LOG not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$GLOBAL_LOG" ]; then
		$ECHO "GLOBAL_LOG not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$SNAPSHOT_RW" ]; then
		$ECHO "SNAPSHOT_RW not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$HOST_BACKUP" ]; then
		$ECHO "HOST_BACKUP not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$MOUNT_LOCK" ]; then
		$ECHO "MOUNT_LOCK not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$BACKUP_LOCK" ]; then
		$ECHO "BACKUP_LOCK not set. Aborting."
		exit $ERR_GENERAL
	fi

	if [ -z "$CAT" ]; then
		$ECHO "CAT not set. Aborting."
		exit $ERR_GENERAL
	fi
	
	# Make sure we're running as root.
	ensureRoot
	local FAIL=$?
	if [ "$FAIL" -ne 0 ]; then
		return $FAIL
	fi
	
	# Ensure that the snapshots device is mounted.
	ensureMounted $SNAPSHOT_RW
	local FAIL=$?
	if [ "$FAIL" -ne 0 ]; then
		return $FAIL
	fi

	# Check if another backup process is still active.
	ensureExclusivity
	local FAIL=$?
	if [ "$FAIL" -ne 0 ]; then
		return $FAIL
	fi

	# Make sure the backup device is writable.
	ensureWritable
	if [ "$?" -ne 0 ]; then
		return $ERR_GENERAL
	fi

	# Ensure that the HOST_BACKUP folder exists
	if [ ! -d "$HOST_BACKUP" ]; then
		$ECHO "Creating $HOST_BACKUP." &>> $LOG
		if [ ! $DRY_RUN ]; then
			$MKDIR -p "$HOST_BACKUP" &>> $LOG
			if [ "$?" -ne 0 ]; then
				return $ERR_GENERAL
			fi
		fi
	fi

	# Just hope that in the meantime no other process locked it.
	lockBackupFolder
	local FAIL=$?
	if [ "$FAIL" -ne 0 ]; then
		return $FAIL
	fi

	return 0
}

# Cleanup everything which was done by prepareBackup.
function backupExit {

	local FAIL=$1

	# If the abort is not due to another process is still working
	# unlock the folders
	if [ "$FAIL" -ne "$ERR_LOCKED" ]; then
		unlockBackupFolder

		# Now remount the RW snapshot mountpoint as readonly
		# if we are the last to access it.
		# Also if there is no mount lock file anymore, remount as
		# read only
		local REMOUNT_RO=true
		if [ -f "$MOUNT_LOCK" ]; then
			local NUM=$($CAT "$MOUNT_LOCK")
			NUM=$(( NUM - 1 ))
			if [ $NUM -gt 0 ]; then
				$ECHO "Still $NUM are accessing $SNAPSHOT_RW." &>> "$LOG"
				REMOUNT_RO=false
				if [ ! $DRY_RUN ]; then
					$ECHO $NUM > "$MOUNT_LOCK"
				fi
			else
				$ECHO "Unlocking $SNAPSHOT_RW." &>> "$LOG"
				if [ ! $DRY_RUN ]; then
					$RM "$MOUNT_LOCK" &>> "$LOG"
				fi
			fi
		fi

		if [ $REMOUNT_RO == true ]; then
			$ECHO "Remounting $SNAPSHOT_RW as read-only." &>> "$LOG"
			if [ ! $DRY_RUN ]; then
				$MOUNT -o remount,ro $SNAPSHOT_RW &>> "$LOG"
				if [ "$?" -ne 0 ]; then
					$ECHO "snapshot: could not remount $SNAPSHOT_RW readonly" >> "$LOG"
					FAIL=$ERR_GENERAL
				fi
			fi
		else
			$ECHO "Leaving $SNAPSHOT_RW mounted as rw." &>> "$LOG"
		fi
	fi

	local STATUS="SUCCEEDED"
	if (( $FAIL )); then
		STATUS="FAILED"
	fi

	$ECHO "$($DATE) Backup $STATUS for $HOST." >> "$LOG"

	# First append the log to the global log
	$CAT "$LOG" &>> "$GLOBAL_LOG"

	# If an error occurred, print the log to stderr so that the cron job sends an email.
	if (( $FAIL )); then
		$CAT "$LOG" 1>&2
	fi

	if [ -f "$LOG" ]; then
		$RM "$LOG"
	fi

	exit $FAIL
}


# Ensure that the snapshots device is mounted
function ensureMounted {
	local MOUNT_POINT="$1"
	$FINDMNT "$MOUNT_POINT" &> /dev/null
	if [ "$?" -ne 0 ]; then
		# If not, try to mount it.
		# If this doesn't succeed, exit.
		$ECHO "Mounting $MOUNT_POINT" &>> "$LOG"
		if [ ! $DRY_RUN ]; then
			$MOUNT --target "$MOUNT_POINT" &>> "$LOG"
			if [ "$?" -ne 0 ]; then
				return $ERR_GENERAL
			fi
		fi

:		# FIXME: Remove all locks which might still be there because the harddrive was plugged out/unmounted/whatever when a backup process was still working.
	fi

	return 0
}


# Attempt to remount the backup device as RW; else abort
# Check if SNAPSHOT_RW is already mounted rw by another backup.
# If so, increase the usage counter, otherwise create one.
function ensureWritable {
	# The mount lock should exist if and only if the snapshots folder is mounted writable.
	# So mount it as writable if it does not exist.
	# Remounting a writable mount as writable doesn' fail.
	if [ ![ -f "$MOUNT_LOCK" ] ]; then
		$ECHO "Remounting $SNAPSHOT_RW writable." &>> "$LOG"
		if [ ! $DRY_RUN ]; then
			$MOUNT -o remount,rw --target $SNAPSHOT_RW &>> "$LOG"
			if [ "$?" -ne 0 ]; then
				$ECHO "snapshot: could not remount $SNAPSHOT_RW readwrite" >> "$LOG"
				return $ERR_GENERAL
			fi
		fi
	fi

	# Now check again if the mount lock exists.
	# Some other process might have created it because they were launched simultaneously.
	# This hopefully fixes the bug that two simultaneously started rotations tasks
	# don't work together. Both mounted the partition as writable and the first one, which
	# finished, remounted the partition as read-only.
	if [ -f "$MOUNT_LOCK" ]; then
		local NUM=$($CAT "$MOUNT_LOCK")
		$ECHO "$NUM backups accessing $SNAPSHOT_RW." &>> "$LOG"
		if [ ! $DRY_RUN ]; then
			$ECHO "Increasing by 1" &>> "$LOG"
			$ECHO "$(( $NUM + 1 ))" > "$MOUNT_LOCK"
		fi
	else
		$ECHO "Locking $SNAPSHOT_RW as writable." &>> "$LOG"
		if [ ! $DRY_RUN ]; then
			$ECHO "1" > "$MOUNT_LOCK"
		fi
	fi

	return 0
}

# Check if another backup process is still active
function ensureExclusivity {
	if [ -f $BACKUP_LOCK ]; then
		$ECHO "Another backup process still seems to be active." >> "$LOG"
		return $ERR_LOCKED
	fi

	return 0
}

function lockBackupFolder {
	# Just hope, that in the meantime no other process locked.
	$ECHO "Locking $HOST_BACKUP." &>> "$LOG"
	if [ ! $DRY_RUN ]; then
		$TOUCH $BACKUP_LOCK &>> "$LOG"
	fi

	return 0
}


function unlockBackupFolder {
	# note: do *not* update the mtime of daily.0; it will reflect
	# when hourly.3 was made, which should be correct.
	if [ -f "$BACKUP_LOCK" ]; then
		$ECHO "Unlocking $HOST_BACKUP." &>> "$LOG"
		if [ ! $DRY_RUN ]; then
			$RM "$BACKUP_LOCK" &>> "$LOG"
			if [ "$?" -ne 0 ]; then
				return $ERR_GENERAL
			fi
		fi
	fi

	return 0
}


# make sure we're running as root
function ensureRoot {
	if (( `$ID -u` != 0 )); then { $ECHO "Sorry, must be root.  Exiting..." >> "$LOG"; return 1; } fi
}

# Checks if the global log exceeds some size.
# If so, it moves the log by appending an increasing number and zips it using gzip.
function archiveLog {
	BYTES=$($STAT --printf="%s" "$GLOBAL_LOG")

	# If greater than 250M
	if [ $BYTES -gt 250000000 ]; then
		i=1
		for file in "$GLOBAL_LOG".*.gz ; do
			k=${file#$GLOBAL_LOG.}
			k=${k%.gz}
			if [ "$k" -gt "$i" ]; then
				i=$k
			fi
		done
		let 'i=i+1'
		LOG_ARCHIVE="$GLOBAL_LOG.$i"
		$MV "$GLOBAL_LOG" "$LOG_ARCHIVE"
		$GZIP "$LOG_ARCHIVE" -9
	fi
}
