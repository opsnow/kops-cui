#!/bin/bash

JOB="${1:-sample}"

JENKINS=$(kubectl get ing -n devops -o wide | grep jenkins | awk '{print $2}')

USERNAME="admin"
PASSWORD=$(kubectl get secret -n devops jenkins -o jsonpath="{.data.jenkins-${USERNAME}-password}" | base64 --decode)

curl -X POST \
     -H "Content-Type: application/xml" \
     -u $USERNAME:$PASSWORD \
     --data-binary "@$JOB.xml" \
     "http://$JENKINS/createItem?name=$JOB"

#     --retry "20" --retry-delay "10" --max-time "3" \
