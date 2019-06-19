#!/bin/bash

SHELL_DIR=$(dirname $0)

. ${SHELL_DIR}/common.sh
. ${SHELL_DIR}/default.sh

################################################################################

title() {
    if [ "${TPUT}" != "" ]; then
        tput clear
    fi

    echo
    _echo "${THIS_NAME}" 3
    echo
    _echo "${KOPS_STATE_STORE} > ${KOPS_CLUSTER_NAME}" 4
}

press_enter() {
    _result "$(date)"

    _read "Press Enter to continue..." 5
    echo

    case ${1} in
        cluster)
            cluster_menu
            ;;
        create)
            create_menu
            ;;
        state)
            state_store
            ;;
    esac
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

prepare() {
    logo

    mkdir -p ~/.ssh
    mkdir -p ~/.aws
    mkdir -p ${SHELL_DIR}/build/${THIS_NAME}

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

    if [ ! -z ${NEED_TOOL} ]; then
        question "Do you want to install the required tools? (awscli,kubectl,kops...) [Y/n] : "

        if [ "${ANSWER:-Y}" == "Y" ]; then
            ${SHELL_DIR}/tools.sh
        else
            _error
        fi
    fi
	
	aws s3 ls 2>temp

	if grep -q "Unable to" temp; then
		echo "There is no aws config in here" 
		aws configure
		REGION="$(aws configure get default.region)"
	else
		REGION="$(aws configure get default.region)"
	fi

	rm -f temp
}

run() {
    prepare

    state_store
}

state_store() {
    read_state_store

    read_cluster_list

    read_kops_config

    save_kops_config

    get_kops_cluster

    if [ "x${CLUSTER}" != "x0" ]; then
        kops_export
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
    fi

    echo
    _echo "u. update self"
    _echo "t. update tools"

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

            hint_istio
            hint_cluster_autoscaler

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
                # press_enter state
            else
                cluster_menu
            fi
            ;;
        u)
            update_self
            press_enter cluster
            ;;
        t)
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
            save_kops_config

            kops_create

            hint_istio
            hint_cluster_autoscaler

            press_enter

            get_kops_cluster

            cluster_menu
            ;;
        t)
            KOPS_TERRAFORM=true
            save_kops_config

            kops_create

            hint_cluster_autoscaler

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

hint_istio() {
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
}

hint_cluster_autoscaler() {
    _result "Edit InstanceGroup (node) for Autoscaler"

    echo "spec:"
    echo "  cloudLabels:"
    echo "    k8s.io/cluster-autoscaler/enabled: \"\""
    echo "    kubernetes.io/cluster/${KOPS_CLUSTER_NAME}: owned"
}

get_kops_cluster() {
    _command "kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | wc -l | xargs"
    CLUSTER=$(kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | wc -l | xargs)

    _command "kubectl config current-context"
    CURRENT=$(kubectl config current-context)

    if [ "${CURRENT}" != "${KOPS_CLUSTER_NAME}" ]; then
        _command "kubectl config unset current-context"
        kubectl config unset current-context
    fi
}

read_kops_config() {
    if [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        _command "aws s3 ls s3://${KOPS_STATE_STORE} | grep ${KOPS_CLUSTER_NAME}.kops-cui | wc -l | xargs"
        COUNT=$(aws s3 ls s3://${KOPS_STATE_STORE} | grep ${KOPS_CLUSTER_NAME}.kops-cui | wc -l | xargs)

        if [ "x${COUNT}" != "x0" ]; then
            CONFIG=${SHELL_DIR}/build/${THIS_NAME}/kops-config.sh

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

    if [ -z ${EFS_ID} ] && [ ! -z ${EFS_FILE_SYSTEM_ID} ]; then
        CLUSTER_NAME="${KOPS_CLUSTER_NAME}"
        EFS_ID="${EFS_FILE_SYSTEM_ID}"

        # save config to cluster
        config_save

        S3_SYNC=true
    fi

    CONFIG=${SHELL_DIR}/build/${THIS_NAME}/kops-config.sh
    echo "# kops config" > ${CONFIG}
    echo "KOPS_STATE_STORE=${KOPS_STATE_STORE}" >> ${CONFIG}
    echo "KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}" >> ${CONFIG}
    echo "KOPS_TERRAFORM=${KOPS_TERRAFORM}" >> ${CONFIG}
    echo "ROOT_DOMAIN=${ROOT_DOMAIN}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}
    echo "EFS_ID=${EFS_ID}" >> ${CONFIG}
    echo "ISTIO=${ISTIO}" >> ${CONFIG}

    . ${CONFIG}

    if [ ! -z ${S3_SYNC} ] && [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        _command "aws s3 cp ${CONFIG} s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui"
        aws s3 cp ${CONFIG} s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui --quiet
    fi
}

read_state_store() {
    # state store list
    LIST=${SHELL_DIR}/build/${THIS_NAME}/kops-state-store-list
    
	_command "aws s3 ls | grep kops-state"
    aws s3 ls | grep kops-state | awk '{print $3}' > ${LIST}
    
	# select
    select_one

    KOPS_STATE_STORE="${SELECTED}"

    if [ -z ${KOPS_STATE_STORE} ]; then
        DEFAULT=$(aws s3 ls | grep kops-state | head -1 | awk '{print $3}')
        if [ -z ${DEFAULT} ]; then
            DEFAULT="kops-state-$(whoami)"
        fi

        question "Enter cluster store [${DEFAULT}] : "

        KOPS_STATE_STORE=${ANSWER:-${DEFAULT}}
    fi
    if [ -z ${KOPS_STATE_STORE} ]; then
        _error
    fi

    # S3 Bucket
    BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq -r '.Owner.ID')
    if [ -z ${BUCKET} ]; then
        _command "aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}"
        aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}

        waiting 2

        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq -r '.Owner.ID')
        if [ -z ${BUCKET} ]; then
            _error
        fi
    fi
}

