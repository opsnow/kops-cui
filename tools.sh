#!/bin/bash

# version
DATE=
KUBECTL=
KOPS=
HELM=
DRAFT=
GUARD=

mkdir -p ~/.kops-cui

CONFIG=~/.kops-cui/tools
touch ${CONFIG} && . ${CONFIG}

################################################################################

command -v tput > /dev/null && TPUT=true

_echo() {
    if [ "${TPUT}" != "" ] && [ "$2" != "" ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
}

_result() {
    _echo "# $@" 4
}

_command() {
    _echo "$ $@" 3
}

_success() {
    _echo "+ $@" 2
    exit 0
}

_error() {
    _echo "- $@" 1
    exit 1
}

DATE=$(date '+%Y-%m-%d %H:%M:%S')

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

_result "${OS_NAME} [${OS_TYPE}]"
_result "${DATE}"

if [ "${OS_TYPE}" == "" ]; then
    _error "Not supported OS. [${OS_NAME}]"
fi

# brew for mac
if [ "${OS_TYPE}" == "brew" ]; then
    command -v brew > /dev/null || ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# for ubuntu
if [ "${OS_TYPE}" == "apt" ]; then
    export LC_ALL=C
fi

# ssh keygen
[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -q -f ~/.ssh/id_rsa -N ''

# update
echo "================================================================================"
_result "update..."

if [ "${OS_TYPE}" == "apt" ]; then
    sudo apt update && sudo apt upgrade -y
    command -v jq > /dev/null || sudo apt install -y jq
    command -v git > /dev/null || sudo apt install -y git
    command -v pip > /dev/null || sudo apt install -y python-pip
    command -v ab > /dev/null || sudo apt install -y apache2-utils
elif [ "${OS_TYPE}" == "yum" ]; then
    sudo yum update -y
    command -v jq > /dev/null || sudo yum install -y jq
    command -v git > /dev/null || sudo yum install -y git
    command -v pip > /dev/null || sudo yum install -y python-pip
    command -v ab > /dev/null || sudo yum install -y httpd-tools
elif [ "${OS_TYPE}" == "brew" ]; then
    brew update && brew upgrade
    command -v jq > /dev/null || brew install jq
    command -v git > /dev/null || brew install git
    command -v fzf > /dev/null || brew install fzf
    # getopt
    GETOPT=$(getopt 2>&1 | head -1 | xargs)
    if [ "${GETOPT}" == "--" ]; then
        brew install gnu-getopt
        brew link --force gnu-getopt
    fi
fi

# aws-cli
echo "================================================================================"
_result "install aws-cli..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v aws > /dev/null || brew install awscli
else
    pip install --upgrade --user awscli
fi

aws --version | xargs

if [ ! -f ~/.aws/config ]; then
    # aws region
    aws configure set default.region ap-northeast-2
fi

# kubectl
echo "================================================================================"
_result "install kubectl..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kubectl > /dev/null || brew install kubernetes-cli
else
    VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)

    if [ "${KUBECTL}" != "${VERSION}" ] || [ "$(command -v kubectl)" == "" ]; then
        _result " ${KUBECTL} >> ${VERSION}"

        curl -LO https://storage.googleapis.com/kubernetes-release/release/${VERSION}/bin/${OS_NAME}/amd64/kubectl
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

        KUBECTL="${VERSION}"
    fi
fi

kubectl version --client --short | xargs | awk '{print $3}'

# terraform
echo "================================================================================"
_result "install terraform..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v terraform > /dev/null || brew install terraform
else
    VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r '.tag_name' | cut -d'v' -f2)

    if [ "${TERRAFORM}" != "${VERSION}" ] || [ "$(command -v terraform)" == "" ]; then
        _result " ${TERRAFORM} >> ${VERSION}"

        curl -LO "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_${OS_NAME}_amd64.zip"
        unzip terraform_${VERSION}_${OS_NAME}_amd64.zip && rm -rf terraform_${VERSION}_${OS_NAME}_amd64.zip
        sudo mv terraform /usr/local/bin/terraform

        TERRAFORM="${VERSION}"
    fi
fi

terraform version | xargs | awk '{print $2}'

# kops
echo "================================================================================"
_result "install kops..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v kops > /dev/null || brew install kops
else
    VERSION=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | jq -r '.tag_name')

    if [ "${KOPS}" != "${VERSION}" ] || [ "$(command -v kops)" == "" ]; then
        _result " ${KOPS} >> ${VERSION}"

        curl -LO https://github.com/kubernetes/kops/releases/download/${VERSION}/kops-${OS_NAME}-amd64
        chmod +x kops-${OS_NAME}-amd64 && sudo mv kops-${OS_NAME}-amd64 /usr/local/bin/kops

        KOPS="${VERSION}"
    fi
