#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

THIS_VERSION=v0.0.0

DEBUG_MODE=true

L_PAD="$(printf %3s)"

CONFIG=

ANSWER=
CLUSTER=

REGION=
AZ_LIST=

KOPS_STATE_STORE=
KOPS_CLUSTER_NAME=
KOPS_TERRAFORM=

ROOT_DOMAIN=
BASE_DOMAIN=

EFS_FILE_SYSTEM_ID=

cloud=aws
master_size=c4.large
master_count=1
master_zones=
node_size=m4.large
node_count=2
zones=
network_cidr=10.0.0.0/16
networking=calico
topology=private
dns_zone=
vpc=

command -v tput > /dev/null || TPUT=false

_echo() {
    if [ -z ${TPUT} ] && [ ! -z $2 ]; then
        echo -e "${L_PAD}$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "${L_PAD}$1"
    fi
}

_read() {
    if [ -z ${TPUT} ] && [ ! -z $2 ]; then
        read -p "${L_PAD}$(tput setaf $2)$1$(tput sgr0)" ANSWER
    else
        read -p "${L_PAD}$1" ANSWER
    fi
}

_result() {
    _echo "# $@" 4
}

_command() {
    if [ ! -z ${DEBUG_MODE} ]; then
        _echo "$ $@" 3
        echo
    fi
}

_success() {
    echo
    _echo "+ $@" 2
    echo
    exit 0
}

_error() {
    echo
    _echo "- $@" 1
    echo
    exit 1
}

question() {
    Q=${1:-"Enter your choice : "}
    echo
    _read "$Q" 6
    echo
}

press_enter() {
    echo
    _read "Press Enter to continue..." 5
    echo

    case ${1} in
        cluster)
            cluster_menu
            ;;
        create)
            create_menu
            ;;
        addons)
            addons_menu
            ;;
        monitor)
            # monitor_menu
            charts_menu "monitor"
            ;;
        devops)
            # devops_menu
            charts_menu "devops"
            ;;
        sample)
            sample_menu
            ;;
        state)
            state_store
            ;;
    esac
}

waiting() {
    SEC=${1:-2}

    echo
    progress start

    IDX=0
    while [ 1 ]; do
        if [ "${IDX}" == "${SEC}" ]; then
            break
        fi
        IDX=$(( ${IDX} + 1 ))
        progress
    done

    progress end
    echo
}

waiting_for() {
    echo
    progress start

    IDX=0
    while true; do
        if $@ ${IDX}; then
            break
        fi
        IDX=$(( ${IDX} + 1 ))
        progress
    done

    progress end
    echo
}

waiting_pod() {
    NAMESPACE=${1}
    NAME=${2}
    SEC=${3:-10}

    echo
    _command "kubectl get pod -n ${NAMESPACE} | grep ${NAME}"

    TMP=$(mktemp /tmp/kops-cui-waiting-pod.XXXXXX)

    IDX=0
    while [ 1 ]; do
        kubectl get pod -n ${NAMESPACE} | grep ${NAME} | head -1 > ${TMP}
        cat ${TMP}

        READY=$(cat ${TMP} | awk '{print $2}' | cut -d'/' -f1)
        STATUS=$(cat ${TMP} | awk '{print $3}')

        if [ "${STATUS}" == "Running" ] && [ "x${READY}" != "x0" ]; then
            break
        elif [ "${STATUS}" == "Error" ]; then
            echo
            _result "${STATUS}"
            break
        elif [ "${STATUS}" == "CrashLoopBackOff" ]; then
            echo
            _result "${STATUS}"
            break
        elif [ "x${IDX}" == "x${SEC}" ]; then
            echo
            _result "Timeout"
            break
        fi

        IDX=$(( ${IDX} + 1 ))
        sleep 2
    done

    echo
}

isElapsed() {
    SEC=${1}
    IDX=${2}

    if [ "${IDX}" == "${SEC}" ]; then
        return 0;
    else
        return -1;
    fi
}

progress() {
    if [ "$1" == "start" ]; then
        printf '%3s'
    elif [ "$1" == "end" ]; then
        printf '.\n'
    else
        printf '.'
        sleep 2
    fi
}

logo() {
    if [ -z ${TPUT} ]; then
        tput clear
    fi

    # figlet kops cui
    echo
    echo
    _echo "  _                                _  " 3
    _echo " | | _____  _ __  ___    ___ _   _(_) " 3
    _echo " | |/ / _ \| '_ \/ __|  / __| | | | | " 3
    _echo " |   < (_) | |_) \__ \ | (__| |_| | | " 3
    _echo " |_|\_\___/| .__/|___/  \___|\__,_|_| " 3
    _echo "           |_|                        " 3
    echo
}

title() {
    if [ -z ${TPUT} ]; then
        tput clear
    fi

    echo
    echo
    _echo "KOPS CUI" 3
    echo
    _echo "${KOPS_STATE_STORE} > ${KOPS_CLUSTER_NAME}" 4
    echo
}

run() {
    logo

    get_kops_config

    mkdir -p ~/.ssh
    mkdir -p ~/.aws

    if [ ! -f ~/.ssh/id_rsa ]; then
        _command "ssh-keygen -q -f ~/.ssh/id_rsa -N ''"
        ssh-keygen -q -f ~/.ssh/id_rsa -N ''
    fi

    NEED_TOOL=
    command -v jq > /dev/null      || export NEED_TOOL=jq
    command -v git > /dev/null     || export NEED_TOOL=git
    command -v wget > /dev/null    || export NEED_TOOL=wget
    command -v aws > /dev/null     || export NEED_TOOL=awscli
    command -v kubectl > /dev/null || export NEED_TOOL=kubectl
    command -v kops > /dev/null    || export NEED_TOOL=kops
    command -v helm > /dev/null    || export NEED_TOOL=helm

    if [ ! -z ${NEED_TOOL} ]; then
        question "Do you want to install the required tools? (awscli,kubectl,kops,helm...) [Y/n] : "

        ANSWER=${ANSWER:-Y}

        if [ "${ANSWER}" == "Y" ]; then
            ${SHELL_DIR}/tools.sh
        else
            error
        fi
    fi

    REGION="$(aws configure get default.region)"

    state_store
}

