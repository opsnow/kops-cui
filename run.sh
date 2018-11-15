#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

THIS_VERSION=v0.0.0

DEBUG_MODE=true

L_PAD="$(printf %2s)"

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

ISTIO=

cloud=aws
master_size=c4.large
master_count=1
master_zones=
node_size=m4.large
node_count=2
zones=
network_cidr=10.0.0.0/16
networking=calico
topology=public
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

_read_pwd() {
    if [ -z ${TPUT} ] && [ ! -z $2 ]; then
        read -s -p "${L_PAD}$(tput setaf $2)$1$(tput sgr0)" PASSWORD
    else
        read -s -p "${L_PAD}$1" PASSWORD
    fi
}

_replace() {
    if [ "${OS_NAME}" == "darwin" ]; then
        sed -i "" -e "$1" $2
    else
        sed -i -e "$1" $2
    fi
}

_result() {
    echo
    _echo "# $@" 4
}

_command() {
    if [ ! -z ${DEBUG_MODE} ]; then
        echo
        _echo "$ $@" 3
    fi
}

_success() {
    echo
    _echo "+ $@" 2
    _exit 0
}

_error() {
    echo
    _echo "- $@" 1
    _exit 1
}

_exit() {
    echo
    exit $1
}

question() {
    echo
    _read "${1:-"Enter your choice : "}" 6

    if [ ! -z ${2} ]; then
        if ! [[ ${ANSWER} =~ ${2} ]]; then
            ANSWER=
        fi
    fi
}

password() {
    echo
    _read_pwd "${1:-"Enter your password : "}" 6
}

logo() {
    if [ -z ${TPUT} ]; then
        tput clear
    fi

    # figlet kops cui
    echo
    _echo "  _                                _  " 3
    _echo " | | _____  _ __  ___    ___ _   _(_) " 3
    _echo " | |/ / _ \| '_ \/ __|  / __| | | | | " 3
    _echo " |   < (_) | |_) \__ \ | (__| |_| | | " 3
    _echo " |_|\_\___/| .__/|___/  \___|\__,_|_| " 3
    _echo "           |_|                        " 3
}

title() {
    if [ -z ${TPUT} ]; then
        tput clear
    fi

    echo
    _echo "KOPS CUI" 3
    echo
    _echo "${KOPS_STATE_STORE} > ${KOPS_CLUSTER_NAME}" 4
}

press_enter() {
    _result "$(date)"
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
            charts_menu "monitor"
            ;;
        devops)
            charts_menu "devops"
            ;;
        sample)
            sample_menu
            ;;
        istio)
            istio_menu
            ;;
        state)
            state_store
            ;;
    esac
}

select_one() {
    echo

    IDX=0
    while read VAL; do
        IDX=$(( ${IDX} + 1 ))
        printf "%3s. %s\n" "${IDX}" "${VAL}";
    done < ${LIST}

    SELECTED=
    COUNT=$(cat ${LIST} | wc -l | xargs)

    if [ "x${COUNT}" == "x0" ]; then
        return
    fi
    if [ "x${COUNT}" != "x1" ]; then
        COUNT="1-${COUNT}"
    fi

    # select
    question "${1:-"Select one"} (${COUNT}) : " "^[0-9]+$"

    # answer
    if [ -z ${ANSWER} ] || [ "x${ANSWER}" == "x0" ]; then
        return
    fi
    # TEST='^[0-9]+$'
    # if ! [[ ${ANSWER} =~ ${TEST} ]]; then
    #     return
    # fi
    SELECTED=$(sed -n ${ANSWER}p ${LIST})
}

waiting() {
    SEC=${1:-2}

    echo
    progress start

    IDX=0
    while true; do
        if [ "${IDX}" == "${SEC}" ]; then
            break
        fi
        IDX=$(( ${IDX} + 1 ))
        progress ${IDX}
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
        progress ${IDX}
    done

    progress end
    echo
}

waiting_pod() {
    _NS=${1}
    _NM=${2}
    SEC=${3:-10}

    _command "kubectl get pod -n ${_NS} | grep ${_NM}"

    TMP=$(mktemp /tmp/kops-cui-waiting-pod.XXXXXX)

    IDX=0
    while true; do
        kubectl get pod -n ${_NS} | grep ${_NM} | head -1 > ${TMP}
        cat ${TMP}

        READY=$(cat ${TMP} | awk '{print $2}' | cut -d'/' -f1)
        STATUS=$(cat ${TMP} | awk '{print $3}')

        if [ "${STATUS}" == "Running" ] && [ "x${READY}" != "x0" ]; then
            break
        elif [ "${STATUS}" == "Error" ]; then
            _result "${STATUS}"
            break
        elif [ "${STATUS}" == "CrashLoopBackOff" ]; then
            _result "${STATUS}"
            break
        elif [ "x${IDX}" == "x${SEC}" ]; then
            _result "Timeout"
            break
        fi

        IDX=$(( ${IDX} + 1 ))
        sleep 2
    done
}

