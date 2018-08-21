#!/bin/bash

JENKINS=$(kubectl get ing -n ${1:-devops} -o wide | grep jenkins | awk '{print $2}')

USERNAME="admin"
PASSWORD=$(kubectl get secret -n ${1:-devops} jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)

JOB="sample"

curl --request POST "http://$JENKINS/createItem?name=$JOB" \
     --data-binary "@$JOB.xml" \
     --user $USERNAME:$PASSWORD \
     --header "Content-Type: application/xml"

#     --retry "20" --retry-delay "10" --max-time "3"