state_store() {
    logo

    read_state_store

    read_cluster_list

    read_kops_config

    save_kops_config

    get_kops_cluster

    if [ "x${CLUSTER}" != "x0" ]; then
        _command "kubectl config current-context"
        KUBE_CLUSTER_NAME=$(kubectl config current-context)

        if [ "${KOPS_CLUSTER_NAME}" != "${KUBE_CLUSTER_NAME}" ]; then
            kops_export
        fi
    fi

    cluster_menu
}

cluster_menu() {
    title

    if [ "x${CLUSTER}" == "x0" ]; then
        _echo "1. Create Cluster"
    else
        _echo "1. Get Cluster"
        _echo "2. Edit Cluster"
        _echo "3. Update Cluster"
        _echo "4. Rolling Update"
        _echo "5. Validate Cluster"
        _echo "6. Export Kube Config"
        echo
        _echo "9. Delete Cluster"
        echo
        _echo "11. Addons.."
    fi
    echo
    _echo "21. update self"
    _echo "22. update tools"
    echo
    _echo "x. Exit"

    question

    case ${ANSWER} in
        1)
            if [ "x${CLUSTER}" == "x0" ]; then
                create_menu
            else
                kops_get
                press_enter cluster
            fi
            ;;
        2)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            kops_edit
            press_enter cluster
            ;;
        3)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            kops_update
            press_enter cluster
            ;;
        4)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            question "Are you sure? (YES/[no]) : "

            if [ "${ANSWER}" == "YES" ]; then
                kops_rolling_update
                press_enter cluster
            else
                cluster_menu
            fi
            ;;
        5)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            kops_validate
            press_enter cluster
            ;;
        6)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            kops_export
            press_enter cluster
            ;;
        9)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            question "Are you sure? (YES/[no]) : "

            if [ "${ANSWER}" == "YES" ]; then
                kops_delete
                press_enter state
            else
                cluster_menu
            fi
            ;;
        11)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            addons_menu
            ;;
        21)
            update_self
            press_enter cluster
            ;;
        22)
            update_tools
            press_enter cluster
            ;;
        x)
            kops_exit
            ;;
        *)
            cluster_menu
            ;;
    esac
}

create_menu() {
    title

    get_az_list

    get_master_zones
    get_node_zones

    _echo "   cloud=${cloud}"
    _echo "   name=${KOPS_CLUSTER_NAME}"
    _echo "   state=s3://${KOPS_STATE_STORE}"
    _echo "1. master-size=${master_size}"
    _echo "2. master-count=${master_count}"
    _echo "   master-zones=${master_zones}"
    _echo "3. node-size=${node_size}"
    _echo "4. node-count=${node_count}"
    _echo "   zones=${zones}"
    _echo "5. network-cidr=${network_cidr}"
    _echo "6. networking=${networking}"
    _echo "7. topology=${topology}"
    _echo "8. dns-zone=${dns_zone}"
    _echo "9. vpc=${vpc}"

    echo
    _echo "c. create"
    _echo "t. terraform"

    question

    case ${ANSWER} in
        1)
            question "Enter master size [${master_size}] : "
            master_size=${ANSWER:-${master_size}}
            create_menu
            ;;
        2)
            question "Enter master count [${master_count}] : "
            master_count=${ANSWER:-${master_count}}
            get_master_zones
            create_menu
            ;;
        3)
            question "Enter node size [${node_size}] : "
            node_size=${ANSWER:-${node_size}}
            create_menu
            ;;
        4)
            question "Enter node count [${node_count}] : "
            node_count=${ANSWER:-${node_count}}
            get_node_zones
            create_menu
            ;;
        5)
            question "Enter network cidr [${network_cidr}] : "
            network_cidr=${ANSWER:-${network_cidr}}
            create_menu
            ;;
        6)
            question "Enter networking [${networking}] : "
            networking=${ANSWER:-${networking}}
            create_menu
            ;;
        7)
            question "Enter topology [${topology}] : "
            topology=${ANSWER:-${topology}}
            create_menu
            ;;
        8)
            question "Enter dns-zone [${dns_zone}] : "
            dns_zone=${ANSWER:-${dns_zone}}
            create_menu
            ;;
        9)
            question "Enter vpc [${vpc}] : "
            vpc=${ANSWER:-${vpc}}
            create_menu
            ;;
        c)
            KOPS_TERRAFORM=
            save_kops_config true

            kops_create

            echo
            _result "Edit InstanceGroup for Cluster Autoscaler"
            echo
            echo "spec:"
            echo "  cloudLabels:"
            echo "    k8s.io/cluster-autoscaler/enabled: \"\""
            echo "    kubernetes.io/cluster/${KOPS_CLUSTER_NAME}: owned"

            press_enter

            get_kops_cluster

            cluster_menu
            ;;
        t)
            KOPS_TERRAFORM=true
            save_kops_config true

            kops_create

            press_enter

            get_kops_cluster

            cluster_menu
            ;;
        *)
            get_kops_cluster

            cluster_menu
            ;;
    esac
}

addons_menu() {
    title

    _echo "1. helm init"
    echo
    _echo "2. nginx-ingress"
    _echo "3. kubernetes-dashboard"
    _echo "4. heapster (deprecated)"
    _echo "5. metrics-server"
    _echo "6. cluster-autoscaler"
    _echo "7. efs-provisioner"
    echo
    _echo "9. remove"
    echo
    _echo "11. sample.."
    _echo "12. monitor.."
    _echo "13. devops.."

    question

    case ${ANSWER} in
        1)
            helm_init
            press_enter addons
            ;;
        2)
            helm_nginx_ingress kube-ingress
            press_enter addons
            ;;
        3)
            helm_install kubernetes-dashboard kube-system false
            echo
            create_cluster_role_binding cluster-admin kube-system dashboard-admin
            echo
            SECRET=$(kubectl get secret -n kube-system | grep dashboard-admin-token | awk '{print $1}')
            kubectl describe secret ${SECRET} -n kube-system | grep 'token:'
            press_enter addons
            ;;
        4)
            helm_install heapster kube-system
            press_enter addons
            ;;
        5)
            helm_install metrics-server kube-system
            echo
            kubectl get hpa
            press_enter addons
            ;;
        6)
            helm_install cluster-autoscaler kube-system
            echo
            _result "Edit InstanceGroup for AutoDiscovery"
            echo
            echo "spec:"
            echo "  cloudLabels:"
            echo "    k8s.io/cluster-autoscaler/enabled: \"\""
            echo "    kubernetes.io/cluster/${KOPS_CLUSTER_NAME}: owned"
            press_enter addons
            ;;
        7)
            # helm_efs_provisioner
            helm_install efs-provisioner kube-system
            press_enter addons
            ;;
        9)
            helm_delete
            press_enter addons
            ;;
        11)
            sample_menu
            ;;
        12)
            # monitor_menu
            charts_menu "monitor"
            ;;
        13)
            # devops_menu
            charts_menu "devops"
            ;;
        *)
            cluster_menu
            ;;
    esac
}