progress() {
    if [ "$1" == "start" ]; then
        printf '%2s'
    elif [ "$1" == "end" ]; then
        printf '.\n'
    else
        printf '.'
        sleep 2
    fi
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
            _error
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
        echo
        _echo "1. Create Cluster"
    else
        echo
        _echo "1. Get Cluster"
        _echo "2. Edit Cluster"
        _echo "3. Update Cluster"
        _echo "4. Rolling Update"
        _echo "5. Validate Cluster"
        _echo "6. Export Kube Config"
        _echo "7. Change SSH key"
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
        7)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            question "Are you sure? (YES/[no]) : "

            if [ "${ANSWER}" == "YES" ]; then
                kops_secret
                press_enter cluster
            else
                cluster_menu
            fi
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
        12)
            if [ "x${CLUSTER}" == "x0" ]; then
                cluster_menu
                return
            fi

            elb_security
            press_enter cluster
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
            _success "Good bye!"
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

    echo
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
            LIST=${SHELL_DIR}/templates/instances.txt
            select_one
            master_size=${SELECTED:-${master_size}}
            create_menu
            ;;
        2)
            question "Enter master count [${master_count}] : " "^[0-9]+$"
            master_count=${ANSWER:-${master_count}}
            get_master_zones
            create_menu
            ;;
        3)
            LIST=${SHELL_DIR}/templates/instances.txt
            select_one
            node_size=${SELECTED:-${node_size}}
            create_menu
            ;;
        4)
            question "Enter node count [${node_count}] : " "^[0-9]+$"
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
            LIST=${SHELL_DIR}/templates/topology.txt
            select_one
            topology=${SELECTED:-${topology}}
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

            _result "Edit Cluster for Istio"

            echo "spec:"
            echo "  kubeAPIServer:"
            echo "    admissionControl:"
            echo "    - NamespaceLifecycle"
            echo "    - LimitRanger"
            echo "    - ServiceAccount"
            echo "    - PersistentVolumeLabel"
            echo "    - DefaultStorageClass"
            echo "    - DefaultTolerationSeconds"
            echo "    - MutatingAdmissionWebhook"
            echo "    - ValidatingAdmissionWebhook"
            echo "    - ResourceQuota"
            echo "    - NodeRestriction"
            echo "    - Priority"

            _result "Edit InstanceGroup (node) for Autoscaler"

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

    echo
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

            create_cluster_role_binding cluster-admin kube-system dashboard-admin

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

            _result "Edit InstanceGroup (node) for Autoscaler"

            echo "spec:"
            echo "  cloudLabels:"
            echo "    k8s.io/cluster-autoscaler/enabled: \"\""
            echo "    kubernetes.io/cluster/${KOPS_CLUSTER_NAME}: owned"

            press_enter addons
            ;;
        7)
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
            charts_menu "monitor"
            ;;
        13)
            charts_menu "devops"
            ;;
        14)
            istio_menu
            ;;
        *)
            cluster_menu
            ;;
    esac
}

istio_menu() {
    title

    echo
    _echo "1. install"
    echo
    _echo "2. injection show"
    _echo "3. injection enable"
    _echo "4. injection disable"
    echo
    _echo "9. remove"

    question

    case ${ANSWER} in
        1)
            istio_install
            press_enter istio
            ;;
        2)
            istio_injection
            press_enter istio
            ;;
        3)
            istio_injection "enable"
            press_enter istio
            ;;
        4)
            istio_injection "disable"
            press_enter istio
            ;;
        9)
            istio_delete
            press_enter istio
            ;;
        *)
            addons_menu
            ;;
    esac
}

sample_menu() {
    title

    LIST=$(mktemp /tmp/kops-cui-sample-list.XXXXXX)

    # find sample
    ls ${SHELL_DIR}/charts/sample | grep yaml | sort | sed 's/.yaml//' > ${LIST}

    # select
    select_one

    if [ -z ${SELECTED} ]; then
        addons_menu
        return
    fi

    # sample install
    if [ "${SELECTED}" == "configmap" ]; then
        sample_install ${SELECTED} dev
    else
        sample_install ${SELECTED} dev true
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
    echo "ISTIO=${ISTIO}" >> ${CONFIG}

    . ${CONFIG}

    if [ ! -z ${DEBUG_MODE} ]; then
        echo
        cat ${CONFIG}
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
    export ISTIO=

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
            _error
        fi
    fi
}

