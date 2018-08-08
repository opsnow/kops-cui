#!/bin/bash

SHELL_DIR=$(dirname $0)

JENKINS=${1:-/tmp/jenkins.yaml}

rm -rf /tmp/jobs
mkdir -p /tmp/jobs

ls ${SHELL_DIR}/files/ > /tmp/jobs.txt

while read VAL; do
    JOB=${SHELL_DIR}/files/${VAL}/Jenkinsfile

    if [ -f ${JOB} ]; then
        cp -rf $JOB /tmp/jenkinsfile-${VAL}

        sed -i -e "s/\"/\&quot;/g" /tmp/jenkinsfile-${VAL}

        while read LINE; do
            if [ "${LINE}" == "REPLACE" ]; then
                cat /tmp/jenkinsfile-${VAL} >> /tmp/jobs/${VAL}.xml
            else
                echo "${LINE}" >> /tmp/jobs/${VAL}.xml
            fi
        done < ${SHELL_DIR}/files/${VAL}/job.xml
    fi
done < /tmp/jobs.txt

ls /tmp/jobs/ | grep "[.]xml" > /tmp/jobs.txt

echo "  Jobs: |-" >> ${JENKINS}
while read VAL; do
    JOB=${VAL%.*l}
    echo "${VAL}"
    echo "    ${JOB}: |-" >> ${JENKINS}
    while read LINE; do
        echo "      ${LINE}" >> ${JENKINS}
    done < /tmp/jobs/${VAL}
done < /tmp/jobs.txt