select_one() {
    IDX=0
    while read VAL; do
        IDX=$(( ${IDX} + 1 ))
        printf "%4s. %s\n" "$IDX" "${VAL}";
    done < ${LIST}

    # select
    question

    # answer
    SELECTED=
    if [ -z ${ANSWER} ]; then
        return
    fi
    TEST='^[0-9]+$'
    if ! [[ ${ANSWER} =~ ${TEST} ]]; then
        return
    fi
    SELECTED=$(sed -n ${ANSWER}p ${LIST})
}

sample_menu() {
    title

    LIST=$(mktemp /tmp/kops-cui-sample-list.XXXXXX)

    # find sample
    ls ${SHELL_DIR}/sample | sort | sed 's/.yaml//' > ${LIST}

    # select
    select_one

    if [ -z ${SELECTED} ]; then
        addons_menu
        return
    fi

    # sample install
    if [ "${SELECTED}" == "configmap" ] || [ "${SELECTED}" == "redis" ]; then
        apply_sample ${SELECTED} default
    else
        apply_sample ${SELECTED} default true
    fi

    press_enter sample
}

charts_menu () {
    title

    NAMESPACE=$1

    LIST=$(mktemp /tmp/kops-cui-charts-list.XXXXXX)

    # find chart
    ls ${SHELL_DIR}/charts/${NAMESPACE} | sort | sed 's/.yaml//' > ${LIST}

    # select
    select_one

    if [ -z ${SELECTED} ]; then
        addons_menu
        return
    fi

    create_cluster_role_binding cluster-admin ${NAMESPACE}

    # helm install
    helm_install ${SELECTED} ${NAMESPACE} true

    press_enter ${NAMESPACE}
}

get_kops_cluster() {
    _command "kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | wc -l | xargs"
    CLUSTER=$(kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | wc -l | xargs)
}

get_kops_config() {
    mkdir -p ~/.kops-cui

    CONFIG=~/.kops-cui/config

    if [ -f ${CONFIG} ]; then
        . ${CONFIG}
    fi
}

read_kops_config() {
    if [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        _command "aws s3 ls s3://${KOPS_STATE_STORE} | grep ${KOPS_CLUSTER_NAME}.kops-cui | wc -l | xargs"
        COUNT=$(aws s3 ls s3://${KOPS_STATE_STORE} | grep ${KOPS_CLUSTER_NAME}.kops-cui | wc -l | xargs)

        if [ "x${COUNT}" != "x0" ]; then
            _command "aws s3 cp s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui ${CONFIG}"
            aws s3 cp s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui ${CONFIG} --quiet

            if [ -f ${CONFIG} ]; then
                . ${CONFIG}
            fi
        fi
    fi
}

save_kops_config() {
    S3_SYNC=$1

    echo "# kops config" > ${CONFIG}
    echo "KOPS_STATE_STORE=${KOPS_STATE_STORE}" >> ${CONFIG}
    echo "KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}" >> ${CONFIG}
    echo "KOPS_TERRAFORM=${KOPS_TERRAFORM}" >> ${CONFIG}
    echo "ROOT_DOMAIN=${ROOT_DOMAIN}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}
    echo "EFS_FILE_SYSTEM_ID=${EFS_FILE_SYSTEM_ID}" >> ${CONFIG}

    . ${CONFIG}

    if [ ! -z ${DEBUG_MODE} ]; then
        cat ${CONFIG}
        echo
    fi

    if [ ! -z ${S3_SYNC} ] && [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        _command "aws s3 cp ${CONFIG} s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui"
        aws s3 cp ${CONFIG} s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui --quiet
    fi
}

clear_kops_config() {
    export KOPS_STATE_STORE=
    export KOPS_CLUSTER_NAME=
    export KOPS_TERRAFORM=
    export ROOT_DOMAIN=
    export BASE_DOMAIN=
    export EFS_FILE_SYSTEM_ID=

    save_kops_config
}

delete_kops_config() {
    if [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        _command "aws s3 rm s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui"
        aws s3 rm s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui --quiet
    fi

    clear_kops_config
}

read_state_store() {
    if [ ! -z ${KOPS_STATE_STORE} ]; then
        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq -r '.Owner.ID')
        if [ -z ${BUCKET} ]; then
            clear_kops_config
        fi
    fi

    if [ -z ${KOPS_STATE_STORE} ]; then
        DEFAULT=$(aws s3 ls | grep kops-state | head -1 | awk '{print $3}')
        if [ -z ${DEFAULT} ]; then
            DEFAULT="kops-state-$(whoami)"
        fi
    else
        DEFAULT=${KOPS_STATE_STORE}
    fi

    question "Enter cluster store [${DEFAULT}] : "

    KOPS_STATE_STORE=${ANSWER:-${DEFAULT}}

    # S3 Bucket
    BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq -r '.Owner.ID')
    if [ -z ${BUCKET} ]; then
        _command "aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}"
        aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}

        waiting 2

        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq -r '.Owner.ID')
        if [ -z ${BUCKET} ]; then
            clear_kops_config
            error
        fi
    fi
}

