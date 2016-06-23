#### Synopsis

* backup ディレクトリにサーバのバックアップデータが生成される  
  backup されたデータは git 管理されない  
* backup の世代管理ができるので古いデータもバックアップしておける  
  ディスクの許す限り持っておけるが 3 〜 7 あればいい気がする  
* サーバーに負荷が気になる場合 rsync でバックアップできる  
  サーバのデータがでかすぎて転送量がもったいない場合にも有効  
* サーバの帯域を使い切らないようにバックアップする  
  ユーザーエクスペリエンスを落としてはいけない  
* coreutils と bash と ssh くらいしか依存しないのでどのサーバーでも動く  
  run anywhere  
* サーバーごとに違うバックアップメソッドを設定できる  
  production_backup.sh をサーバごとに違うファイルにできるため  
* 回線が多少不安定でも backup を 3 回まで試行するので  
  普通の家庭の回線でも問題ない。  

cron にこんな感じで書いておく

    ############### example.com ###############
    0 0 * * * masa /backup/backup.sh -r 100 example.com ssh_username 900 3 1 0

 backup するサイトごとに設定を変更する($5 までは必須)
 
    $1 サーバのドメインを指定する（.ssh/config に書かれたドメイン）
    $2 本番サーバの ssh ログイン user 名
    $3 scp 転送レート (単位は Kbit/秒) サーバの帯域を使い切らないように
    $4 backup を保存する世代を指定
    $5 backup を転送する方法を指定 0:scp 1:rsync
    $6 本番サイトの CPU の負荷を下げるには 1 CPU 負荷が気にならないなら 0 なければデフォルトは 0 扱い
 
    -r [rsync の転送レート(単位は KB/秒)]
    例: -r 200 (これで 200K/s)
	
    -r がない場合は 100KB/秒(これで帯域 1M くらいに制限できる)
	
    -c rsync で本番サイトの CPU 負荷と IO 負荷を下げたいときに c を指定する
    何もない場合はベストエフォートで rsync が動く
	
    -n backup_script の名前 一つのサーバに複数のドメイン(サブドメイン)がある場合
    それぞれのバックアップは別々に行なうためバックアップスクリプトの名前を変
    更する場合に指定する
    例 -n example.jp_backup.sh


# 準備

ssh が公開鍵認証でパスワード無しで接続しているのが前提  

#### バックアップ対象サーバー
vim /etc/sudoers  

    #Defaults    requiretty

コメントアウトしておく  

バックアップ対象サーバーに  
~/backup/production_backup.sh  
ファイルを設定して置いておく  

production_backup.sh の設定ファイルを設定  
-------------------- 設定ファイル ---------------------

    # 一意なドメイン名をつける
    DOMAIN=example.com

    # 保存したいディレクトリが複数ある場合は半角スペースで区切る
    # 例:TARGETS="/home/masa /home/samba"
    TARGETS="/home/htdocs/$DOMAIN/master"

    # バックアップ方法を指定する(圧縮率はデータによる)
    # afz     安全性重視 backup データが損傷を受けても損傷を受けた場所以外は修復できる 圧縮率 85% CPU 負荷 10% 圧縮時間 2 倍
    #       解凍方法 cd backup/example.com;
    #          afio -ivZ /backup/example.com/dev.new.afz
    #       必要条件:yum install afio ; yaourt afio
    # tar.gz  unix 標準 backup データが損傷を受けるとそれ以降のデータは保証されない 以下 tar を使うのは同じ問題をもつ
    # tar.7z  圧縮率重視 65%程度 圧縮時間 6.5 倍 CPU 負荷大 メモリー消費 74 倍(tar.gz 比)
    #       解凍方法 cd backup/example.com;
    #          7za x -so dev.new.tar.7z | tar xf -
    #       必要条件:yum install p7zip ; pacman -S p7zip
    # tar.bz2 圧縮率は 2 番目に良い 圧縮時間 2.5 倍 メモリ消費 8 倍(tar.gz 比)
    METHOD=tar.gz

    # backup を保存する世代を指定
    GENS=3


    # mysqlbackup の設定
    BACKUPMETHOD=mysqldump
    # 保存したいデータベースが複数ある場合は半角スペースで区切る
    # 例:DATABASE_NAME="exampledb exampledbdev"
    DATABASE_NAME="exampledb"
    # 複数のデータベースを保存するなら root を指定
    MYSQLUSER=root
    MYSQLPASSWORD=mysqlrootpassword
    MYSQLSOCK=/var/lib/mysql/mysql.sock
    # リストア方法
    # gzip -d mysql-dump_exampledb.gz
    # mysql --user=root --password=mysqlrootpassword \
    #        --socket=/var/lib/mysql/mysql.sock \
    #        exampledb < mysql-dump_exampledb


    # サーバの IO 負荷が高い場合はこれを変更する(バックアップは遅くなるので注意)
    # 0  IO ベストエフォート
    # 1  一般ユーザの権限でもっとも IO の負荷が少ない設定
    # 2  IO がアイドル時だけバックアップが走る(root 権限が必要)
    ionice_flg=0

    # ここを変更するなら backup.sh の$production_backup_dir も変更する
    BACKUP_DIR=~/backup

-------------------------------------------------------------------------


nut 直下にサーバなどがあってバックアップ時間が長い場合  
バックアップ中に接続が切れることが多いので本番サーバに以下の設定をしておく  
vim /etc/ssh/sshd_config  

>ClientAliveInterval 60
>ClientAliveCountMax 60


### backup を置いておくサーバ

ssh の設定  
vim /etc/ssh/ssh_config  

    Host *
            ServerAliveInterval 60

ssh でドメイン名解決するので  
vim ~/.ssh/config  

     Host example.com
                            HostName IP アドレス
                            User ユーザー名

を書いておく  


cron を設定する
vim /etc/cron.d/backup  

    ############### example.com ###############
    0 0 * * * masa /backup/backup.sh -r 100 example.com ssh_username 900 3 1 0

systemctl cron reload
