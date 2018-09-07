#!/bin/bash

rm -rf target
mkdir -p target

USERNAME=${1:-nalbam}
REPONAME=${2:-kops-cui}

# VERSION
VERSION=$(curl -s https://api.github.com/repos/${USERNAME}/${REPONAME}/releases/latest | grep tag_name | cut -d'"' -f4)
VERSION=$(echo ${VERSION:-v0.0.0} | perl -pe 's/^(([v\d]+\.)*)(\d+)(.*)$/$1.($3+1).$4/e')

echo "VERSION=${VERSION}"

# version
printf "${VERSION}" > target/VERSION

ls -al target