read_cluster_list() {
    CLUSTER_LIST=$(mktemp /tmp/kops-cui-kops-cluster-list.XXXXXX)

    _command "kops get cluster --state=s3://${KOPS_STATE_STORE}"
    kops get cluster --state=s3://${KOPS_STATE_STORE} > ${CLUSTER_LIST}

    IDX=0
    while read VAR; do
        ARR=(${VAR})

        if [ "${ARR[0]}" == "NAME" ]; then
            continue
        fi

        IDX=$(( ${IDX} + 1 ))

        _echo "${IDX}. ${ARR[0]}"
    done < ${CLUSTER_LIST}

    if [ "x${IDX}" == "x0" ]; then
        read_cluster_name
    else
        echo
        _echo "0. new"

        question "Enter cluster (0-${IDX})[1] : "

        ANSWER=${ANSWER:-1}

        if [ "x${ANSWER}" == "x0" ]; then
            read_cluster_name
        else
            ARR=($(sed -n $(( ${ANSWER} + 1 ))p ${CLUSTER_LIST}))
            KOPS_CLUSTER_NAME="${ARR[0]}"
        fi
    fi

    if [ -z ${KOPS_CLUSTER_NAME} ]; then
        clear_kops_config
        error
    fi
}

read_cluster_name() {
    if [ "${OS_NAME}" == "linux" ]; then
        RND=$(shuf -i 1-6 -n 1)
    elif [ "${OS_NAME}" == "darwin" ]; then
        RND=$(ruby -e 'p rand(1...6)')
    else
        RND=
    fi

    if [ ! -z ${RND} ]; then
        WORD=$(sed -n ${RND}p ${SHELL_DIR}/addons/words.txt)
    fi

    if [ -z ${WORD} ]; then
        WORD="demo"
    fi

    DEFAULT="${WORD}.k8s.local"
    question "Enter your cluster name [${DEFAULT}] : "

    KOPS_CLUSTER_NAME=${ANSWER:-${DEFAULT}}
}

kops_get() {
    _command "kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_create() {
    KOPS_CREATE=$(mktemp /tmp/kops-cui-kops-create.XXXXXX)

    echo "kops create cluster "                  >  ${KOPS_CREATE}
    echo "    --cloud=${cloud} "                 >> ${KOPS_CREATE}
    echo "    --name=${KOPS_CLUSTER_NAME} "      >> ${KOPS_CREATE}
    echo "    --state=s3://${KOPS_STATE_STORE} " >> ${KOPS_CREATE}

    [ -z ${master_size} ]  || echo "    --master-size=${master_size} "   >> ${KOPS_CREATE}
    [ -z ${master_count} ] || echo "    --master-count=${master_count} " >> ${KOPS_CREATE}
    [ -z ${master_zones} ] || echo "    --master-zones=${master_zones} " >> ${KOPS_CREATE}
    [ -z ${node_size} ]    || echo "    --node-size=${node_size} "       >> ${KOPS_CREATE}
    [ -z ${node_count} ]   || echo "    --node-count=${node_count} "     >> ${KOPS_CREATE}
    [ -z ${zones} ]        || echo "    --zones=${zones} "               >> ${KOPS_CREATE}
    [ -z ${networking} ]   || echo "    --networking=${networking} "     >> ${KOPS_CREATE}
    [ -z ${topology} ]     || echo "    --topology=${topology} "         >> ${KOPS_CREATE}
    [ -z ${dns_zone} ]     || echo "    --dns-zone=${dns_zone} "         >> ${KOPS_CREATE}

    if [ ! -z ${vpc} ]; then
        echo "    --vpc=${vpc} " >> ${KOPS_CREATE}
    else
        [ -z ${network_cidr} ] || echo "    --network-cidr=${network_cidr} " >> ${KOPS_CREATE}
    fi

    if [ ! -z ${KOPS_TERRAFORM} ]; then
        OUT_PATH="terraform-${KOPS_CLUSTER_NAME}"

        mkdir -p ${OUT_PATH}

        echo "    --target=terraform " >> ${KOPS_CREATE}
        echo "    --out=${OUT_PATH} "  >> ${KOPS_CREATE}
    fi

    cat ${KOPS_CREATE}
    echo

    $(cat ${KOPS_CREATE})
}

kops_edit() {
    IG_LIST=$(mktemp /tmp/kops-cui-kops-ig-list.XXXXXX)

    _command "kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} > ${IG_LIST}

    IDX=0
    while read VAR; do
        ARR=(${VAR})

        if [ "${ARR[0]}" == "NAME" ]; then
            continue
        fi

        IDX=$(( ${IDX} + 1 ))

        _echo "${IDX}. ${ARR[0]}"
    done < ${IG_LIST}

    echo
    _echo "0. cluster"

    question

    SELECTED=

    if [ "x${ANSWER}" == "x0" ]; then
        SELECTED="cluster"
    elif [ ! -z ${ANSWER} ]; then
        ARR=($(sed -n $(( ${ANSWER} + 1 ))p ${IG_LIST}))
        SELECTED="ig ${ARR[0]}"
    fi

    if [ "${SELECTED}" != "" ]; then
        _command "kops edit ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
        kops edit ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
    fi
}

kops_update() {
    if [ -z ${KOPS_TERRAFORM} ]; then
        _command "kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
        kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes
    else
        _command "kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --target=terraform --out=terraform-${KOPS_CLUSTER_NAME}"
        kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --target=terraform --out=terraform-${KOPS_CLUSTER_NAME}
    fi
}

kops_rolling_update() {
    _command "kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
    kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes
}

kops_validate() {
    _command "kops validate cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops validate cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
    echo

    _command "kubectl get node -o wide"
    kubectl get node -o wide
    echo

    _command "kubectl get pod -n kube-system"
    kubectl get pod -n kube-system
}

kops_export() {
    rm -rf ~/.kube

    _command "kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_delete() {
    delete_efs

    _command "kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes
    echo

    # delete_record

    delete_kops_config

    rm -rf ~/.kube ~/.helm ~/.draft
}

