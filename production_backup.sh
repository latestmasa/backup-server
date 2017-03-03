#!/bin/bash
# production_backup.sh
# Put this file on the backup target server only
# Set this file at ssh login user's ~/backup/production_backup.sh

MAILTO=yourmailaddress@example.com
DOMAIN=example.com
TARGETS="/home/htdocs/$DOMAIN/master"
METHOD=tar.gz
GENS=3
BACKUPMETHOD=mysqldump
DATABASE_NAME="exampledb"
# Specify root to save multiple databases
MYSQLUSER=root
MYSQLPASSWORD=mysqlrootpassword
MYSQLSOCK=/var/lib/mysql/mysql.sock
# Restore method
# gzip -d mysql-dump_exampledb.gz
# mysql --user=root --password=mysqlrootpassword \
#        --socket=/var/lib/mysql/mysql.sock \
#        exampledb < mysql-dump_exampledb
ionice_flg=0
BACKUP_DIR=~/backup


echo "${DOMAIN} backup start "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` > /tmp/${DOMAIN}-backuptime

if [ ! -d $BACKUP_DIR/$DOMAIN ]; then
  mkdir -p $BACKUP_DIR/$DOMAIN
fi

if [ $ionice_flg = 1 ]; then
  ionice -c2 -n7 -p$$
elif [ $ionice_flg = 2 ]; then
  sudo ionice -c3 -p$$
fi

for target in $TARGETS; do
  name=`basename $target`
  case $METHOD in
  'tar.gz')
          tar cvzf $BACKUP_DIR/$DOMAIN/$name.new.$METHOD $target > /dev/null
          ;;

  'tar.bz2')
          tar jcvf $BACKUP_DIR/$DOMAIN/$name.new.$METHOD $target > /dev/null
          ;;

  'tar.7z')
          tar cf - $target | 7za a -si $BACKUP_DIR/$DOMAIN/$name.new.$METHOD > /dev/null
          ;;

  'afz')
          find $target | afio -oZ $BACKUP_DIR/$DOMAIN/$name.new.$METHOD
          ;;

  *)
          echo "$DOMAIN wrong backup method!" | mail -s $0 $MAILTO
          exit 1
          ;;

  esac

  # If backup fails, e-mail the administrator and skip the rotation process of the corresponding data
  if [ $? != 0 ]; then
    echo "$DOMAIN backup $name.new.$METHOD failure!" | mail -s $0 $MAILTO
    continue
  fi

  # Rotate after backup completes normally
  i=`expr $GENS - 1`
  while [ $i -gt 1 ]; do
    i=`expr $i - 1`
    archive=$BACKUP_DIR/$DOMAIN/$name.$i.$METHOD
    if [ -f $archive ]; then
      archive2=$BACKUP_DIR/$DOMAIN/$name.`expr $i + 1`.$METHOD
      mv -f $archive $archive2
    fi
  done

  archive=$BACKUP_DIR/$DOMAIN/$name.$METHOD
  if [ -f $archive ]; then
    archive2=$BACKUP_DIR/$DOMAIN/$name.1.$METHOD
    mv -f $archive $archive2
  fi

  mv -f $BACKUP_DIR/$DOMAIN/$name.new.$METHOD $BACKUP_DIR/$DOMAIN/$name.$METHOD
done


for dbtarget in $DATABASE_NAME; do
  case $BACKUPMETHOD in
    'mysqldump')
             mysqldump --user=$MYSQLUSER --password=$MYSQLPASSWORD \
              --socket=$MYSQLSOCK \
              --single-transaction \
              --master-data=2 \
              --flush-logs \
              --all-databases | gzip > $BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.new.gz
            ;;

    *)
            echo "$DOMAIN wrong mysql backup method!" | mail -s $0 $MAILTO
            exit 1
            ;;

  esac


  # If mysqlbackup fails, e-mail the administrator and skip the rotation process of the corresponding data
  if [ $? != 0 ]; then
    case $BACKUPMETHOD in
      'mysqldump')
            echo "$DOMAIN mysql backup mysql-dump_$dbtarget.new.gz failure!" | mail -s $0 $MAILTO
            continue
            ;;

      *)
            echo "$DOMAIN wrong mysql backup method!" | mail -s $0 $MAILTO
            exit 1
            ;;

    esac
  fi


  # Rotate after backup completes normally
  i=`expr $GENS - 1`
  while [ $i -gt 1 ]; do
    i=`expr $i - 1`
    archive=$BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.$i.gz
    if [ -f $archive ]; then
      archive2=$BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.`expr $i + 1`.gz
      mv -f $archive $archive2
    fi
  done

  archive=$BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.gz
  if [ -f $archive ]; then
    archive2=$BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.1.gz
    mv -f $archive $archive2
  fi

  # After the rotation is completed, change the latest version new to the official name
  mv -f $BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.new.gz $BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.gz
done

# Mark if it ends normally
touch $BACKUP_DIR/$DOMAIN/success

echo "${DOMAIN} backup end "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/${DOMAIN}-backuptime
exit 0
