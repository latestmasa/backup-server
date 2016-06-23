#### Synopsis

* backup ディレクトリにサーバのバックアップデータが生成される  
* backup の世代管理ができるので古いデータもバックアップしておける  
* サーバーに負荷が気になる場合 rsync でバックアップできる  
* サーバの帯域を使い切らないようにバックアップする  


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

#### バックアップ対象サーバー
vim /etc/sudoers  

    #Defaults    requiretty

コメントアウトしておく  

バックアップ対象サーバーに  
~/backup/production_backup.sh  
ファイルを設定して置いておく  

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
