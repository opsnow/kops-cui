#!/bin/bash

SHELL_DIR=$(dirname $0)

CHART=${1:-/tmp/kops-cui-jenkins.yaml}

TMP_DIR=/tmp/kops-cui-jenkins

JOBS_DIR=${TMP_DIR}/jobs
FILE_DIR=${TMP_DIR}/file

rm -rf ${TMP_DIR}
mkdir -p ${JOBS_DIR} ${FILE_DIR}

JOB_LIST=${TMP_DIR}/job-list

CHART_TMP=${TMP_DIR}/chart.yaml

# job list
ls ${SHELL_DIR}/jobs/ > ${JOB_LIST}

while read JOB; do
    ORIGIN=${SHELL_DIR}/jobs/${JOB}/Jenkinsfile
    TMP=${FILE_DIR}/${JOB}
    XML=${JOBS_DIR}/${JOB}.xml

    # Jenkinsfile
    if [ -f ${ORIGIN} ]; then
        cp -rf ${ORIGIN} ${TMP}
        sed -i -e "s/\"/\&quot;/g" ${TMP}
        sed -i -e "s/</\&lt;/g" ${TMP}
        sed -i -e "s/>/\&gt;/g" ${TMP}
    else
        touch ${TMP}
    fi

    # Jenkinsfile >> job.xml
    while read LINE; do
        if [ "${LINE}" == "REPLACE" ]; then
            cat ${TMP} >> ${XML}
        else
            echo "${LINE}" >> ${XML}
        fi
    done < ${SHELL_DIR}/jobs/${JOB}/config.xml
done < ${JOB_LIST}

# job list
ls ${JOBS_DIR} | grep "[.]xml" > ${JOB_LIST}

# jobs.yaml >> chart.yaml
POS=$(grep -n "jenkins-jobs -- start" ${CHART} | cut -d':' -f1)

sed "${POS}q" ${CHART} >> ${CHART_TMP}

echo
echo "  Jobs:" >> ${CHART_TMP}
while read JOB; do
    echo "> ${JOB}"

    NAME=${JOB%.*l}
    echo "    ${NAME}: |-" >> ${CHART_TMP}
    while read LINE; do
        echo "      ${LINE}" >> ${CHART_TMP}
    done < ${JOBS_DIR}/${JOB}
done < ${JOB_LIST}

sed "1,${POS}d" ${CHART} >> ${CHART_TMP}

# done
cp -rf ${CHART_TMP} ${CHART}