read_cluster_list() {
    # cluster list
    LIST=$(mktemp /tmp/kops-cui-kops-cluster-list.XXXXXX)

    _command "kops get cluster --state=s3://${KOPS_STATE_STORE}"
    kops get cluster --state=s3://${KOPS_STATE_STORE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

    # select
    select_one

    KOPS_CLUSTER_NAME="${SELECTED}"

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        read_cluster_name
    fi

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        clear_kops_config
        _error
    fi
}

read_cluster_name() {
    # words list
    LIST=${SHELL_DIR}/templates/words.txt

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        DEFAULT="dev"
        question "Enter cluster name [${DEFAULT}] : "

        SELECTED=${ANSWER:-${DEFAULT}}
    fi

    KOPS_CLUSTER_NAME="${SELECTED}.k8s.local"
}

kops_get() {
    _command "kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    _command "kubectl get no"
    kubectl get no
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
        OUT_PATH="terraform-${cloud}-${KOPS_CLUSTER_NAME}"

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
    kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | grep -v "NAME" > ${IG_LIST}

    echo

    IDX=0
    while read VAR; do
        ARR=(${VAR})
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
        ARR=($(sed -n ${ANSWER}p ${IG_LIST}))
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

    _command "kubectl get node"
    kubectl get node

    _command "kubectl get pod -n kube-system"
    kubectl get pod -n kube-system
}