read_cluster_list() {
    # cluster list
    LIST=${SHELL_DIR}/build/${THIS_NAME}/kops-cluster-list

    _command "kops get cluster --state=s3://${KOPS_STATE_STORE}"
    kops get cluster --state=s3://${KOPS_STATE_STORE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

    # select
    select_one

    KOPS_CLUSTER_NAME="${SELECTED}"

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        read_cluster_name
    fi

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        _error
    fi
}

read_cluster_name() {
    # words list
    LIST=${SHELL_DIR}/templates/words.txt

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        DEFAULT="dev.k8s.local"
        question "Enter cluster name [${DEFAULT}] : "

        KOPS_CLUSTER_NAME=${ANSWER:-${DEFAULT}}
    else
        KOPS_CLUSTER_NAME="${SELECTED}.k8s.local"
    fi
}

kops_get() {
    _command "kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    _command "kubectl cluster-info"
    kubectl cluster-info

    _command "kubectl get node"
    kubectl get node
}

kops_create() {
    KOPS_CREATE=${SHELL_DIR}/build/${THIS_NAME}/kops-create.sh

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
        TF_PATH="terraform-${cloud}-${KOPS_CLUSTER_NAME}"
        mkdir -p ${TF_PATH}

        echo "    --target=terraform " >> ${KOPS_CREATE}
        echo "    --out=${TF_PATH} "   >> ${KOPS_CREATE}
    fi

    cat ${KOPS_CREATE}
    echo

    $(cat ${KOPS_CREATE})
}

kops_edit() {
    LIST=${SHELL_DIR}/build/${THIS_NAME}/kops-ig-list

    _command "kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | grep -v "NAME" > ${LIST}

    echo

    IDX=0
    while read VAR; do
        ARR=(${VAR})
        IDX=$(( ${IDX} + 1 ))

        _echo "${IDX}. ${ARR[0]}"
    done < ${LIST}

    echo
    _echo "0. cluster"

    question

    SELECTED=

    if [ "x${ANSWER}" == "x0" ]; then
        SELECTED="cluster"
    elif [ ! -z ${ANSWER} ]; then
        ARR=($(sed -n ${ANSWER}p ${LIST}))
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
        TF_PATH="terraform-${cloud}-${KOPS_CLUSTER_NAME}"
        mkdir -p ${TF_PATH}

        _command "kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --target=terraform --out=${TF_PATH}"
        kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --target=terraform --out=${TF_PATH}
    fi
}

kops_rolling_update() {
    if [ -z ${KOPS_TERRAFORM} ]; then
        _command "kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
        kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes
    else
        _command "kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --cloudonly --force"
        kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes --cloudonly --force
    fi
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
    _command "kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    _command "kubectl config use-context ${KOPS_CLUSTER_NAME}"
    kubectl config use-context ${KOPS_CLUSTER_NAME}
}

kops_secret() {
    _command "kops delete secret sshpublickey admin --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops delete secret sshpublickey admin --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    _command "kops create secret sshpublickey admin -i ~/.ssh/id_rsa.pub --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}"
    kops create secret sshpublickey admin -i ~/.ssh/id_rsa.pub --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_delete() {
    efs_delete

    elb_delete

    _command "kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes"
    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    _command "kubectl config unset current-context"
    kubectl config unset current-context

    _success
}

efs_delete() {
    if [ "${EFS_ID}" != "" ]; then
        _result "EFS_ID: ${EFS_ID}"

        _error "Please remove EFS first."
    fi
}

elb_delete() {
    LIST=${SHELL_DIR}/build/${THIS_NAME}/elb-list

    kubectl get svc --all-namespaces | grep LoadBalancer | awk '{print $5}' | cut -d'-' -f1 > ${LIST}

    while read VAL; do
        _command "aws elb delete-load-balancer --load-balancer-name ${VAL}"
        aws elb delete-load-balancer --load-balancer-name ${VAL}
    done < ${LIST}
}

run
