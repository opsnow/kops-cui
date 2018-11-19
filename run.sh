
SHELL_DIR=$(dirname $0)

. ${SHELL_DIR}/common.sh
. ${SHELL_DIR}/default.sh

################################################################################

prepare() {
    logo

    mkdir -p ~/.ssh
    mkdir -p ~/.aws

    NEED_TOOL=
    command -v jq > /dev/null      || export NEED_TOOL=jq
    command -v git > /dev/null     || export NEED_TOOL=git
    command -v aws > /dev/null     || export NEED_TOOL=awscli
    command -v kubectl > /dev/null || export NEED_TOOL=kubectl
    command -v kops > /dev/null    || export NEED_TOOL=kops
    command -v helm > /dev/null    || export NEED_TOOL=helm

    if [ ! -z ${NEED_TOOL} ]; then
        question "Do you want to install the required tools? (awscli,kubectl,kops,helm...) [Y/n] : "

        if [ "${ANSWER:-Y}" == "Y" ]; then
            ${SHELL_DIR}/tools.sh
        else
            _error "Need install tools."
        fi
    fi

    REGION="$(aws configure get default.region)"
}

usage() {
cat <<EOF
Usage: `basename $0` {Command}

Commands:
    kops        kops 로 클러스터를 관리 합니다.
    helm        helm 으로 클러스터의 Application 을 관리합니다.
    tools       필요한 Tool 을 설치 합니다.
================================================================================
EOF
    _success
}

run_kops() {
    ${SHELL_DIR}/kops.sh
}

run_helm() {
    ${SHELL_DIR}/helm.sh
}

run() {
    prepare

    case ${CMD} in
        kops)
            run_kops
            ;;
        helm)
            run_helm
            ;;
        tools)
            update_tools
            ;;
        *)
            usage
            ;;
    esac
}

CMD=$1

run