kops_export() {
    rm -rf ~/.kube

    _command "kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_secret() {
    _command "kops delete secret sshpublickey admin --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops delete secret sshpublickey admin --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    _command "kops create secret sshpublickey admin -i ~/.ssh/id_rsa.pub --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops create secret sshpublickey admin -i ~/.ssh/id_rsa.pub --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_delete() {
    efs_delete

    _command "kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    delete_kops_config

    rm -rf ~/.kube ~/.helm ~/.draft
}

get_elb_domain() {
    ELB_DOMAIN=

    if [ -z $2 ]; then
        _command "kubectl get svc --all-namespaces -o wide | grep LoadBalancer | grep $1 | head -1 | awk '{print \$5}'"
    else
        _command "kubectl get svc -n $2 -o wide | grep LoadBalancer | grep $1 | head -1 | awk '{print \$4}'"
    fi

    progress start

    IDX=0
    while true; do
        # ELB Domain 을 획득
        if [ -z $2 ]; then
            ELB_DOMAIN=$(kubectl get svc --all-namespaces -o wide | grep LoadBalancer | grep $1 | head -1 | awk '{print $5}')
        else
            ELB_DOMAIN=$(kubectl get svc -n $2 -o wide | grep LoadBalancer | grep $1 | head -1 | awk '{print $4}')
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
    POD="${1:-nginx-ingress}"

    ELB_NAME=

    get_elb_domain "${POD}"

    if [ -z ${ELB_DOMAIN} ]; then
        return
    fi

    _command "echo ${ELB_DOMAIN} | cut -d'-' -f1"
    ELB_NAME=$(echo ${ELB_DOMAIN} | cut -d'-' -f1)

    _result ${ELB_NAME}
}

get_ingress_nip_io() {
    POD="${1:-nginx-ingress}"

    ELB_IP=

    get_elb_domain "${POD}"

    if [ -z ${ELB_DOMAIN} ]; then
        return
    fi

    _command "dig +short ${ELB_DOMAIN} | head -n 1"

    progress start

    IDX=0
    while true; do
        ELB_IP=$(dig +short ${ELB_DOMAIN} | head -n 1)

        if [ ! -z ${ELB_IP} ]; then
            BASE_DOMAIN="${ELB_IP}.nip.io"
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
    # domain list
    LIST=$(mktemp /tmp/kops-cui-hosted-zones.XXXXXX)

    _command "aws route53 list-hosted-zones | jq -r '.HostedZones[] | .Name' | sed 's/.$//'"
    aws route53 list-hosted-zones | jq -r '.HostedZones[] | .Name' | sed 's/.$//' > ${LIST}

    # select
    select_one

    ROOT_DOMAIN=${SELECTED}
}

get_ssl_cert_arn() {
    if [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # get certificate arn
    _command "aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn'"
    SSL_CERT_ARN=$(aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn')
}

set_record_cname() {
    if [ -z ${ROOT_DOMAIN} ] || [ -z ${BASE_DOMAIN} ] || [ -z ${SSL_CERT_ARN} ]; then
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

    if [ -z ${ZONE_ID} ]; then
        return
    fi

    # domain validate name
    _command "aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Name'"
    CERT_DNS_NAME=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Name')

    if [ -z ${CERT_DNS_NAME} ]; then
        return
    fi

    # domain validate value
    _command "aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Value'"
    CERT_DNS_VALUE=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq -r '.Certificate.DomainValidationOptions[].ResourceRecord | .Value')

    if [ -z ${CERT_DNS_VALUE} ]; then
        return
    fi

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-cname.XXXXXX)
    get_template templates/record-sets-cname.json ${RECORD}

    # replace
    _replace "s/DOMAIN/${CERT_DNS_NAME}/g" ${RECORD}
    _replace "s/DNS_NAME/${CERT_DNS_VALUE}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

set_record_alias() {
    if [ -z ${ROOT_DOMAIN} ] || [ -z ${BASE_DOMAIN} ] || [ -z ${ELB_NAME} ]; then
        return
    fi

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    if [ -z ${ZONE_ID} ]; then
        return
    fi

    # ELB 에서 Hosted Zone ID 를 획득
    _command "aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .CanonicalHostedZoneNameID'"
    ELB_ZONE_ID=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .CanonicalHostedZoneNameID')

    if [ -z ${ELB_ZONE_ID} ]; then
        return
    fi

    # ELB 에서 DNS Name 을 획득
    _command "aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .DNSName'"
    ELB_DNS_NAME=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | jq -r '.LoadBalancerDescriptions[] | .DNSName')

    if [ -z ${ELB_DNS_NAME} ]; then
        return
    fi

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-alias.XXXXXX)
    get_template templates/record-sets-alias.json ${RECORD}

    # replace
    _replace "s/DOMAIN/*.${BASE_DOMAIN}/g" ${RECORD}
    _replace "s/ZONE_ID/${ELB_ZONE_ID}/g" ${RECORD}
    _replace "s/DNS_NAME/${ELB_DNS_NAME}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

set_record_delete() {
    if [ -z ${BASE_DOMAIN} ] || [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    if [ -z ${ZONE_ID} ]; then
        return
    fi

    # record sets
    RECORD=$(mktemp /tmp/kops-cui-record-sets-delete.XXXXXX)
    get_template templates/record-sets-delete.json ${RECORD}

    # replace
    _replace "s/DOMAIN/*.${BASE_DOMAIN}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

set_base_domain() {
    POD="${1:-nginx-ingress}"

    _result "Pending ELB..."

    if [ -z ${BASE_DOMAIN} ]; then
        get_ingress_nip_io ${POD}
    else
        get_ingress_elb_name ${POD}

        set_record_alias
    fi
}

get_base_domain() {
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

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX)
    get_template charts/${NAMESPACE}/${NAME}.yaml ${CHART}

    # certificate
    if [ ! -z ${BASE_DOMAIN} ]; then
        get_ssl_cert_arn

        if [ -z ${SSL_CERT_ARN} ]; then
            set_record_cname
        fi
        if [ -z ${SSL_CERT_ARN} ]; then
            _error "Certificate ARN does not exists. [*.${BASE_DOMAIN}][${REGION}]"
        fi

        _result "CertificateArn: ${SSL_CERT_ARN}"

        _replace "s@aws-load-balancer-ssl-cert:.*@aws-load-balancer-ssl-cert: ${SSL_CERT_ARN}@" ${CHART}
    fi
}

elb_security() {
    LIST=$(mktemp /tmp/kops-cui-elb-list.XXXXXX)

    # elb list
    _command "kubectl get svc --all-namespaces | grep LoadBalancer"
    kubectl get svc --all-namespaces | grep LoadBalancer \
        | awk '{printf "%-20s %-30s %s\n", $1, $2, $5}' > ${LIST}

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        return
    fi

    ELB_NAME=$(echo "${SELECTED}" | awk '{print $3}' | cut -d'-' -f1 | xargs)

    if [ "${ELB_NAME}" == "" ]; then
        return
    fi

    # security groups
    _command "aws elb describe-load-balancers --load-balancer-name ${ELB_NAME}"
    aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} \
        | jq -r '.LoadBalancerDescriptions[].SecurityGroups[]' > ${LIST}

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        return
    fi

    # ingress rules
    _command "aws ec2 describe-security-groups --group-ids ${SELECTED}"
    aws ec2 describe-security-groups --group-ids ${SELECTED} \
        | jq -r '.SecurityGroups[].IpPermissions[] | "\(.IpProtocol) \(.FromPort) \(.IpRanges[].CidrIp)"' > ${LIST}

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        return
    fi

    # aws ec2 describe-security-groups --group-ids ${SELECTED} | jq '.SecurityGroups[].IpPermissions'

    # aws ec2 authorize-security-group-ingress --group-id ${SELECTED} --protocol tcp --port 8080 --cidr 203.0.113.0/24

    # aws ec2 revoke-security-group-ingress --group-id ${SELECTED} --protocol tcp --port 8080 --cidr 203.0.113.0/24

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

efs_create() {
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

    # save config (EFS_FILE_SYSTEM_ID)
    save_kops_config true

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
}

efs_delete() {
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
        aws ec2 delete-security-group --group-id ${EFS_SG_ID}
    fi

    # delete efs
    if [ -n ${EFS_FILE_SYSTEM_ID} ]; then
        echo "Deleting the elastic file system"
        aws efs delete-file-system --file-system-id ${EFS_FILE_SYSTEM_ID} --region ${REGION}
    fi
}

helm_nginx_ingress() {
    helm_check

    NAME="nginx-ingress"
    NAMESPACE=${1:-kube-ingress}

    create_namespace ${NAMESPACE}

    get_base_domain

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

    # save config (INGRESS)
    INGRESS=true
    save_kops_config true

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}" 20

    _command "helm history ${NAME}"
    helm history ${NAME}

    _command "kubectl get deploy,pod,svc -n ${NAMESPACE}"
    kubectl get deploy,pod,svc -n ${NAMESPACE}

    set_base_domain ${NAME}
}

helm_install() {
    helm_check

    NAME=${1}
    NAMESPACE=${2}
    INGRESS=${3}
    DOMAIN=

    # for efs-provisioner
    if [ "${NAME}" == "efs-provisioner" ]; then
        efs_create
    fi

    create_namespace ${NAMESPACE}

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX)
    get_template charts/${NAMESPACE}/${NAME}.yaml ${CHART}

    _replace "s/AWS_REGION/${REGION}/" ${CHART}
    _replace "s/CLUSTER_NAME/${KOPS_CLUSTER_NAME}/" ${CHART}

    # for jenkins
    if [ "${NAME}" == "jenkins" ]; then
        # admin password
        read_password ${CHART}

        ${SHELL_DIR}/jenkins/jobs.sh ${CHART}
    fi

    # for grafana
    if [ "${NAME}" == "grafana" ]; then
        # admin password
        read_password ${CHART}

        # ldap
        question "Enter grafana LDAP secret : "
        GRAFANA_LDAP="${ANSWER}"
        _result "secret: ${GRAFANA_LDAP}"

        if [ "${GRAFANA_LDAP}" != "" ]; then
            _replace "s/#:LDAP://" ${CHART}
            _replace "s/GRAFANA_LDAP/${GRAFANA_LDAP}/" ${CHART}
        fi
    fi

    # for fluentd-elasticsearch
    if [ "${NAME}" == "fluentd-elasticsearch" ]; then
        # host
        question "Enter elasticsearch host [elasticsearch-client] : "
        CUSTOM_HOST=${ANSWER:-elasticsearch-client}
        _result "host: ${CUSTOM_HOST}"
        _replace "s/CUSTOM_HOST/${CUSTOM_HOST}/" ${CHART}

        # port
        question "Enter elasticsearch port [9200]: "
        CUSTOM_PORT=${ANSWER:-9200}
        _result "port: ${CUSTOM_PORT}"
        _replace "s/CUSTOM_PORT/${CUSTOM_PORT}/" ${CHART}
    fi

    # for efs-provisioner
    if [ ! -z ${EFS_FILE_SYSTEM_ID} ]; then
        _replace "s/#:EFS://" ${CHART}
        _replace "s/EFS_FILE_SYSTEM_ID/${EFS_FILE_SYSTEM_ID}/" ${CHART}
    fi

    # for istio
    if [ "${ISTIO}" == "true" ]; then
        _replace "s/ISTIO_ENABLED/true/" ${CHART}
    else
        _replace "s/ISTIO_ENABLED/false/" ${CHART}
    fi

    # ingress
    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            _replace "s/SERVICE_TYPE/LoadBalancer/" ${CHART}
            _replace "s/INGRESS_ENABLED/false/" ${CHART}
        else
            DOMAIN="${NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            _replace "s/SERVICE_TYPE/ClusterIP/" ${CHART}
            _replace "s/INGRESS_ENABLED/true/" ${CHART}
            _replace "s/INGRESS_DOMAIN/${DOMAIN}/" ${CHART}
        fi
    fi

    # chart version
    CHART_VERSION=$(cat ${CHART} | grep chart-version | awk '{print $3}')

    # if [ -z ${CHART_VERSION} ] || [ "${CHART_VERSION}" == "latest" ]; then
    #     # https://kubernetes-charts.storage.googleapis.com/
    #     CHART_VERSION=${CHART_VERSION:-latest}
    # fi

    # check exist persistent volume
    PVC_LIST=$(mktemp /tmp/pvc-${NAME}.XXXXXX.yaml)
    cat ${CHART} | grep chart-pvc | awk '{print $3,$4,$5}' > ${PVC_LIST}
    while IFS='' read -r line || [[ -n "$line" ]]; do
        ARR=(${line})
        check_exist_pv ${NAMESPACE} ${ARR[0]} ${ARR[1]} ${ARR[2]}
        RELEASED=$?
        if [ "${RELEASED}" -gt "0" ]; then
            echo "  To use an existing volume, remove the PV's '.claimRef.uid' attribute to make the PV an 'Available' status and try again."
            return;
        fi
    done < "${PVC_LIST}"

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

    _command "kubectl get deploy,pod,svc,ing,pv -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing,pv -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            get_elb_domain ${NAME} ${NAMESPACE}

            _result "${NAME}: http://${ELB_DOMAIN}"
        else
            if [ -z ${ROOT_DOMAIN} ]; then
                _result "${NAME}: http://${DOMAIN}"
            else
                _result "${NAME}: https://${DOMAIN}"
            fi
        fi
    fi
}