fi

kops version 2>&1 | grep Version | xargs | awk '{print $2}'

# helm
echo "================================================================================"
_result "install helm..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v helm > /dev/null || brew install kubernetes-helm
else
    # VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')
    VERSION="v2.13.1"

    if [ "${HELM}" != "${VERSION}" ] || [ "$(command -v helm)" == "" ]; then
        _result " ${HELM} >> ${VERSION}"

        curl -L https://storage.googleapis.com/kubernetes-helm/helm-${VERSION}-${OS_NAME}-amd64.tar.gz | tar xz
        sudo mv ${OS_NAME}-amd64/helm /usr/local/bin/helm && rm -rf ${OS_NAME}-amd64

        HELM="${VERSION}"
    fi
fi

helm version --client --short | xargs | awk '{print $2}' | cut -d'+' -f1

# draft
echo "================================================================================"
_result "install draft..."

if [ "${OS_TYPE}" == "brew" ]; then
    if [ "$(command -v draft)" == "" ]; then
        brew tap azure/draft && brew install azure/draft/draft
    fi
else
    VERSION=$(curl -s https://api.github.com/repos/Azure/draft/releases/latest | jq -r '.tag_name')

    if [ "${DRAFT}" != "${VERSION}" ] || [ "$(command -v draft)" == "" ]; then
        _result " ${DRAFT} >> ${VERSION}"

        curl -L https://azuredraft.blob.core.windows.net/draft/draft-${VERSION}-${OS_NAME}-amd64.tar.gz | tar xz
        sudo mv ${OS_NAME}-amd64/draft /usr/local/bin/draft && rm -rf ${OS_NAME}-amd64

        DRAFT="${VERSION}"
    fi
fi

draft version --short | xargs | cut -d'+' -f1

# aws-iam-authenticator
echo "================================================================================"
_result "install aws-iam-authenticator..."

if [ "${OS_TYPE}" == "brew" ]; then
    command -v aws-iam-authenticator > /dev/null || brew install aws-iam-authenticator
else
    # VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/aws-iam-authenticator/releases/latest | jq -r '.tag_name' | cut -d'v' -f2)
    VERSION="0.3.0"

    if [ "${AWS_AUTH}" != "${VERSION}" ] || [ "$(command -v draft)" == "" ]; then
        _result " ${AWS_AUTH} >> ${VERSION}"

        URL="https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v${VERSION}/heptio-authenticator-aws_${VERSION}_${OS_NAME}_amd64"
        curl -L -o aws-iam-authenticator ${URL}
        chmod +x aws-iam-authenticator && sudo mv aws-iam-authenticator /usr/local/bin/aws-iam-authenticator

        AWS_AUTH="${VERSION}"
    fi
fi

echo "${VERSION}"

# guard
echo "================================================================================"
_result "install guard..."

VERSION=$(curl -s https://api.github.com/repos/appscode/guard/releases/latest | jq -r '.tag_name')

if [ "${GUARD}" != "${VERSION}" ]; then
    _result " ${GUARD} >> ${VERSION}"

    curl -LO https://github.com/appscode/guard/releases/download/${VERSION}/guard-${OS_NAME}-amd64
    chmod +x guard-${OS_NAME}-amd64 && sudo mv guard-${OS_NAME}-amd64 /usr/local/bin/guard

    GUARD="${VERSION}"
fi

guard version 2>&1 | grep 'Version ' | xargs | awk '{print $3}'

# clean
echo "================================================================================"
_result "clean all..."

if [ "${OS_TYPE}" == "apt" ]; then
    sudo apt clean all
    sudo apt autoremove -y
elif [ "${OS_TYPE}" == "yum" ]; then
    sudo yum clean all
elif [ "${OS_TYPE}" == "brew" ]; then
    brew cleanup
fi

echo "================================================================================"

cat << EOF > ${CONFIG}
# version
DATE="${DATE}"
KUBECTL="${KUBECTL}"
TERRAFORM="${TERRAFORM}"
KOPS="${KOPS}"
HELM="${HELM}"
DRAFT="${DRAFT}"
AWS_AUTH="${AWS_AUTH}"
GUARD="${GUARD}"
EOF
