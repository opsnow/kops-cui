#!/bin/bash

title() {
    echo -e "$(tput setaf 3)$@$(tput sgr0)"
}

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
DRAFT=

mkdir -p ~/.kops-cui

CONFIG=~/.kops-cui/bastion
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
title "# update..."

DATE=$(date '+%Y-%m-%d %H:%M:%S')

if [ "${OS_TYPE}" == "apt" ]; then
    sudo apt update && sudo apt upgrade -y
    command -v jq > /dev/null   || sudo apt install -y jq
    command -v git > /dev/null  || sudo apt install -y git
    command -v pip > /dev/null  || sudo apt install -y python-pip
elif [ "${OS_TYPE}" == "yum" ]; then
    sudo yum update -y
    command -v jq > /dev/null   || sudo yum install -y jq
    command -v git > /dev/null  || sudo yum install -y git
    command -v pip > /dev/null  || sudo yum install -y python-pip
elif [ "${OS_TYPE}" == "brew" ]; then
    brew update && brew upgrade
    command -v jq > /dev/null   || brew install jq
    command -v git > /dev/null  || brew install git
fi

# aws-cli
echo "================================================================================"
title "# install aws-cli..."

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
title "# install kubectl..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kubectl > /dev/null || brew install kubernetes-cli
else
    VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)

    if [ "${KUBECTL}" != "${VERSION}" ]; then
        curl -LO https://storage.googleapis.com/kubernetes-release/release/${VERSION}/bin/${OS_NAME}/amd64/kubectl
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

        KUBECTL="${VERSION}"
    fi
fi

kubectl version --client --short

# kops
echo "================================================================================"
title "# install kops..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kops > /dev/null || brew install kops
else
    VERSION=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | jq --raw-output '.tag_name')

    if [ "${KOPS}" != "${VERSION}" ]; then
        curl -LO https://github.com/kubernetes/kops/releases/download/${VERSION}/kops-${OS_NAME}-amd64
        chmod +x kops-${OS_NAME}-amd64 && sudo mv kops-${OS_NAME}-amd64 /usr/local/bin/kops

        KOPS="${VERSION}"
    fi
fi

kops version

# helm
echo "================================================================================"
title "# install helm..."

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

# draft
echo "================================================================================"
title "# install draft..."

#if [ "${OS_TYPE}" == "brew" ]; then
#    command -v draft > /dev/null || brew install draft
#else
    VERSION=$(curl -s https://api.github.com/repos/Azure/draft/releases/latest | jq --raw-output '.tag_name')

    if [ "${DRAFT}" != "${VERSION}" ]; then
        curl -L https://azuredraft.blob.core.windows.net/draft/draft-${VERSION}-${OS_NAME}-amd64.tar.gz | tar xz
        sudo mv ${OS_NAME}-amd64/draft /usr/local/bin/draft && rm -rf ${OS_NAME}-amd64

        DRAFT="${VERSION}"
    fi
#fi

draft version --short

echo "================================================================================"
title "# clean all..."

if [ "${OS_TYPE}" == "apt" ]; then
    sudo apt clean all
    sudo apt autoremove -y
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
echo "DRAFT=\"${DRAFT}\"" >> ${CONFIG}

title "# Done."