check_exist_pv() {
    NAMESPACE=${1}
    PVC_NAME=${2}
    PVC_ACCESS_MODE=${3}
    PVC_SIZE=${4}

    PV_NAMES=$(kubectl get pv | grep ${PVC_NAME} | awk '{print $1}')
    for PvName in ${PV_NAMES}; do
        if [ "$(kubectl get pv -o json ${PvName} | jq -r '.spec.claimRef.name')" == "${PVC_NAME}" ]; then
            PV_NAME=${PvName}
        fi
    done

    if [ -z ${PV_NAME} ]; then
        echo "No PersistentVolume."
        # Create a new pvc
        create_pvc ${NAMESPACE} ${PVC_NAME} ${PVC_ACCESS_MODE} ${PVC_SIZE}
    else
        PV_JSON=$(mktemp /tmp/kops-cui-pv-${PVC_NAME}.XXXXXX)

        _command "kubectl get pv -o json ${PV_NAME}"
        kubectl get pv -o json ${PV_NAME} > ${PV_JSON}

        PV_STATUS=$(cat ${PV_JSON} | jq -r '.status.phase')
        echo "PV is in '${PV_STATUS}' status."
        
        if [ "${PV_STATUS}" == "Available" ]; then
            # If PVC for PV is not present, create PVC
            PVC_TMP=$(kubectl get pvc -n ${NAMESPACE} ${PVC_NAME} | grep ${PVC_NAME} | awk '{print $1}')
            if [ "${PVC_NAME}" != "${PVC_TMP}" ]; then
                # create a static PVC 
                create_pvc ${NAMESPACE} ${PVC_NAME} ${PVC_ACCESS_MODE} ${PVC_SIZE} ${PV_NAME}
            fi
        elif [ "${PV_STATUS}" == "Released" ]; then
            return 1
        fi
    fi
}

