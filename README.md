#Backup-download - script to download backups from remote servers with logging to MySQL DB and Zabbix monitor template.

Main functions of this script:
-download backups from remote servers.It can be done via SCP or RSYNC.
-send alerts and errors to LOG-file and Telegram when ran from CRON env.
-write download logs to MySQL database.Then the status of jobs done can be determinied by another script.

This system means that you have somewhere on remote server some folder where backups are stored.Logically and physically they are divided into two types:
Daily backups and Weekly backups.Also, there must be such two folder inside you main folder.
For example: 
-main folder is "/home/backup"
-there are two folders inside: "/home/backup/daily" and "/home/backup/weekly".
Also, this script for download is related to the other one - backup.sh which lays nearby. You can use that script on the remote side to properly create backups, 
and backup-download.sh script to download them.
All backups are begin created in subfolders according to its type - daily backup is in daily folder.Weekyly - in weekly folder.
Format of the name of the backup's folder is a date - for ex. 23.07.2023. Backup-download script looking into the today's date named folder
while trying to download backups.
Example:
for download today's backup when today is 23.07.2023, we need to have the next structure(in case of SCP):
1)Today is 23.07.2023
2)Remote side has:
/home/backup/daily/23.07.2023/<files here>
3)This script is launched with "daily" parameter.So it is heading to remote server to /home/backup/daily/23.07.2023/ and download all from there to local
folder from $backupsFolder value + domain name of server + type (Daily/Weekly) + current date.
Ex.: /media/storage/server.com/daily/23.07.2023
In case of Rsync, the script takes $remRsyncFolder value and syncing it to the local $backupsFolder/$domain/Weekly folder.

This script determines the environment it's launched in. If it is shell env. - the script shows up all alerts and work logs to console.
If it is launched in CRON env. - it creates LOG-file and place all messages in it.
-If Telegram settings are set in .local file - error messages are being sent to Telegram,not only to LOG.
-If MySQL settings are set - the results of jobs done are being written to the DB.

At the first launch of backup-download.sh script, it will create backup-download.local file.It consists important settings for general work.All settings in there
have comments with explanation what do they do.
At the second launch - the script will generate backup-download.list file.It consists settings of remote servers. It has next format:

<hostname> <dnsname> <type> <dailyType> <weeklyType> <remScpDir> <scpUser> <remRsyncDir> <rsyncUser>
<hostname>    - Name of a host which is used as folder name on backup server and in log messages.
<dnsname>     - DNS or IP address of the host. Just for connections.
<type>        - What we can do with that host - download "all" (daily and weekly), or only "daily" or "weekly" backups.
<dailyType>   - How to do daily downloads: via "scp" or "rsync".
<weeklyType>  - How to do weekly downloads: via "scp" or "rsync".
<remScpDir>   - Remote directory with backups. For example: /home/backup. Inside os this dir. must be folders "daily" and "weekly" with backups.
<scpUser>     - Username for SCP connection.
<remRsyncDir> - Remote directory to be fully synced with a local one.Can be ignored if not use Rsync.
<rsyncUser>   - Username for Rsync connection. If not set, scpUser's value will be used.Can be ignored if not use Rsync.
Example:
cloudserver1.infra clo01phx0.domain.com all scp scp home/backup bckp 
cloudserver2.infra clo01phx1.domain.com all scp rsync home/backup bckp /var/www root

#Backup.sh - script to create local backups of DB and folders.

The script uses shared settings.local file to get all necessary settings, and his own file with settings of points need to be backed up.
The file named backup.list. It has simple format:
<type>: <value> where:
<type> should be: "db:" or "backup:"
<value> - a path to folder for backup, or name of DB to backup. Path must be without / at the end.
example:
db: siteDatabase
backup: /var/www

You can create personal dumps of MySQL databases via "db:" option, or an archived copy of some folder with subfolders via "site:" option.
Important moment - "site:" backups are created only when "weekly" type is selected.In "daily" there are only "db:" backups being made.
All files are stored in $backupLocalFolder in subfolder according the type of launch - daily or weekly.

In settings.local there are few personal options for backup.sh:
localBackupsFolder - local folder where backups will be stored.Inside this folder will be "daily" and "weekly" folders
uid - user to make an owner of the files
gid - group to make an owner of the files
