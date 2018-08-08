#!/bin/bash

SHELL_DIR=$(dirname $0)

CHART=${1:-/tmp/jenkins.yaml}

TMP_DIR=/tmp/jenkins
JOB_DIR=${TMP_DIR}/jobs
FILE_DIR=${TMP_DIR}/files

rm -rf ${TMP_DIR}
mkdir -p ${JOB_DIR} ${FILE_DIR}

JOBS=${TMP_DIR}/jobs.txt
ls ${SHELL_DIR}/files/ > ${JOBS}

while read VAL; do
    ORIGIN=${SHELL_DIR}/files/${VAL}/Jenkinsfile
    FILE=${FILE_DIR}/${VAL}
    JOB=${JOB_DIR}/${VAL}.xml

    if [ -f ${ORIGIN} ]; then
        cp -rf ${ORIGIN} ${FILE}
        sed -i -e "s/\"/\&quot;/g" ${FILE}
    else
        touch ${FILE}
    fi

    while read LINE; do
        if [ "${LINE}" == "REPLACE" ]; then
            cat ${FILE} >> ${JOB}
        else
            echo "${LINE}" >> ${JOB}
        fi
    done < ${SHELL_DIR}/files/${VAL}/job.xml
done < ${JOBS}

ls ${JOB_DIR} | grep "[.]xml" > ${JOBS}

echo "  Jobs: |-" >> ${CHART}
while read VAL; do
    JOB=${VAL%.*l}
    echo "${VAL}"
    echo "    ${JOB}: |-" >> ${CHART}
    while read LINE; do
        echo "      ${LINE}" >> ${CHART}
    done < ${JOB_DIR}/${VAL}
done < ${JOBS}
