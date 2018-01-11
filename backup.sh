#!/bin/bash
# backup.sh

RSYNC_SERVER_DIR=/home/htdocs/$1
MAILTO=yourmailaddress@example.com
BACKUP_DIR=${PWD}/backup
RSYNC_DIR=${PWD}/rsync
backup_script_name=production_backup.sh
production_backup_dir=backup
ssh_trial=0
success_trial=0
scp_trial=0
ssh_time_trial=0
ssh_find_trial=0
dataflg=1
i=0


while getopts cr:n: OPT
do
    case $OPT in
	'c') rsync_ionice_nice_flg="TRUE"
             ;;

	'r') rsync_rate_flg="TRUE";
             rsync_rate="$OPTARG"
             ;;

	'n') backup_script_name="$OPTARG"
             ;;

	* ) break
            ;;
    esac
done

shift $(( "$OPTIND" - 1 ))


if [ -z "$1" ] || [ -z "$2" ]  || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
    echo Usage: "$0 [domain] [user] [scp transfer rate] [generation] [scp:0 or rsync:1] | mail -s $0 $MAILTO"
    exit 1
fi


if [ ! -d "$BACKUP_DIR/$1" ]; then
    mkdir -p "$BACKUP_DIR/$1"
fi

if [ "$5" = 1 ] && [ ! -d "$RSYNC_DIR/$1" ]; then
    mkdir -p "$RSYNC_DIR/$1"
fi


while true;
do
    # Run backup script on production site
    if [ -z "$6" ]; then
	ssh "$2@$1 $production_backup_dir/$backup_script_name" > /dev/null
    elif [ "$6" = 0 ]; then
	ssh "$2@$1 $production_backup_dir/$backup_script_name" > /dev/null
    elif [ "$6" = 1 ]; then
	ssh "$2@$1 nice -n 19 $production_backup_dir/$backup_script_name" > /dev/null
    else
	ssh "$2@$1 $production_backup_dir/$backup_script_name" > /dev/null
    fi

    if [ $? != 0 ]; then
	ssh_trial=`expr $ssh_trial + 1`

	if [ $ssh_trial -gt 3 ]; then
	    echo "orz $1 ssh in a state of emergency!!" | mail -s $0 $MAILTO
	    exit 1
	fi

	sleep 60
	continue
    else
	break
    fi
done


while true;
do
    # Confirm whether the backup script of the production site finished successfully
    success_search=`ssh $2@$1 "find backup/$1/ -daystart -mtime -1 -type f -name success"`
    echo $success_search | grep success > /dev/null

    if [ $? = 0 ]; then
	echo "$1 production_backup success" > /dev/null
	break
    else
	success_trial=`expr $success_trial + 1`

	if [ $success_trial -gt 3 ]; then
	    echo "orz $1 production_backup failure" | mail -s $0 $MAILTO
	    exit 1
	fi

	sleep 60
	continue
    fi
done


# Aggregate backup time
oldifs=$IFS
(IFS=$'\n';
 for targettime in `ssh $2@$1 "cat /tmp/$1-backuptime"`; do
     if [ $? != 0 ]; then
	 ssh_time_trial=`expr $ssh_time_trial + 1`

	 if [ $ssh_time_trial -gt 3 ]; then
	     echo "orz $1 ssh_time in a state of emergency!!" | mail -s $0 $MAILTO
	     exit 1
	 fi

	 sleep 60
	 continue
     else

	 find /tmp/ -daystart -mtime -1 -type f -name backuptime | grep backuptime > /dev/null
	 if [ $? = 0 ]; then
	     echo "$targettime" >> /tmp/backuptime
	 else
	     echo "$targettime" > /tmp/backuptime
	 fi
     fi
 done
)
IFS=$oldifs


for target in `ssh $2@$1 "find backup/$1/ -daystart -mtime -1 -type f ! -regex '.*\.[1-9][0-9]?\..*' ! -name success"`; do
    if [ $? != 0 ]; then
	ssh_find_trial=`expr $ssh_find_trial + 1`

	if [ $ssh_find_trial -gt 3 ]; then
	    echo "orz $1 ssh_find in a state of emergency!!" | mail -s $0 $MAILTO
	    exit 1
	fi

	sleep 60
	continue
    else
	array[$i]=$target
	i=`expr $i + 1`
	dataflg=0
    fi
done

if [ $dataflg = 1 ]; then
    echo "orz $1 There is no backup of today" | mail -s $0 $MAILTO
    exit 1
