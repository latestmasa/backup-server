# Synopsis

This is a backup script of a fucking server that is not source  
controlled by git  

* Server backup data is created in the backup directory  
  Data that was backed up is not git managed  

* Since it is troublesome to jump for each server simply by local backup on the server  
  Physically back up to another server  

* Because generation generation of backup can be done, old data can also be backed up  
  I can carry as much as the disk allows but I feel like I have 3 to 7  

* You can backup with rsync if you are concerned about server load  
  It is also valid when the data of the server is too large and the transfer amount is wasteful  

* Back up the server so that it does not run out of bandwidth  
  Do not drop user experience  

* run anywhere  

* You can set a different backup method for each server  
  Because you can make production_backup.sh different for each server  

* Even if the line is somewhat unstable try up to 3 backups  

* We will send you an email only when backup can not be taken or abnormally terminated  

cron  

    ############### example.com ###############
    0 0 * * * masa /home/masa/git/backup-server/backup.sh -r 100 example.com ssh_username 900 3 1 0

 Change settings for each site to be backed up

    $1 Specify the domain of the server（with .ssh/config）
    $2 Ssh login user name of production server
    $3 Scp transfer rate
    $4 Specify generation to save backup
    $5 Transfer method  0:scp 1:rsync
    $6 CPU usage 1: Do not worry 0: Sparingly

## Preparation

Assumption that ssh is connected with no password with public key authentication  

#### Backup target server

vim /etc/sudoers  

    #Defaults    requiretty

Leave a comment out  

production_backup.sh  

    # Add unique domain name
    DOMAIN=example.com

    # If there are multiple directories to be saved, use single-byte spaces to separate
    # 例:TARGETS="/home/masa /home/samba"
    TARGETS="/home/htdocs/$DOMAIN/master"

    METHOD=tar.gz
    GENS=3
    BACKUPMETHOD=mysqldump
    DATABASE_NAME="exampledb"
    MYSQLUSER=root
    MYSQLPASSWORD=mysqlrootpassword
    MYSQLSOCK=/var/lib/mysql/mysql.sock
    ionice_flg=0
    BACKUP_DIR=~/backup

Set up the file and keep it ~/backup/production_backup.sh  

>ssh server  
>mkdir backup  
>scp production_backup.sh server:backup/  

When there is a server etc. directly under nut and the backup time is  
long Since the connection is often broken during backup, make the  
following settings on the production server  
vim /etc/ssh/sshd_config  

>ClientAliveInterval 60
>ClientAliveCountMax 60


### backup server

vim backup.sh  

    RSYNC_SERVER_DIR=/home/htdocs/$1
    MAILTO=yourmailaddress@example.com

vim /etc/ssh/ssh_config  

    Host *
            ServerAliveInterval 60

vim /etc/cron.d/backup  

    ############### example.com ###############
    0 0 * * * masa /home/masa/git/backup-server/backup.sh -r 100 example.com ssh_username 900 3 1 0

systemctl cron reload


Backup Time  
cat /tmp/backuptime  

    example.com backup start 2016-06-23 19:41:51
    example.com backup end 2016-06-23 19:41:51
    example.com transfer start 2016-06-23 19:41:53
    example.com transfer end 2016-06-23 19:43:13
	example2.com backup start 2016-06-23 19:45:51
    example2.com backup end 2016-06-23 19:45:57
    example2.com transfer start 2016-06-23 19:45:59
    example2.com transfer end 2016-06-23 19:46:13

Since it is recorded with such feeling, set cron so that it does not wear as much as possible.  
