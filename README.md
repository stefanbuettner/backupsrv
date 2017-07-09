# Installation
## On your client
1. Make the hostname for your raspberry pi available on your client, e.g. by editing `/etc/hosts`:
   ```
   <ip-address>        raspberrypi
   ```
2. Enable the rsyncd service and run it on a nice level of 10 or something.
   On my machine it worked by installing a systemd service by creating `/lib/systemd/system/rsync.service`:
   ```
   [Unit]
   Description=fast remote file copy program daemon
   ConditionPathExists=/etc/rsyncd.conf

   [Service]
   ExecStart=/usr/bin/nice /usr/bin/rsync --daemon --no-detach

   [Install]
   WantedBy=multi-user.target
   ```
   Enabling and starting it via
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable rsync
   sudo service rsync start
   ```
3. Export the folder you want to backup as `backupsrc` via `rsync`by adding the following to your `/etc/rsyncd.conf`
   ```
   [system]
   path = <backup-path>
   comment = <some comment>
   max connections = 1
   hosts allow = raspberrypi
   hosts deny = *
   use chroot = yes # Don't know what this does
   list = true # Maybe no?
   uid = root # No clue
   gid = root # No clue
   read only = true # Sound's good
   ```
   Maybe you need to restart the rsync daemon afterwards.

## On the raspberry
1. To install the scripts, clone the repository onto the raspberry and make it accessible to root (i.e. clone it into `/root`).
2. Add an entry to your `/etc/fstab` to mount the backup destination to `/root/snapshots`:
   ```
   UUID=<uuid-of-your-backup-drive>  /root/snapshots  ext4  ro,suid,dev,noexec,nouser,async,noauto  0  0
   ```
   You can determine the UUID using `sudo lsblk -o +uuid`.
2. Make the hostname for the machine you want to backup available on your raspberry pi, e.g. by editing your `/etc/hosts`:
   ```
   <ip-address>        backup-client
   ```
3. Create cronjobs which do the backups using `crontab -e` as root:
   ```
   # m h  dom mon dow   command
   # Run an hourly backup every hour.
   0 * * * * /root/backupsrv/take_snapshot.sh --host backup-client --turnus hourly --count 4

   # Use the latest hourly snapshot as a daily snapshot every day at 07:45.
   45 7 * * * /root/backupsrv/rotate_snapshot.sh --host backup-client --turnus daily --count 7 --turnus-fast hourly --count-fast 4

   # Use the latest daily snapshot as weekly snapshot every monday morning at 03:00
   0 3 * * 1 /root/backupsrv/rotate_snapshot.sh --host backup-client --turnus weekly --count 4 --turnus-fast daily --count-fast 7
   ```

Now your raspberry should be setup make rotating backups if your machine is available when the cronjobs execute.

## Providing snapshots to client
Export `/root/snapshots` as read only NFS mount to your backup client and configure your backup client
to mount it someplace, e.g. `/snapshots`.

TODO: Specify

# Reference
The scripts are based on the following articles:

[1]: www.mikerubel.org/computers/rsync_snapshots/ "Mike Rubel - Rsync Snapshots"
[2]: http://jonmoore.duckdns.org/index.php/linux-articles/39-backup-with-rsync-or-dd "Jon Moore - Backup with rsync or dd"
