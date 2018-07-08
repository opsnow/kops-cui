#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"
OS_FULL="$(uname -a)"
OS_TYPE=

if [ "${OS_NAME}" == "linux" ]; then
    if [ $(echo "${OS_FULL}" | grep -c "amzn1") -gt 0 ]; then
        OS_TYPE="yum"
    elif [ $(echo "${OS_FULL}" | grep -c "amzn2") -gt 0 ]; then
        OS_TYPE="yum"
    elif [ $(echo "${OS_FULL}" | grep -c "el6") -gt 0 ]; then
        OS_TYPE="yum"
    elif [ $(echo "${OS_FULL}" | grep -c "el7") -gt 0 ]; then
        OS_TYPE="yum"
    elif [ $(echo "${OS_FULL}" | grep -c "Ubuntu") -gt 0 ]; then
        OS_TYPE="apt"
    elif [ $(echo "${OS_FULL}" | grep -c "coreos") -gt 0 ]; then
        OS_TYPE="apt"
    fi
elif [ "${OS_NAME}" == "darwin" ]; then
    OS_TYPE="brew"
fi

if [ "${OS_TYPE}" == "" ]; then
    error "Not supported OS. [${OS_FULL}]"
fi

# version
DATE=
KUBECTL=
KOPS=
HELM=

CONFIG=~/.kops/bastion
if [ -f ${CONFIG} ]; then
  . ${CONFIG}
fi

# brew for mac
if [ "${OS_TYPE}" == "brew" ]; then
    command -v brew > /dev/null || ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# for ubuntu
if [ "${OS_TYPE}" == "apt" ]; then
    export LC_ALL=C
fi

# update
echo "================================================================================"
echo "# update... "

VERSION=$(date '+%Y-%m-%d %H')

if [ "${DATE}" != "${VERSION}" ]; then
    if [ "${OS_TYPE}" == "apt" ]; then
        sudo apt update
    elif [ "${OS_TYPE}" == "yum" ]; then
        sudo yum update -y
    elif [ "${OS_TYPE}" == "brew" ]; then
        brew update && brew upgrade
    fi

    if [ "${OS_TYPE}" == "apt" ]; then
        sudo apt install -y jq git make wget python-pip
    elif [ "${OS_TYPE}" == "yum" ]; then
        sudo yum install -y jq git make wget python-pip
    elif [ "${OS_TYPE}" == "brew" ]; then
        command -v jq > /dev/null || brew install jq
        command -v git > /dev/null || brew install git
        command -v make > /dev/null || brew install make
        command -v wget > /dev/null || brew install wget
    fi

    DATE="${VERSION}"
fi

# aws-cli
echo "================================================================================"
echo "# install aws-cli... "

if [ "${OS_TYPE}" == "brew" ]; then
    command -v aws > /dev/null || brew install awscli
else
    pip install --upgrade --user awscli
fi

aws --version

if [ ! -f ~/.aws/credentials ]; then
    # aws region
    aws configure set default.region ap-northeast-2

    # aws credentials
    echo "[default]" > ~/.aws/credentials
    echo "aws_access_key_id=" >> ~/.aws/credentials
    echo "aws_secret_access_key=" >> ~/.aws/credentials
fi

# kubectl
echo "================================================================================"
echo "# install kubectl... "

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kubectl > /dev/null || brew install kubernetes-cli
else
    VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)

    if [ "${KUBECTL}" != "${VERSION}" ]; then
        wget https://storage.googleapis.com/kubernetes-release/release/${VERSION}/bin/${OS_NAME}/amd64/kubectl
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

        KUBECTL="${VERSION}"
    fi
fi

kubectl version --client --short

# kops
echo "================================================================================"
echo "# install kops... "

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kops > /dev/null || brew install kops
else
    VERSION=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | jq --raw-output '.tag_name')

    if [ "${KOPS}" != "${VERSION}" ]; then
        wget https://github.com/kubernetes/kops/releases/download/${VERSION}/kops-${OS_NAME}-amd64
        chmod +x kops-${OS_NAME}-amd64 && sudo mv kops-${OS_NAME}-amd64 /usr/local/bin/kops

        KOPS="${VERSION}"
    fi
fi

kops version

# helm
echo "================================================================================"
echo "# install helm... "

if [ "${OS_TYPE}" == "brew" ]; then
    command -v helm > /dev/null || brew install kubernetes-helm
else
    VERSION=$(curl -s https://api.github.com/repos/kubernetes/helm/releases/latest | jq --raw-output '.tag_name')

    if [ "${HELM}" != "${VERSION}" ]; then
        curl -L https://storage.googleapis.com/kubernetes-helm/helm-${VERSION}-${OS_NAME}-amd64.tar.gz | tar xz
        sudo mv ${OS_NAME}-amd64/helm /usr/local/bin/helm && rm -rf ${OS_NAME}-amd64

        HELM="${VERSION}"
    fi
fi

helm version --client --short

echo "================================================================================"
echo "# clean all... "

if [ "${OS_TYPE}" == "apt" ]; then
    sudo apt clean all
elif [ "${OS_TYPE}" == "yum" ]; then
    sudo yum clean all
elif [ "${OS_TYPE}" == "brew" ]; then
    brew cleanup
fi

echo "================================================================================"

echo "# bastion" > ${CONFIG}
echo "DATE=\"${DATE}\"" >> ${CONFIG}
echo "KUBECTL=\"${KUBECTL}\"" >> ${CONFIG}
echo "KOPS=\"${KOPS}\"" >> ${CONFIG}
echo "HELM=\"${HELM}\"" >> ${CONFIG}

echo "# Done."
