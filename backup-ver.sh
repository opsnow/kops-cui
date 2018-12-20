#!/bin/bash

SHELL_DIR=$(dirname $0)

if [ ! -f $SHELL_DIR/versions ]; then
    echo "Need a versions file"
    exit 0
fi

. ${SHELL_DIR}/common.sh
. ${SHELL_DIR}/default.sh

BACKUP_DIR=$1

if [ -z $BACKUP_DIR ]; then
    BACKUP_DIR=$SHELL_DIR
fi
echo "Backup charts to $BACKUP_DIR"
$(cp -rf charts $BACKUP_DIR)

CHART_LIST=$(cat $SHELL_DIR/versions)

#echo $CHART_LIST

# 한줄씩 읽어서
# 설치된 버전 ver1
# yaml 파일을 찾아서
# ver1 로 replace
while read LINE; do

    # get chart name
    chart_name=$(echo $LINE | awk '{print $1}')

    # get_build_ver
    ver1=$(echo $LINE | awk '{print $2}'| rev | cut -d'-' -f1 | rev)

    # confirm chart version
    echo "BUILD VER : " $chart_name $ver1

    #find file
    file=$(find $BACKUP_DIR -name "$chart_name.yaml")

    echo "FILE      : " $file

    if [ -z $file ]; then
        # no file
        echo "Not found file : $file"
        continue;
    fi
    # found file
    prefix="# chart-version: "
    echo "REPLACE   : " "$prefix$ver1"
    _replace "s/$prefix.*/$prefix$ver1/g" $file

    echo "============================="
	
done < $SHELL_DIR/versions


