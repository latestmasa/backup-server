#!/bin/bash
# samba_backup.sh

MAILTO=yourmailaddress@example.com
# $1 samba domain
# $2 samba server's ssh login user
# $3 Specify generation to save backup
ext=tar.gz
BACKUP_DIR=${PWD}/backup
RSYNC_DIR=${PWD}/rsync
SAMBA_DIR=/home/samba

while getopts cr: OPT
do
    case $OPT in
	'c') rsync_ionice_nice_flg="TRUE"
             ;;

	'r') rsync_rate_flg="TRUE";
             rsync_rate="$OPTARG"
             ;;

	* ) break
            ;;
    esac
done
shift $(( "$OPTIND" - 1 ))

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 [domain] [user] [generation] | mail -s $0 $MAILTO"
    exit 1
fi

if [ ! -d "$BACKUP_DIR/$1" ]; then
    mkdir -p "$BACKUP_DIR/$1"
fi

if [ ! -d "$RSYNC_DIR/$1" ]; then
    mkdir -p "$RSYNC_DIR/$1"
fi

# Save backup time
find /tmp/ -daystart -mtime -1 -type f -name backuptime | grep backuptime > /dev/null
if [ $? = 0 ]; then
    echo "$1 samba transfer start $(date +%Y-%m-%d-%H:%M:%S)" >> /tmp/backuptime
else
    echo "$1 samba transfer start $(date +%Y-%m-%d-%H:%M:%S)" > /tmp/backuptime
fi

# RSYNC
if [ "$rsync_rate_flg" = "TRUE" ] && [ "$rsync_ionice_nice_flg" = "TRUE" ]; then
    rsync -az --bwlimit="$rsync_rate" --delete --rsync-path="ionice -c2 -n7 nice -n19 rsync" -e ssh "$2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba"
elif [ "$rsync_rate_flg" = "TRUE" ]; then
    rsync -az --bwlimit="$rsync_rate" --delete -e ssh "$2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba"
else
    rsync -az --bwlimit=100 --delete -e ssh "$2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba"
fi

case $ext in

    'tar.gz')
        tar cvzf "$BACKUP_DIR/$1/samba.new.$ext $RSYNC_DIR/$1/samba > /dev/null"
        ;;

    'tar.bz2')
        tar jcvf "$BACKUP_DIR/$1/samba.new.$ext $RSYNC_DIR/$1/samba > /dev/null"
        ;;

    'tar.7z')
        tar cf - "$RSYNC_DIR/$1/samba | 7za a -si $BACKUP_DIR/$1/samba.new.$ext > /dev/null"
        ;;

    'afz')
        find "$RSYNC_DIR/$1/samba | afio -oZ $BACKUP_DIR/$1/samba.new.$ext"
        ;;

    *)
        echo "$1 samba wrong rsync backup method!" | mail -s "$0 $MAILTO"
        exit 1
        ;;

esac

# If backup fails, e-mail the administrator and skip the rotation process of the corresponding data
if [ $? != 0 ]; then
    echo "$1 samba rsync backup samba.new.$ext failure!" | mail -s "$0 $MAILTO"
    exit 1
fi

# Rotate after completing normally
gens=$(( $3 - 1 ))

while [ $gens -gt 1 ]; do
    gens=$(( "$gens" - 1 ))
    archive=$BACKUP_DIR/$1/samba.$gens.$ext
    if [ -f "$archive" ]; then
	archive2=$BACKUP_DIR/$1/samba.$(( "$gens" + 1 )).$ext
	mv -f "$archive $archive2"
    fi
done

archive=$BACKUP_DIR/$1/samba.$ext
if [ -f "$archive" ]; then
    archive2=$BACKUP_DIR/$1/samba.1.$ext
    mv -f "$archive $archive2"
fi

mv -f "$BACKUP_DIR/$1/samba.new.$ext $BACKUP_DIR/$1/samba.$ext"

echo "$1 samba transfer end $(date +%Y-%m-%d-%H:%M:%S)" >> /tmp/backuptime
exit 0
