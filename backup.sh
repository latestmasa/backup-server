#!/bin/bash
# backup.sh

##################################### 使い方 #######################################################
# backupするサイトごとに設定を変更する($5までは必須)
# $1 ドメインを指定する
# $2 本番サーバのログインuser名を指定する
# $3 scp転送レートを指定する(単位はKbit/秒)800くらいでいいかも
# $4 backupを保存する世代を指定
# $5 backupを転送する方法を指定 0:scp 1:rsync
#
# $6 本番サイトのproduction_backup.shのCPUの負荷を下げるには1 CPU負荷が気にならないなら0 なければデフォルトは0扱い
# -r [rsyncの転送レート(単位はKB/秒)]
#    例: -r 200 (これで200K/s)
#    -rがない場合は100KB/秒(これで帯域1Mくらいに制限できる)
# -c rsyncで本番サイトのCPU負荷とIO負荷を下げたいときにcを指定する
#    何もない場合はベストエフォートでrsyncが動く
# -n backup_scriptの名前 一つのサーバに複数のドメイン(サブドメイン)がある場合
#    それぞれのバックアップは別々に行なうためバックアップスクリプトの名前を変
#    更する場合に指定する
#    例 -n example.jp_backup.sh
####################################################################################################

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

shift `expr $OPTIND - 1`


if [ -z $1 -o -z $2 -o -z $3 -o -z $4 -o -z $5 ]; then
  echo Usage: $0 [domain] [user] [scp transfer rate] [generation] [scp:0 or rsync:1] | mail -s $0 root
  exit 1
fi


if [ ! -d $BACKUP_DIR/$1 ]; then
  mkdir -p $BACKUP_DIR/$1
fi

if [ $5 = 1 -a ! -d $RSYNC_DIR/$1 ]; then
  mkdir -p $RSYNC_DIR/$1
fi


while true;
do
  # 本番サイトのバックアップスクリプトを実行
  if [ -z $6 ]; then
    ssh $2@$1 "$production_backup_dir/$backup_script_name" > /dev/null
  elif [ $6 = 0 ]; then
    ssh $2@$1 "$production_backup_dir/$backup_script_name" > /dev/null
  elif [ $6 = 1 ]; then
    ssh $2@$1 "nice -n 19 $production_backup_dir/$backup_script_name" > /dev/null
  else
    ssh $2@$1 "$production_backup_dir/$backup_script_name" > /dev/null
  fi

  if [ $? != 0 ]; then
    ssh_trial=`expr $ssh_trial + 1`

    # 3回まで試行してダメなら諦めて管理者にメール
    if [ $ssh_trial -gt 3 ]; then
      echo "orz $1 ssh in a state of emergency!!" | mail -s $0 root
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
  # 本番サイトのバックアップスクリプトが正常に終了したか確認する
  success_search=`ssh $2@$1 "find backup/$1/ -daystart -mtime -1 -type f -name success"`
  echo $success_search | grep success > /dev/null
  # backupが正常の場合
  if [ $? = 0 ]; then
    echo "$1 production_backup success" > /dev/null
    break
  else
    success_trial=`expr $success_trial + 1`

    # 3回まで試行してダメなら諦めて管理者にメール
    if [ $success_trial -gt 3 ]; then
      echo "orz $1 production_backup failure" | mail -s $0 root
      exit 1
    fi

    sleep 60
    continue
  fi
done