fi

datetime=$(date +%Y-%m-%d-%H:%M:%S)
echo "$1 transfer start "$datetime >> /tmp/backuptime

for num in "${array[@]}";
do
    while :
    do
	name=`echo $num | sed -e "s/.*\/\(.*\)\(.afz\|.tar.gz\|.tar.bz2\|.tar.7z\|.gz\)$/\1/g"`
	ext=`echo $num | sed -e "s/\(.*\)\(afz\|tar.gz\|tar.bz2\|tar.7z\|gz\)$/\2/g"`
	echo $name | grep mysql-dump > /dev/null
	mysqldumpflg=$?

	# SCP
	if [ $5 = 0 ]; then
	    scp -l $3 $2@$1:$num $BACKUP_DIR/$1/$name.new.$ext

	    # RSYNC
	elif [ $5 = 1 ] && [ $mysqldumpflg = 0 ]; then
	    scp -l $3 $2@$1:$num $BACKUP_DIR/$1/$name.new.$ext
	elif [ $5 = 1 ] && [ $mysqldumpflg != 0 ]; then
	    if [ "$rsync_rate_flg" = "TRUE" ] && [ "$rsync_ionice_nice_flg" = "TRUE" ]; then
		rsync -az --bwlimit=$rsync_rate --delete --rsync-path="ionice -c2 -n7 nice -n19 rsync" --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:$RSYNC_SERVER_DIR/ $RSYNC_DIR/$1/
	    elif [ "$rsync_rate_flg" = "TRUE" ]; then
		rsync -az --bwlimit=$rsync_rate --delete --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:$RSYNC_SERVER_DIR/ $RSYNC_DIR/$1/
	    else
		rsync -az --bwlimit=100 --delete --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:$RSYNC_SERVER_DIR/ $RSYNC_DIR/$1/
	    fi

	    # ERROR
	else
	    echo "orz $1 Plese select scp or rsync" | mail -s $0 $MAILTO
	    exit 1
	fi

	if [ $? != 0 ]; then
	    scp_trial=`expr $scp_trial + 1`

	    if [ $scp_trial -gt 3 ]; then
		echo "orz $1 scp in a state of emergency!!" | mail -s $0 $MAILTO
		break
	    fi

	    sleep 60
	    continue
	else
	    if [ $5 = 1 ] && [ $mysqldumpflg != 0 ]; then
		case $ext in

		    'tar.gz')
			tar cvzf $BACKUP_DIR/$1/$name.new.$ext $RSYNC_DIR/$1 > /dev/null
			;;

		    'tar.bz2')
			tar jcvf $BACKUP_DIR/$1/$name.new.$ext $RSYNC_DIR/$1 > /dev/null
			;;

		    'tar.7z')
			tar cf - $RSYNC_DIR/$1 | 7za a -si $BACKUP_DIR/$1/$name.new.$ext > /dev/null
			;;

		    'afz')
			find $RSYNC_DIR/$1 | afio -oZ $BACKUP_DIR/$1/$name.new.$ext
			;;

		    *)
			echo "$1 wrong rsync backup method!" | mail -s $0 $MAILTO
			exit 1
			;;

		esac

		# If backup fails, e-mail the administrator and skip the rotation process of the corresponding data
		if [ $? != 0 ]; then
		    echo "$1 rsync backup $name.new.$ext failure!" | mail -s $0 $MAILTO
		    continue
		fi
	    fi

	    # Rotate after completing normally
	    gens=`expr $4 - 1`

	    while [ $gens -gt 1 ]; do
		gens=`expr $gens - 1`
		archive=$BACKUP_DIR/$1/$name.$gens.$ext
		if [ -f $archive ]; then
		    archive2=$BACKUP_DIR/$1/$name.`expr $gens + 1`.$ext
		    mv -f $archive $archive2
		fi
	    done

	    archive=$BACKUP_DIR/$1/$name.$ext
	    if [ -f $archive ]; then
		archive2=$BACKUP_DIR/$1/$name.1.$ext
		mv -f $archive $archive2
	    fi

	    mv -f $BACKUP_DIR/$1/$name.new.$ext $BACKUP_DIR/$1/$name.$ext
	    echo "$1 $name.$ext rotate success" > /dev/null
	    break
	fi
    done
done

backuptime=$(date +%Y-%m-%d-%H:%M:%S)
echo "$1 transfer end "$backuptime >> /tmp/backuptime
exit 0
