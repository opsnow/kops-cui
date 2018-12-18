#!/bin/bash

SHELL_DIR=$(dirname $0)

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
# yaml 에 명시된 버전 ver2
# ver2 를 ver1 로 replace
while read LINE; do

    # get chart name
	chart_name=$(echo $LINE | awk '{print $1}')

    # get_build_ver
    ver1=$(echo $LINE | awk '{print $2}'| rev | cut -d'-' -f1 | rev)

    # confirm chart version
    echo "BUILD : " $chart_name $ver1

    #find file
    file=$(find $BACKUP_DIR -name "$chart_name.yaml")

    echo "FILE  : " $file

    if [ -z $file ]; then
        # no file
        continue;
    fi
    # found file
    # get_input_ver
    ver2=$(cat $file | grep chart-version | awk '{print $3}')

    echo "YAML  : " $ver2

    prefix="# chart-version: "
    if [ $ver2 == "latest" ]; then
        echo "CMD   : " "sed -i -e 's/$prefix$ver2/$prefix$ver1/g' $file"
        sed -i -e "s/$prefix$ver2/$prefix$ver1/g" $file
    fi

    echo "============================="
	
done < $SHELL_DIR/versions