# バックアップ時間を集計
oldifs=$IFS
(IFS=$'\n';
for targettime in `ssh $2@$1 "cat /tmp/$1-backuptime"`; do
  if [ $? != 0 ]; then
    ssh_time_trial=`expr $ssh_time_trial + 1`

    # 3回まで試行してダメなら諦めて管理者にメール
    if [ $ssh_time_trial -gt 3 ]; then
      echo "orz $1 ssh_time in a state of emergency!!" | mail -s $0 root
      exit 1
    fi

    sleep 60
    continue
  else
    # バックアップ時間を保存
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


# 今日保存されたバックアップデータを特定する
for target in `ssh $2@$1 "find backup/$1/ -daystart -mtime -1 -type f ! -regex '.*\.[1-9][0-9]?\..*' ! -name success"`; do
  if [ $? != 0 ]; then
    ssh_find_trial=`expr $ssh_find_trial + 1`

    # 3回まで試行してダメなら諦めて管理者にメール
    if [ $ssh_find_trial -gt 3 ]; then
      echo "orz $1 ssh_find in a state of emergency!!" | mail -s $0 root
      exit 1
    fi

    sleep 60
    continue
  else
    # 保存するターゲットを配列に入れる
    array[$i]=$target
    i=`expr $i + 1`
    dataflg=0
  fi
done

if [ $dataflg = 1 ]; then
  # 今日保存されたバックアップデータが存在しない
  echo "orz $1 There is no backup of today" | mail -s $0 root
  exit 1
fi


echo "$1 transfer start "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/backuptime

for num in ${array[@]};
do
  while :
  do
    # backupするデータの名前と拡張子をとってくる
    name=`echo $num | sed -e "s/.*\/\(.*\)\(.afz\|.tar.gz\|.tar.bz2\|.tar.7z\|.gz\)$/\1/g"`
    ext=`echo $num | sed -e "s/\(.*\)\(afz\|tar.gz\|tar.bz2\|tar.7z\|gz\)$/\2/g"`
    echo $name | grep mysql-dump > /dev/null
    mysqldumpflg=$?

    # SCP
    if [ $5 = 0 ]; then
      # backupしたデータを本番サーバからbackupサーバに転送するscp
      scp -l $3 $2@$1:$num $BACKUP_DIR/$1/$name.new.$ext

    # RSYNC
    elif [ $5 = 1 -a $mysqldumpflg = 0 ]; then
      # mysql-dumpファイルはscpで転送する
      scp -l $3 $2@$1:$num $BACKUP_DIR/$1/$name.new.$ext
    elif [ $5 = 1 -a $mysqldumpflg != 0 ]; then
      # backupしたデータを本番サーバからbackupサーバに転送するrsync
      if [ "$rsync_rate_flg" = "TRUE" -a "$rsync_ionice_nice_flg" = "TRUE" ]; then
        rsync -az --bwlimit=$rsync_rate --delete --rsync-path="ionice -c2 -n7 nice -n19 rsync" --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:/home/htdocs/$1/$name/ $RSYNC_DIR/$1/$name
      elif [ "$rsync_rate_flg" = "TRUE" ]; then
        rsync -az --bwlimit=$rsync_rate --delete --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:/home/htdocs/$1/$name/ $RSYNC_DIR/$1/$name
      else
        rsync -az --bwlimit=100 --delete --exclude '*tmp/sessions/sess_[0-9a-z]*' -e ssh $2@$1:/home/htdocs/$1/$name/ $RSYNC_DIR/$1/$name
      fi

    # ERROR
    else
      echo "orz $1 Plese select scp or rsync" | mail -s $0 root
      exit 1
    fi

    if [ $? != 0 ]; then
      scp_trial=`expr $scp_trial + 1`

      # 3回まで試行してダメなら諦める
      if [ $scp_trial -gt 3 ]; then
        echo "orz $1 scp in a state of emergency!!" | mail -s $0 root
        break
      fi

      sleep 60
      continue
    else
       # rsyncかつmysql-dumpファイルでないものを固める
      if [ $5 = 1 -a $mysqldumpflg != 0 ]; then
        case $ext in

        'tar.gz')
            tar cvzf $BACKUP_DIR/$1/$name.new.$ext $RSYNC_DIR/$1/$name > /dev/null
            ;;

        'tar.bz2')
            tar jcvf $BACKUP_DIR/$1/$name.new.$ext $RSYNC_DIR/$1/$name > /dev/null
            ;;

        'tar.7z')
            tar cf - $RSYNC_DIR/$1/$name | 7za a -si $BACKUP_DIR/$1/$name.new.$ext > /dev/null
            ;;

        'afz')
            find $RSYNC_DIR/$1/$name | afio -oZ $BACKUP_DIR/$1/$name.new.$ext
            ;;

        *)
            echo "$1 wrong rsync backup method!" | mail -s $0 root
            exit 1
            ;;

        esac

        # backupに失敗したら管理者にメールして該当データのローテート処理をとばす(データ保護のため)
        if [ $? != 0 ]; then
          echo "$1 rsync backup $name.new.$ext failure!" | mail -s $0 root
          continue
        fi
      fi

      # 正常に終了したらローテートする
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

      # ローテート終了後最新版newを正式名称に変更する
      mv -f $BACKUP_DIR/$1/$name.new.$ext $BACKUP_DIR/$1/$name.$ext
      echo "$1 $name.$ext rotate success" > /dev/null
      break
    fi
  done
done

echo "$1 transfer end "`date +%Y"-"%m"-"%d" "%H':'%M':'%S` >> /tmp/backuptime
exit 0