get_elb_domain() {
    ELB_DOMAIN=

    if [ -z $2 ]; then
        _command "kubectl get svc --all-namespaces -o wide | grep LoadBalancer | grep $1 | awk '{print $5}' | head -1"
    else
        _command "kubectl get svc -n $2 -o wide | grep LoadBalancer | grep $1 | awk '{print $4}' | head -1"
    fi

    progress start

    IDX=0
    while [ 1 ]; do
        # ELB Domain 을 획득
        if [ -z $2 ]; then
            ELB_DOMAIN=$(kubectl get svc --all-namespaces -o wide | grep LoadBalancer | grep $1 | awk '{print $5}' | head -1)
        else
            ELB_DOMAIN=$(kubectl get svc -n $2 -o wide | grep LoadBalancer | grep $1 | awk '{print $4}' | head -1)
        fi

        if [ ! -z ${ELB_DOMAIN} ] && [ "${ELB_DOMAIN}" != "<pending>" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))

        if [ "${IDX}" == "200" ]; then
            ELB_DOMAIN=
            break
        fi

        progress
    done

    progress end

    _result ${ELB_DOMAIN}
}

get_ingress_elb_name() {
    ELB_NAME=

    get_elb_domain "nginx-ingress"
    echo

    _command "echo ${ELB_DOMAIN} | cut -d'-' -f1"
    ELB_NAME=$(echo ${ELB_DOMAIN} | cut -d'-' -f1)

    _result ${ELB_NAME}
}

get_ingress_nip_io() {
    ELB_IP=

    get_elb_domain "nginx-ingress"

    if [ -z ${ELB_DOMAIN} ]; then
        return
    fi

    _command "dig +short ${ELB_DOMAIN} | head -n 1"

    progress start

    IDX=0
    while [ 1 ]; do
        ELB_IP=$(dig +short ${ELB_DOMAIN} | head -n 1)

        if [ ! -z ${ELB_IP} ]; then
            BASE_DOMAIN="apps.${ELB_IP}.nip.io"
            break
        fi

        IDX=$(( ${IDX} + 1 ))

        if [ "${IDX}" == "100" ]; then
            BASE_DOMAIN=
            break
        fi

        progress
    done

    progress end

    _result ${BASE_DOMAIN}
}

read_root_domain() {
    HOST_LIST=$(mktemp /tmp/kops-cui-hosted-zones.XXXXXX)

    _command "aws route53 list-hosted-zones | jq -r '.HostedZones[] | .Name'"
    aws route53 list-hosted-zones | jq -r '.HostedZones[] | .Name' > ${HOST_LIST}

    IDX=0
    while read VAR; do
        IDX=$(( ${IDX} + 1 ))

        _echo "${IDX}. $(echo ${VAR} | sed 's/.$//')"
    done < ${HOST_LIST}

    if [ "${IDX}" != "0" ]; then
        echo
        _echo "0. nip.io"

        question "Enter root domain (0-${IDX})[0] : "

        if [ "x${ANSWER}" == "x0" ]; then
            ROOT_DOMAIN=
        elif [ ! -z ${ANSWER} ]; then
            TEST='^[0-9]+$'
            if ! [[ ${ANSWER} =~ ${TEST} ]]; then
                ROOT_DOMAIN=${ANSWER}
            else
                ROOT_DOMAIN=$(sed -n ${ANSWER}p ${HOST_LIST} | sed 's/.$//')
            fi
        fi

        _result "${ROOT_DOMAIN}"
    fi
}

get_ssl_cert_arn() {
    # get certificate arn
    _command "aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn'"
    SSL_CERT_ARN=$(aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn')
}

set_record_cname() {
    if [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # request certificate
    _command "aws acm request-certificate --domain-name "*.${BASE_DOMAIN}" --validation-method DNS | jq -r '.CertificateArn'"
    SSL_CERT_ARN=$(aws acm request-certificate --domain-name "*.${BASE_DOMAIN}" --validation-method DNS | jq -r '.CertificateArn')

    _result "Request Certificate..."

    waiting 2

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    # domain validate name
    _command "aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Name'"
    CERT_DNS_NAME=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Name')

    # domain validate value
    _command "aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Value'"
    CERT_DNS_VALUE=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Value')

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-cname.XXXXXX.json)
    get_template addons/record-sets-cname.json ${RECORD}

    # replace
    sed -i -e "s/DOMAIN/${CERT_DNS_NAME}/g" ${RECORD}
    sed -i -e "s/DNS_NAME/${CERT_DNS_VALUE}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    if [ ! -z ${ZONE_ID} ]; then
        _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
        aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
    fi
}

set_record_alias() {
    if [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    # ELB 에서 Hosted Zone ID 를 획득
    _command "aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .CanonicalHostedZoneNameID'"
    ELB_ZONE_ID=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .CanonicalHostedZoneNameID')

    # ELB 에서 DNS Name 을 획득
    _command "aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .DNSName'"
    ELB_DNS_NAME=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .DNSName')

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-alias.XXXXXX.json)
    get_template addons/record-sets-alias.json ${RECORD}

    # replace
    sed -i -e "s/DOMAIN/*.${BASE_DOMAIN}/g" ${RECORD}
    sed -i -e "s/ZONE_ID/${ELB_ZONE_ID}/g" ${RECORD}
    sed -i -e "s/DNS_NAME/${ELB_DNS_NAME}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    if [ ! -z ${ZONE_ID} ]; then
        _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
        aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
    fi
}

delete_record() {
    if [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-delete.XXXXXX.json)
    get_template addons/record-sets-delete.json ${RECORD}

    # replace
    sed -i -e "s/DOMAIN/*.${BASE_DOMAIN}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    if [ ! -z ${ZONE_ID} ]; then
        _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
        aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
    fi
}

isEFSAvailable() {
    FILE_SYSTEMS=$(aws efs describe-file-systems --creation-token ${KOPS_CLUSTER_NAME} --region ${REGION})
    FILE_SYSTEM_LENGH=$(echo ${FILE_SYSTEMS} | jq -r '.FileSystems | length')
    if [ ${FILE_SYSTEM_LENGH} -gt 0 ]; then
        STATES=$(echo ${FILE_SYSTEMS} | jq -r '.FileSystems[].LifeCycleState')

        COUNT=0
        for state in ${STATES}; do
            if [ "${state}" == "available" ]; then
                COUNT=$(( ${COUNT} + 1 ))
            fi
        done

        # echo ${COUNT}/${FILE_SYSTEM_LENGH}

        if [ ${COUNT} -eq ${FILE_SYSTEM_LENGH} ]; then
            return 0;
        fi
    fi

    return 1;
}

isMountTargetAvailable() {
    MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION})
    MOUNT_TARGET_LENGH=$(echo ${MOUNT_TARGETS} | jq -r '.MountTargets | length')
    if [ ${MOUNT_TARGET_LENGH} -gt 0 ]; then
        STATES=$(echo ${MOUNT_TARGETS} | jq -r '.MountTargets[].LifeCycleState')

        COUNT=0
        for state in ${STATES}; do
            if [ "${state}" == "available" ]; then
                COUNT=$(( ${COUNT} + 1 ))
            fi
        done

        # echo ${COUNT}/${MOUNT_TARGET_LENGH}

        if [ ${COUNT} -eq ${MOUNT_TARGET_LENGH} ]; then
            return 0;
        fi
    fi

    return 1;
}