create_pvc() {
    NAMESPACE=${1}
    PVC_NAME=${2}
    PVC_ACCESS_MODE=${3}
    PVC_SIZE=${4}
    PV_NAME=${5}

    PVC=$(mktemp /tmp/kops-cui-pvc-${PVC_NAME}.XXXXXX.yaml)
    get_template templates/pvc.yaml ${PVC}

    _replace "s/PVC_NAME/${PVC_NAME}/" ${PVC}
    _replace "s/PVC_ACCESS_MODE/${PVC_ACCESS_MODE}/" ${PVC}
    _replace "s/PVC_SIZE/${PVC_SIZE}/" ${PVC}

    # for efs-provisioner
    if [ ! -z ${EFS_FILE_SYSTEM_ID} ]; then
        _replace "s/#:EFS://" ${PVC}
    fi

    # for static pvc
    if [ ! -z ${PV_NAME} ]; then
        _replace "s/#:PV://" ${PVC}
        _replace "s/PV_NAME/${PV_NAME}/" ${PVC}
    fi
    
    echo ${PVC}

    _command "kubectl create -n ${NAMESPACE} -f ${PVC}"
    kubectl create -n ${NAMESPACE} -f ${PVC}

    waiting_for isBound ${NAMESPACE} ${PVC_NAME}

    _command "kubectl get pvc,pv -n ${NAMESPACE}"
    kubectl get pvc,pv -n ${NAMESPACE}
}

