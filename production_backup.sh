#!/bin/bash
# production_backup.sh 本番サーバー用
# このファイルだけbackup対象サーバに置く
# サーバごとに違う設定になるのでサーバーごとに設置する
# sshログインユーザーの
# ~/backup/production_backup.sh に置く

##################################### 設定ファイル #######################################################
MAILTO=yourmailaddress@example.com
# 一意なドメイン名をつける
DOMAIN=example.com

# 保存したいディレクトリが複数ある場合は半角スペースで区切る
# 例:TARGETS="/home/masa /home/samba"
TARGETS="/home/htdocs/$DOMAIN/master"

# バックアップ方法を指定する(圧縮率はデータによる)
# afz     安全性重視 backupデータが損傷を受けても損傷を受けた場所以外は修復できる 圧縮率85% CPU負荷10% 圧縮時間2倍
#       解凍方法 cd backup/example.com;
#          afio -ivZ /backup/example.com/dev.new.afz
#       必要条件:yum install afio ; yaourt afio
# tar.gz  unix標準 backupデータが損傷を受けるとそれ以降のデータは保証されない 以下tarを使うのは同じ問題をもつ
# tar.7z  圧縮率重視 65%程度 圧縮時間6.5倍 CPU負荷大 メモリー消費74倍(tar.gz比)
#       解凍方法 cd backup/example.com;
#          7za x -so dev.new.tar.7z | tar xf -
#       必要条件:yum install p7zip ; pacman -S p7zip
# tar.bz2 圧縮率は2番目に良い 圧縮時間2.5倍 メモリ消費8倍(tar.gz比)
METHOD=tar.gz

# backupを保存する世代を指定
GENS=3


# mysqlbackupの設定
BACKUPMETHOD=mysqldump
# 保存したいデータベースが複数ある場合は半角スペースで区切る
# 例:DATABASE_NAME="exampledb exampledbdev"
DATABASE_NAME="exampledb"
# 複数のデータベースを保存するならrootを指定
MYSQLUSER=root
MYSQLPASSWORD=mysqlrootpassword
MYSQLSOCK=/var/lib/mysql/mysql.sock
# リストア方法
# gzip -d mysql-dump_exampledb.gz
# mysql --user=root --password=mysqlrootpassword \
#        --socket=/var/lib/mysql/mysql.sock \
#        exampledb < mysql-dump_exampledb


# サーバのIO負荷が高い場合はこれを変更する(バックアップは遅くなるので注意)
# 0  IOベストエフォート
# 1  一般ユーザの権限でもっともIOの負荷が少ない設定
# 2  IOがアイドル時だけバックアップが走る(root権限が必要)
ionice_flg=0

# ここを変更するならbackup.shの$production_backup_dirも変更する
BACKUP_DIR=~/backup
##########################################################################################################

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

  # backupに失敗したら管理者にメールして該当データのローテート処理をとばす(データ保護のため)
  if [ $? != 0 ]; then
    echo "$DOMAIN backup $name.new.$METHOD failure!" | mail -s $0 $MAILTO
    continue
  fi

  # backupが正常に終了したらローテートする
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

  # ローテート終了後最新版newを正式名称に変更する
  mv -f $BACKUP_DIR/$DOMAIN/$name.new.$METHOD $BACKUP_DIR/$DOMAIN/$name.$METHOD
done


# ここからMysqlバックアップ
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


  # mysqlbackupに失敗したら管理者にメールして該当データのローテート処理をとばす(データ保護のため)
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


  # backupが正常に終了したらローテートする
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

  # ローテート終了後最新版newを正式名称に変更する
  mv -f $BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.new.gz $BACKUP_DIR/$DOMAIN/mysql-dump_$dbtarget.gz
done

# 正常終了したら印をつける
touch $BACKUP_DIR/$DOMAIN/success

echo "${DOMAIN} backup end "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/${DOMAIN}-backuptime
exit 0