isMountTargetDeleted() {
    MOUNT_TARGET_LENGTH=$(aws efs describe-mount-targets --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION} | jq -r '.MountTargets | length')
    if [ ${MOUNT_TARGET_LENGTH} == 0 ]; then
        return 0
    else
        return 1
    fi
}

create_efs() {
    # get the security group id
    K8S_NODE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=nodes.${KOPS_CLUSTER_NAME}" | jq -r '.SecurityGroups[0].GroupId')
    if [ -z ${K8S_NODE_SG_ID} ]; then
        _error "Not found the security group for the nodes."
    fi

    # get vpc id & subent ids
    VPC_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=nodes.${KOPS_CLUSTER_NAME}" | jq -r '.SecurityGroups[0].VpcId')
    VPC_PRIVATE_SUBNETS_LENGTH=$(aws ec2 describe-subnets --filters "Name=tag:KubernetesCluster,Values=${KOPS_CLUSTER_NAME}" "Name=tag:SubnetType,Values=Private" | jq '.Subnets | length')
    if [ ${VPC_PRIVATE_SUBNETS_LENGTH} -eq 2 ]; then
        VPC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:KubernetesCluster,Values=${KOPS_CLUSTER_NAME}" "Name=tag:SubnetType,Values=Private" | jq -r '(.Subnets[].SubnetId)')
    else
        VPC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:KubernetesCluster,Values=${KOPS_CLUSTER_NAME}" | jq -r '(.Subnets[].SubnetId)')
    fi

    if [ -z ${VPC_ID} ]; then
        _error "Not found the VPC."
    fi

    _result "K8S_NODE_SG_ID=${K8S_NODE_SG_ID}"
    _result "VPC_ID=${VPC_ID}"
    _result "VPC_SUBNETS="
    echo "${VPC_SUBNETS}"
    echo

    # create a security group for efs mount targets
    EFS_SG_LENGTH=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${KOPS_CLUSTER_NAME}" | jq '.SecurityGroups | length')
    if [ ${EFS_SG_LENGTH} -eq 0 ]; then
        echo "Creating a security group for mount targets"

        EFS_SG_ID=$(aws ec2 create-security-group \
            --region ${REGION} \
            --group-name efs-sg.${KOPS_CLUSTER_NAME} \
            --description "Security group for EFS mount targets" \
            --vpc-id ${VPC_ID} | jq -r '.GroupId')

        aws ec2 authorize-security-group-ingress \
            --group-id ${EFS_SG_ID} \
            --protocol tcp \
            --port 2049 \
            --source-group ${K8S_NODE_SG_ID} \
            --region ${REGION}
    else
        EFS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${KOPS_CLUSTER_NAME}" | jq -r '.SecurityGroups[].GroupId')
    fi

    # echo "Security group for mount targets:"
    _result "EFS_SG_ID=${EFS_SG_ID}"
    echo

    # create an efs
    EFS_LENGTH=$(aws efs describe-file-systems --creation-token ${KOPS_CLUSTER_NAME} | jq '.FileSystems | length')
    if [ ${EFS_LENGTH} -eq 0 ]; then
        echo "Creating a elastic file system"

        EFS_FILE_SYSTEM_ID=$(aws efs create-file-system --creation-token ${KOPS_CLUSTER_NAME} --region ${REGION} | jq -r '.FileSystemId')
        aws efs create-tags \
            --file-system-id ${EFS_FILE_SYSTEM_ID} \
            --tags Key=Name,Value=efs.${KOPS_CLUSTER_NAME} \
            --region ap-northeast-2
    else
        EFS_FILE_SYSTEM_ID=$(aws efs describe-file-systems --creation-token ${KOPS_CLUSTER_NAME} --region ${REGION} | jq -r '.FileSystems[].FileSystemId')
    fi

    _result "EFS_FILE_SYSTEM_ID=${EFS_FILE_SYSTEM_ID}"
    echo

    echo "Waiting for the state of the EFS to be available."
    waiting_for isEFSAvailable

    # create mount targets
    EFS_MOUNT_TARGET_LENGTH=$(aws efs describe-mount-targets --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION} | jq -r '.MountTargets | length')
    if [ ${EFS_MOUNT_TARGET_LENGTH} -eq 0 ]; then
        echo "Creating mount targets"

        for SubnetId in ${VPC_SUBNETS}; do
            EFS_MOUNT_TARGET_ID=$(aws efs create-mount-target \
                --file-system-id ${EFS_FILE_SYSTEM_ID} \
                --subnet-id ${SubnetId} \
                --security-group ${EFS_SG_ID} \
                --region ${REGION} | jq -r '.MountTargetId')
            EFS_MOUNT_TARGET_IDS=(${EFS_MOUNT_TARGET_IDS[@]} ${EFS_MOUNT_TARGET_ID})
        done
    else
        EFS_MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION} | jq -r '.MountTargets[].MountTargetId')
    fi

    _result "EFS_MOUNT_TARGET_IDS="
    echo "${EFS_MOUNT_TARGET_IDS[@]}"
    echo

    echo "Waiting for the state of the EFS mount targets to be available."
    waiting_for isMountTargetAvailable

    save_kops_config true
}