isBound() {
    NAMESPACE=${1}
    PVC_NAME=${2}

    PVC_STATUS=$(kubectl get pvc -n ${NAMESPACE} ${PVC_NAME} -o json | jq -r '.status.phase')
    if [ "${PVC_STATUS}" != "Bound" ]; then 
        return 1;
    fi
}

helm_delete() {
    NAME=

    LIST=$(mktemp /tmp/kops-cui-helm-list.XXXXXX)

    _command "helm ls --all"

    # find sample
    helm ls --all | grep -v "NAME" | sort \
        | awk '{printf "%-30s %-20s %-5s %-12s %s\n", $1, $11, $2, $8, $9}' > ${LIST}

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

    _command "helm repo update"
    helm repo update

    _command "helm ls"
    helm ls
}

create_namespace() {
    NAMESPACE=$1

    CHECK=

    _command "kubectl get ns ${NAMESPACE}"
    kubectl get ns ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _result "${NAMESPACE}"

        _command "kubectl create ns ${NAMESPACE}"
        kubectl create ns ${NAMESPACE}
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
        _result "${NAMESPACE}:${ACCOUNT}"

        _command "kubectl create sa ${ACCOUNT} -n ${NAMESPACE}"
        kubectl create sa ${ACCOUNT} -n ${NAMESPACE}
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
        _result "${ROLL}:${NAMESPACE}:${ACCOUNT}"

        _command "kubectl create clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} --clusterrole=${ROLL} --serviceaccount=${NAMESPACE}:${ACCOUNT}"
        kubectl create clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} --clusterrole=${ROLL} --serviceaccount=${NAMESPACE}:${ACCOUNT}
    fi

    SECRET=$(kubectl get secret -n ${NAMESPACE} | grep ${ACCOUNT}-token | awk '{print $1}')
    kubectl describe secret ${SECRET} -n ${NAMESPACE} | grep 'token:'
}

istio_install() {
    helm_check

    NAME="istio"
    NAMESPACE="istio-system"

    create_namespace ${NAMESPACE}

    # get_base_domain

    ISTIO_TMP=/tmp/kops-cui-istio
    mkdir -p ${ISTIO_TMP}

    VERSION=$(curl -s https://api.github.com/repos/${NAME}/${NAME}/releases/latest | jq -r '.tag_name')

    # istio download
    if [ ! -d ${ISTIO_TMP}/${NAME}-${VERSION} ]; then
        pushd ${ISTIO_TMP}
        curl -sL https://git.io/getLatestIstio | sh -
        popd
    fi

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX)
    get_template charts/istio/${NAME}.yaml ${CHART}

    # ingress
    if [ -z ${BASE_DOMAIN} ]; then
        _replace "s/SERVICE_TYPE/LoadBalancer/g" ${CHART}
        _replace "s/INGRESS_ENABLED/false/g" ${CHART}
    else
        _replace "s/SERVICE_TYPE/ClusterIP/g" ${CHART}
        _replace "s/INGRESS_ENABLED/true/g" ${CHART}
        _replace "s/BASE_DOMAIN/${BASE_DOMAIN}/g" ${CHART}
    fi

    # admin password
    read_password ${CHART}

    ISTIO_DIR=${ISTIO_TMP}/${NAME}-${VERSION}/install/kubernetes/helm/istio

    # helm install
    _command "helm upgrade --install ${NAME} ${ISTIO_DIR} --namespace ${NAMESPACE} --values ${CHART}"
    helm upgrade --install ${NAME} ${ISTIO_DIR} --namespace ${NAMESPACE} --values ${CHART}

    # save config (ISTIO)
    ISTIO=true
    save_kops_config true

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}"

    _command "helm history ${NAME}"
    helm history ${NAME}

    _command "kubectl get deploy,pod,svc -n ${NAMESPACE}"
    kubectl get deploy,pod,svc -n ${NAMESPACE}

    # set_base_domain "istio-ingressgateway"

    _command "kubectl get ing -n ${NAMESPACE}"
    kubectl get ing -n ${NAMESPACE}
}

istio_injection() {
    CMD=$1

    if [ -z ${CMD} ]; then
        _command "kubectl get ns --show-labels"
        kubectl get ns --show-labels
        return
    fi

    LIST=$(mktemp /tmp/kops-cui-ns-list.XXXXXX)

    # find sample
    kubectl get ns | grep -v "NAME" | awk '{print $1}' > ${LIST}

    # select
    select_one

    if [ -z ${SELECTED} ]; then
        istio_menu
        return
    fi

    # istio-injection
    if [ "${CMD}" == "enable" ]; then
        kubectl label namespace ${SELECTED} istio-injection=enabled
    else
        kubectl label namespace ${SELECTED} istio-injection-
    fi

    press_enter istio
}

