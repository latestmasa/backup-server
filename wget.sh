#!/bin/bash
# Ssh can not login html of server
DOMAIN=$1
cd "${PWD}/backup" || exit
wget -rpkK -l3 --output-file=/dev/null "http://${DOMAIN}/"