delete_efs() {
    if [ -z ${EFS_FILE_SYSTEM_ID} ]; then
        return
    fi

    # delete mount targets
    EFS_MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION} | jq -r '.MountTargets[].MountTargetId')
    for MountTargetId in ${EFS_MOUNT_TARGET_IDS}; do
        echo "Deleting the mount targets"
        aws efs delete-mount-target --mount-target-id ${MountTargetId}
    done

    echo "Waiting for the EFS mount targets to be deleted."
    waiting_for isMountTargetDeleted

    # delete security group for efs mount targets
    EFS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${KOPS_CLUSTER_NAME}" | jq -r '.SecurityGroups[0].GroupId')
    if [ -n ${EFS_SG_ID} ]; then
        echo "Deleting the security group for mount targets"
        aws ec2 delete-security-group --group-id=${EFS_SG_ID}
    fi

    # delete efs
    if [ -n ${EFS_FILE_SYSTEM_ID} ]; then
        echo "Deleting the elastic file system"
        aws efs delete-file-system --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION}
    fi

    echo
}

helm_nginx_ingress() {
    NAME="nginx-ingress"
    NAMESPACE=${1:-kube-ingress}

    create_namespace ${NAMESPACE}

    helm_check

    ROOT_DOMAIN=
    BASE_DOMAIN=

    read_root_domain

    # ingress domain
    if [ ! -z ${ROOT_DOMAIN} ]; then
        WORD=$(echo ${KOPS_CLUSTER_NAME} | cut -d'.' -f1)

        DEFAULT="${WORD}.${ROOT_DOMAIN}"
        question "Enter your ingress domain [${DEFAULT}] : "

        BASE_DOMAIN=${ANSWER:-${DEFAULT}}
    fi

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX.yaml)
    get_template charts/${NAMESPACE}/${NAME}.yaml ${CHART}

    # certificate
    if [ ! -z ${BASE_DOMAIN} ]; then
        get_ssl_cert_arn

        if [ -z ${SSL_CERT_ARN} ]; then
            set_record_cname
            echo
        fi
        if [ -z ${SSL_CERT_ARN} ]; then
            _error "Certificate ARN does not exists. [*.${BASE_DOMAIN}][${REGION}]"
        fi

        _result "CertificateArn: ${SSL_CERT_ARN}"
        echo

        sed -i -e "s@aws-load-balancer-ssl-cert:.*@aws-load-balancer-ssl-cert: ${SSL_CERT_ARN}@" ${CHART}
    fi

    # chart version
    CHART_VERSION=$(cat ${CHART} | grep chart-version | awk '{print $3}')

    # helm install
    if [ -z ${CHART_VERSION} ] || [ "${CHART_VERSION}" == "latest" ]; then
        _command "helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART}"
        helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART}
    else
        _command "helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART} --version ${CHART_VERSION}"
        helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART} --version ${CHART_VERSION}
    fi

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}" 20

    _command "helm history ${NAME}"
    helm history ${NAME}
    echo

    _command "kubectl get deploy,pod,svc -n ${NAMESPACE}"
    kubectl get deploy,pod,svc -n ${NAMESPACE}
    echo

    _result "Pending ELB..."

    if [ -z ${BASE_DOMAIN} ]; then
        get_ingress_nip_io
        echo
    else
        get_ingress_elb_name
        echo

        set_record_alias
        echo
    fi

    save_kops_config true
}

helm_install() {
    NAME=${1}
    NAMESPACE=${2}
    INGRESS=${3}
    DOMAIN=

    # for efs-provisioner
    if [ "${NAME}" == "efs-provisioner" ]; then
        create_efs
    fi

    create_namespace ${NAMESPACE}

    helm_check

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX.yaml)
    get_template charts/${NAMESPACE}/${NAME}.yaml ${CHART}

    # for jenkins jobs
    if [ "${NAME}" == "jenkins" ]; then
        ${SHELL_DIR}/jobs/replace.sh ${CHART}
        echo
    fi

    sed -i -e "s/CLUSTER_NAME/${KOPS_CLUSTER_NAME}/" ${CHART}
    sed -i -e "s/AWS_REGION/${REGION}/" ${CHART}

    if [ ! -z ${EFS_FILE_SYSTEM_ID} ]; then
        sed -i -e "s/EFS_FILE_SYSTEM_ID/${EFS_FILE_SYSTEM_ID}/" ${CHART}
    fi

    # ingress
    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            sed -i -e "s/SERVICE_TYPE/LoadBalancer/" ${CHART}
            sed -i -e "s/INGRESS_ENABLED/false/" ${CHART}
        else
            DOMAIN="${NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            sed -i -e "s/SERVICE_TYPE/ClusterIP/" ${CHART}
            sed -i -e "s/INGRESS_ENABLED/true/" ${CHART}
            sed -i -e "s/INGRESS_DOMAIN/${DOMAIN}/" ${CHART}
        fi
    fi

    # efs
    if [ ! -z ${EFS_FILE_SYSTEM_ID} ]; then
        sed -i -e "s/#:EFS://" ${CHART}
    fi

    # chart version
    CHART_VERSION=$(cat ${CHART} | grep chart-version | awk '{print $3}')

    # helm install
    if [ -z ${CHART_VERSION} ] || [ "${CHART_VERSION}" == "latest" ]; then
        _command "helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART}"
        helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART}
    else
        _command "helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART} --version ${CHART_VERSION}"
        helm upgrade --install ${NAME} stable/${NAME} --namespace ${NAMESPACE} --values ${CHART} --version ${CHART_VERSION}
    fi

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}"

    _command "helm history ${NAME}"
    helm history ${NAME}
    echo

    _command "kubectl get deploy,pod,svc,ing,pv -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing,pv -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            echo
            get_elb_domain ${NAME} ${NAMESPACE}
            echo
            _result "${NAME}: https://${ELB_DOMAIN}"
        else
            echo
            _result "${NAME}: https://${DOMAIN}"
        fi
    fi
}