istio_delete() {
    NAME="istio"
    NAMESPACE="istio-system"

    ISTIO_TMP=/tmp/kops-cui-istio
    mkdir -p ${ISTIO_TMP}

    VERSION=$(curl -s https://api.github.com/repos/${NAME}/${NAME}/releases/latest | jq -r '.tag_name')

    # istio download
    if [ ! -d ${ISTIO_TMP}/${NAME}-${VERSION} ]; then
        pushd ${ISTIO_TMP}
        curl -sL https://git.io/getLatestIstio | sh -
        popd
    fi

    ISTIO_DIR=${ISTIO_TMP}/${NAME}-${VERSION}/install/kubernetes/helm/istio

    # helm delete
    _command "helm delete --purge ${NAME}"
    helm delete --purge ${NAME}

    # save config (ISTIO)
    ISTIO=
    save_kops_config true

    _command "kubectl delete -f ${ISTIO_DIR}/templates/crds.yaml"
    kubectl delete -f ${ISTIO_DIR}/templates/crds.yaml

    _command "kubectl delete namespace ${NAMESPACE}"
    kubectl delete namespace ${NAMESPACE}
}

sample_install() {
    helm_check

    NAME=${1}
    NAMESPACE=${2}
    INGRESS=${3}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_ingress_nip_io
        fi
    fi

    CHART=$(mktemp /tmp/kops-cui-${NAME}.XXXXXX)
    get_template charts/sample/${NAME}.yaml ${CHART}

    # profile
    _replace "s/profile:.*/profile: ${NAMESPACE}/" ${CHART}

    # ingress
    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            _replace "s/SERVICE_TYPE/LoadBalancer/" ${CHART}
            _replace "s/INGRESS_ENABLED/false/" ${CHART}
        else
            _replace "s/SERVICE_TYPE/ClusterIP/" ${CHART}
            _replace "s/INGRESS_ENABLED/true/" ${CHART}
            _replace "s/BASE_DOMAIN/${BASE_DOMAIN}/" ${CHART}
        fi
    fi

    # has configmap
    COUNT=$(kubectl get configmap -n ${NAMESPACE} 2>&1 | grep ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${COUNT}" != "x0" ]; then
        _replace "s/CONFIGMAP_ENABLED/true/" ${CHART}
    else
        _replace "s/CONFIGMAP_ENABLED/false/" ${CHART}
    fi

    # has secret
    COUNT=$(kubectl get secret -n ${NAMESPACE} 2>&1 | grep ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${COUNT}" != "x0" ]; then
        _replace "s/SECRET_ENABLED/true/" ${CHART}
    else
        _replace "s/SECRET_ENABLED/false/" ${CHART}
    fi

    # for istio
    if [ "${ISTIO}" == "true" ]; then
        _replace "s/ISTIO_ENABLED/true/" ${CHART}
    else
        _replace "s/ISTIO_ENABLED/false/" ${CHART}
    fi

    SAMPLE_DIR=${SHELL_DIR}/charts/sample/${NAME}

    # helm install
    _command "helm upgrade --install ${NAME}-${NAMESPACE} ${SAMPLE_DIR} --namespace ${NAMESPACE} --values ${CHART}"
    helm upgrade --install ${NAME}-${NAMESPACE} ${SAMPLE_DIR} --namespace ${NAMESPACE} --values ${CHART}

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}-${NAMESPACE}"

    _command "helm history ${NAME}-${NAMESPACE}"
    helm history ${NAME}-${NAMESPACE}

    _command "kubectl get deploy,pod,svc,ing -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_elb_domain ${NAME}-${NAMESPACE} ${NAMESPACE}

            _result "${NAME}: http://${ELB_DOMAIN}"
        else
            DOMAIN="${NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            if [ -z ${ROOT_DOMAIN} ]; then
                _result "${NAME}: http://${DOMAIN}"
            else
                _result "${NAME}: https://${DOMAIN}"
            fi
        fi
    fi
}

read_password() {
    CHART=${1}

    # admin password
    DEFAULT="password"
    password "Enter admin password [${DEFAULT}] : "
    echo

    _replace "s/PASSWORD/${PASSWORD:-${DEFAULT}}/g" ${CHART}
}

get_template() {
    rm -rf ${2}
    if [ -f ${SHELL_DIR}/${1} ]; then
        cat ${SHELL_DIR}/${1} > ${2}
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

    _result "Please restart!"
    _exit 0
}

run
