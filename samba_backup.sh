#!/bin/bash
# samba_backup.sh
# sambaサーバ用backupスクリプト

MAILTO=yourmailaddress@example.com

##################################### 使い方 #######################################################
# $1 sambaサーバのドメインを指定する
# $2 sambaサーバのログインuser名を指定する
# $3 backupを保存する世代を指定
#
# -r [rsyncの転送レート(単位はKB/秒)]
#    例: -r 200 (これで200K/s)
#    -rがない場合は100KB/秒(これで帯域1Mくらいに制限できる)
# -c rsyncで本番サイトのCPU負荷とIO負荷を下げたいときにcを指定する
#    何もない場合はベストエフォートでrsyncが動く
####################################################################################################
# バックアップ方法を指定する(圧縮率はデータによる)
# afz     安全性重視 backupデータが損傷を受けても損傷を受けた場所以外は修復できる 圧縮率85% CPU負荷10% 圧縮時間2倍
#       解凍方法 cd backup/example.com;
#          afio -ivZ /backup/example.com/ctdev.new.afz
#       必要条件:yum install afio
# tar.gz  unix標準 backupデータが損傷を受けるとそれ以降のデータは保証されない 以下tarを使うのは同じ問題をもつ
# tar.7z  圧縮率重視 65%程度 圧縮時間6.5倍 CPU負荷大 メモリー消費74倍(tar.gz比)
#       解凍方法 cd backup/example.com;
#          7za x -so ctdev.new.tar.7z | tar xf -
#       必要条件:yum install p7zip
# tar.bz2 圧縮率は2番目に良い 圧縮時間2.5倍 メモリ消費8倍(tar.gz比)
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

shift `expr $OPTIND - 1`


if [ -z $1 -o -z $2 -o -z $3 ]; then
  echo Usage: $0 [domain] [user] [generation] | mail -s $0 $MAILTO
  exit 1
fi


if [ ! -d $BACKUP_DIR/$1 ]; then
  mkdir -p $BACKUP_DIR/$1
fi

if [ ! -d $RSYNC_DIR/$1 ]; then
  mkdir -p $RSYNC_DIR/$1
fi


# バックアップ時間を保存
find /tmp/ -daystart -mtime -1 -type f -name backuptime | grep backuptime > /dev/null
if [ $? = 0 ]; then
  echo "$1 samba transfer start "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/backuptime
else
  echo "$1 samba transfer start "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` > /tmp/backuptime
fi


# RSYNC
if [ "$rsync_rate_flg" = "TRUE" -a "$rsync_ionice_nice_flg" = "TRUE" ]; then
  rsync -az --bwlimit=$rsync_rate --delete --rsync-path="ionice -c2 -n7 nice -n19 rsync" -e ssh $2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba
elif [ "$rsync_rate_flg" = "TRUE" ]; then
  rsync -az --bwlimit=$rsync_rate --delete -e ssh $2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba
else
  rsync -az --bwlimit=100 --delete -e ssh $2@$1:$SAMBA_DIR/ $RSYNC_DIR/$1/samba
fi


case $ext in

    'tar.gz')
        tar cvzf $BACKUP_DIR/$1/samba.new.$ext $RSYNC_DIR/$1/samba > /dev/null
        ;;

    'tar.bz2')
        tar jcvf $BACKUP_DIR/$1/samba.new.$ext $RSYNC_DIR/$1/samba > /dev/null
        ;;

    'tar.7z')
        tar cf - $RSYNC_DIR/$1/samba | 7za a -si $BACKUP_DIR/$1/samba.new.$ext > /dev/null
        ;;

    'afz')
        find $RSYNC_DIR/$1/samba | afio -oZ $BACKUP_DIR/$1/samba.new.$ext
        ;;

    *)
        echo "$1 samba wrong rsync backup method!" | mail -s $0 $MAILTO
        exit 1
        ;;

esac

# backupに失敗したら管理者にメールして該当データのローテート処理をとばす(データ保護のため)
if [ $? != 0 ]; then
  echo "$1 samba rsync backup samba.new.$ext failure!" | mail -s $0 $MAILTO
  exit 1
fi


# 正常に終了したらローテートする
gens=`expr $3 - 1`

while [ $gens -gt 1 ]; do
  gens=`expr $gens - 1`
  archive=$BACKUP_DIR/$1/samba.$gens.$ext
  if [ -f $archive ]; then
    archive2=$BACKUP_DIR/$1/samba.`expr $gens + 1`.$ext
    mv -f $archive $archive2
  fi
done

archive=$BACKUP_DIR/$1/samba.$ext
if [ -f $archive ]; then
  archive2=$BACKUP_DIR/$1/samba.1.$ext
  mv -f $archive $archive2
fi

# ローテート終了後最新版newを正式名称に変更する
mv -f $BACKUP_DIR/$1/samba.new.$ext $BACKUP_DIR/$1/samba.$ext

echo "$1 samba transfer end "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/backuptime
exit 0