helm_delete() {
    NAME=

    LIST=$(mktemp /tmp/kops-cui-helm-list.XXXXXX)

    _command "helm ls --all"

    # find sample
    helm ls --all | grep -v "NAME" | sort > ${LIST}

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        return
    fi

    NAME="$(echo ${SELECTED} | awk '{print $1}')"

    if [ ! -z ${NAME} ]; then
        _command "helm delete --purge ${NAME}"
        helm delete --purge ${NAME}
    fi
}

helm_check() {
    _command "kubectl get pod -n kube-system | grep tiller-deploy"
    COUNT=$(kubectl get pod -n kube-system | grep tiller-deploy | wc -l | xargs)

    if [ "x${COUNT}" == "x0" ] || [ ! -d ~/.helm ]; then
        helm_init
        echo
    fi
}

helm_init() {
    NAMESPACE="kube-system"
    ACCOUNT="tiller"

    create_cluster_role_binding cluster-admin ${NAMESPACE} ${ACCOUNT}

    _command "helm init --upgrade --service-account=${ACCOUNT}"
    helm init --upgrade --service-account=${ACCOUNT}

    # waiting 5
    waiting_pod "${NAMESPACE}" "tiller"

    _command "kubectl get pod,svc -n ${NAMESPACE}"
    kubectl get pod,svc -n ${NAMESPACE}
    echo

    _command "helm repo update"
    helm repo update
    echo

    _command "helm ls"
    helm ls
}

helm_uninit() {
    NAMESPACE="kube-system"
    ACCOUNT="tiller"

    _command "kubectl delete deployment tiller-deploy -n ${NAMESPACE}"
    kubectl delete deployment tiller-deploy -n ${NAMESPACE}
    echo

    _command "kubectl delete clusterrolebinding cluster-admin:${NAMESPACE}:${ACCOUNT}"
    kubectl delete clusterrolebinding cluster-admin:${NAMESPACE}:${ACCOUNT}
    echo

    _command "kubectl delete serviceaccount ${ACCOUNT} -n ${NAMESPACE}"
    kubectl delete serviceaccount ${ACCOUNT} -n ${NAMESPACE}
}

create_namespace() {
    NAMESPACE=$1

    CHECK=

    _command "kubectl get ns ${NAMESPACE}"
    kubectl get ns ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _echo "${NAMESPACE}"
        echo

        _command "kubectl create ns ${NAMESPACE}"
        kubectl create ns ${NAMESPACE}
        echo
    fi
}

create_service_account() {
    NAMESPACE=$1
    ACCOUNT=$2

    create_namespace ${NAMESPACE}

    CHECK=

    _command "kubectl get sa ${ACCOUNT} -n ${NAMESPACE}"
    kubectl get sa ${ACCOUNT} -n ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _echo "${NAMESPACE}:${ACCOUNT}"
        echo

        _command "kubectl create sa ${ACCOUNT} -n ${NAMESPACE}"
        kubectl create sa ${ACCOUNT} -n ${NAMESPACE}
        echo
    fi
}

create_cluster_role_binding() {
    ROLL=$1
    NAMESPACE=$2
    ACCOUNT=${3:-default}

    create_service_account ${NAMESPACE} ${ACCOUNT}

    CHECK=

    _command "kubectl get clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT}"
    kubectl get clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _echo "${ROLL}:${NAMESPACE}:${ACCOUNT}"
        echo

        _command "kubectl create clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} --clusterrole=${ROLL} --serviceaccount=${NAMESPACE}:${ACCOUNT}"
        kubectl create clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} --clusterrole=${ROLL} --serviceaccount=${NAMESPACE}:${ACCOUNT}
        echo
    fi
}

apply_sample() {
    NAME=${1}
    NAMESPACE=${2}
    INGRESS=${3}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_ingress_nip_io
        fi
    fi

    SAMPLE=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX.yaml)
    get_template sample/${NAME}.yaml ${SAMPLE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            sed -i -e "s/SERVICE_TYPE/LoadBalancer/" ${SAMPLE}
        else
            DOMAIN="${NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            sed -i -e "s/SERVICE_TYPE/ClusterIP/" ${SAMPLE}
            sed -i -e "s/INGRESS_DOMAIN/${DOMAIN}/" ${SAMPLE}
        fi
    fi

    _command "kubectl apply -f ${SAMPLE}"
    kubectl apply -f ${SAMPLE}

    waiting 2
    # waiting_pod "${NAMESPACE}" "${NAME}"

    _command "kubectl get deploy,pod,svc,ing -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_elb_domain ${NAME} ${NAMESPACE}

            echo
            _result "${NAME}: https://${ELB_DOMAIN}"
        else
            echo
            _result "${NAME}: https://${DOMAIN}"
        fi
    fi
}

get_template() {
    rm -rf ${2}
    if [ -f ${SHELL_DIR}/${1} ]; then
        cp -rf ${SHELL_DIR}/${1} ${2}
    else
        curl -sL https://raw.githubusercontent.com/opsnow/kops-cui/master/${1} > ${2}
    fi
    if [ ! -f ${2} ]; then
        _error "Template does not exists. [${1}]"
    fi
}

get_az_list() {
    if [ -z ${AZ_LIST} ]; then
        AZ_LIST="$(aws ec2 describe-availability-zones | jq -r '.AvailabilityZones[] | .ZoneName' | head -3 | tr -s '\r\n' ',' | sed 's/.$//')"
    fi
}

get_master_zones() {
    if [ "${master_count}" == "1" ]; then
        master_zones=$(echo "${AZ_LIST}" | cut -d',' -f1)
    else
        master_zones="${AZ_LIST}"
    fi
}

get_node_zones() {
    if [ "${node_count}" == "1" ]; then
        zones=$(echo "${AZ_LIST}" | cut -d',' -f1)
    else
        zones="${AZ_LIST}"
    fi
}

update_tools() {
    ${SHELL_DIR}/tools.sh
}

update_self() {
    pushd ${SHELL_DIR}
    git pull
    popd

    echo
    _result "Please restart!"
    echo
    exit 0
}

kops_exit() {
    rm -rf /tmp/kops-cui-*

    echo
    _result "Good bye!"
    echo
    exit 0
}

run
