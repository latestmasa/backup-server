#/bin/bash
# sshログインできないサーバーのhtmlをbackup
DOMAIN='exaple.com'
cd ${PWD}/backup
wget -rpkK -l3 --output-file=/dev/null http://${DOMAIN}/
