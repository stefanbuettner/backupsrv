# Needs SCRIPT_DIR set

PID=$$

# Mount point of the backup destination. Has to be specified in /etc/fstab
SNAPSHOT_RW=/root/snapshots;
# The actual backup directory
HOST_BACKUP="$SNAPSHOT_RW"
if [ -n "$HOST" ]; then
	HOST_BACKUP="$HOST_BACKUP/$HOST"
fi

# The backup lock file
BACKUP_LOCK="$HOST_BACKUP/.backup.lock"

# The rw mount lock
MOUNT_LOCK="$SNAPSHOT_RW/.backup.lock"

# List of patterns which to exclude. See rsync manual.
if [ -n "$SCRIPT_DIR" ]; then
	EXCLUDES="${SCRIPT_DIR}/backupexcludes.txt"
fi

# Logfile
GLOBAL_LOG=/var/log/backupsrv.log
LOG=/tmp/backupsrv
if [ -n "$HOST" ]; then
	LOG="$LOG.$HOST"
fi

if [ -n "$PID" ]; then
	LOG="$LOG.$PID"
fi
LOG="$LOG.log"

# Error codes
ERR_GENERAL=1
ERR_LOCKED=2

