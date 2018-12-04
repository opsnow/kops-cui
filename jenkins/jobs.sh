#!/bin/bash

SHELL_DIR=$(dirname $0)

PARENT_DIR=$(dirname ${SHELL_DIR})

. ${PARENT_DIR}/default.sh
. ${PARENT_DIR}/common.sh

################################################################################

CHART=${1:-${PARENT_DIR}/build/${THIS_NAME}-jenkins.yaml}
CHART_TMP=${PARENT_DIR}/build/${THIS_NAME}-jenkins-tmp.yaml

TMP_DIR=${PARENT_DIR}/build/${THIS_NAME}-jenkins

rm -rf ${TMP_DIR} ${CHART_TMP} && mkdir -p ${TMP_DIR}

# job list
JOB_LIST=${PARENT_DIR}/build/${THIS_NAME}-jenkins-job-list

ls ${SHELL_DIR}/jobs/ > ${JOB_LIST}

while read JOB; do
    mkdir -p ${TMP_DIR}/${JOB}

    ORIGIN=${SHELL_DIR}/jobs/${JOB}/Jenkinsfile

    TARGET=${TMP_DIR}/${JOB}/Jenkinsfile
    CONFIG=${TMP_DIR}/${JOB}/config.xml

    # Jenkinsfile
    if [ -f ${ORIGIN} ]; then
        cp -rf ${ORIGIN} ${TARGET}
        _replace "s/\"/\&quot;/g" ${TARGET}
        _replace "s/</\&lt;/g" ${TARGET}
        _replace "s/>/\&gt;/g" ${TARGET}
    else
        touch ${TARGET}
    fi

    # Jenkinsfile >> config.xml
    while read LINE; do
        if [ "${LINE}" == "REPLACE" ]; then
            cat ${TARGET} >> ${CONFIG}
        else
            echo "${LINE}" >> ${CONFIG}
        fi
    done < ${SHELL_DIR}/jobs/${JOB}/config.xml
done < ${JOB_LIST}

# config.yaml >> jenkins.yaml
POS=$(grep -n "jenkins-jobs -- start" ${CHART} | cut -d':' -f1)

sed "${POS}q" ${CHART} >> ${CHART_TMP}

echo
echo "  Jobs:" >> ${CHART_TMP}

while read JOB; do
    echo "> ${JOB}"
    echo "    ${JOB}: |-" >> ${CHART_TMP}

    sed -e "s/^/      /" ${TMP_DIR}/${JOB}/config.xml >> ${CHART_TMP}
done < ${JOB_LIST}

sed "1,${POS}d" ${CHART} >> ${CHART_TMP}

# done
cp -rf ${CHART_TMP} ${CHART}
