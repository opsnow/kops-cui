#!/bin/bash

SHELL_DIR=$(dirname "$0")

L_PAD="$(printf %3s)"

ANSWER=
CLUSTER=

REGION=
AZ_LIST=

KOPS_STATE_STORE=
KOPS_CLUSTER_NAME=

ROOT_DOMAIN=
BASE_DOMAIN=

cloud=aws
master_size=c4.large
master_count=1
master_zones=
node_size=t2.medium
node_count=2
zones=
network_cidr=10.10.0.0/16
networking=calico

mkdir -p ~/.kops-cui

CONFIG=~/.kops-cui/config
if [ -f ${CONFIG} ]; then
    . ${CONFIG}
fi

print() {
    echo -e "${L_PAD}$@"
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

question() {
    Q=$1
    if [ "$Q" == "" ]; then
        Q="Enter your choice : "
    fi
    read -p "${L_PAD}$(tput setaf 2)$Q$(tput sgr0)" ANSWER
}

waiting() {
    echo
    read -p "${L_PAD}$(tput setaf 4)Press Enter to continue...$(tput sgr0)"
    echo
}

error() {
    echo
    tput setaf 1
    print "$@"
    tput sgr0
    echo
    exit 1
}

logo() {
    tput clear

    echo
    echo
    tput setaf 3
    print "  _  _____  ____  ____     ____ _   _ ___  "
    print " | |/ / _ \|  _ \/ ___|   / ___| | | |_ _| "
    print " | ' / | | | |_) \___ \  | |   | | | || |  "
    print " | . \ |_| |  __/ ___) | | |___| |_| || |  "
    print " |_|\_\___/|_|   |____/   \____|\___/|___|  by nalbam "
    tput sgr0
    echo
}

title() {
    tput clear

    echo
    echo
    tput setaf 3 && tput bold
    print "KOPS CUI"
    tput sgr0
    echo
    print "${KOPS_STATE_STORE} > ${KOPS_CLUSTER_NAME}"
    echo
}

prepare() {
    logo

    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -q -f ~/.ssh/id_rsa -N ''
    fi

    NEED_TOOL=
    command -v jq > /dev/null      || export NEED_TOOL=jq
    command -v git > /dev/null     || export NEED_TOOL=git
    command -v wget > /dev/null    || export NEED_TOOL=wget
    command -v aws > /dev/null     || export NEED_TOOL=awscli
    command -v kubectl > /dev/null || export NEED_TOOL=kubectl
    command -v kops > /dev/null    || export NEED_TOOL=kops

    if [ "${NEED_TOOL}" != "" ]; then
        echo
        question "Do you want to install the required tools? (awscli,kubectl,kops...) [Y/n] : "
        echo

        if [ "${ANSWER}" == "" ]; then
            ANSWER="Y"
        fi

        if [ "${ANSWER}" == "Y" ]; then
            ${SHELL_DIR}/helper/bastion.sh
        else
            error
        fi
    fi

    # iam user
    IAM_USER=$(aws iam get-user | grep Arn | cut -d'"' -f4 | cut -d':' -f5)
    if [ "${IAM_USER}" == "" ]; then
        aws configure

        IAM_USER=$(aws iam get-user | grep Arn | cut -d'"' -f4 | cut -d':' -f5)
        if [ "${IAM_USER}" == "" ]; then
            clear_kops_config
            error
        fi
    fi

    REGION="$(aws configure get profile.default.region)"

    state_store
}

state_store() {
    logo

    read_state_store

    read_cluster_list

    save_kops_config

    get_kops_cluster

    cluster_menu
}

cluster_menu() {
    title

    if [ "${CLUSTER}" == "0" ]; then
        print "1. Create Cluster"
        print "2. Update Tools"
    else
        print "1. Get Cluster"
        print "2. Edit Cluster"
        print "3. Update Cluster"
        print "4. Rolling Update Cluster"
        print "5. Validate Cluster"
        print "6. Export Kubernetes Config"
        print "7. Addons..."
        echo
        print "9. Delete Cluster"
    fi

    echo
    question
    echo

    case ${ANSWER} in
        1)
            if [ "${CLUSTER}" == "0" ]; then
                create_cluster
            else
                kops_get
            fi
            ;;
        2)
            if [ "${CLUSTER}" == "0" ]; then
                install_tools
            else
                kops_edit
            fi
            ;;
        3)
            kops_update
            ;;
        4)
            kops_rolling_update
            ;;
        5)
            kops_validate
            ;;
        6)
            kops_export
            ;;
        7)
            addons_menu
            ;;
        9)
            question "Are you sure? (YES/[no]) : "
            echo

            if [ "${ANSWER}" == "YES" ]; then
                kops_delete
            else
                cluster_menu
            fi
            ;;
        *)
            cluster_menu
            ;;
    esac
}

addons_menu() {
    title

    print "1. Ingress Controller"
    print "2. Dashboard"
    print "3. Heapster (deprecated)"
    print "4. Metrics Server"
    print "5. Cluster Autoscaler"
    echo
    print "7. Sample Spring App"

    echo
    question
    echo

    case ${ANSWER} in
        1)
            apply_ingress_controller
            ;;
        2)
            apply_dashboard
            ;;
        3)
            apply_heapster
            ;;
        4)
            apply_metrics_server
            ;;
        5)
            apply_cluster_autoscaler
            ;;
        7)
            apply_sample_spring
            ;;
        *)
            cluster_menu
            ;;
    esac
}

create_cluster() {
    title

    get_az_list

    get_master_zones
    get_node_zones

    print "   cloud=${cloud}"
    print "   name=${KOPS_CLUSTER_NAME}"
    print "   state=s3://${KOPS_STATE_STORE}"
    print "1. master-size=${master_size}"
    print "2. master-count=${master_count}"
    print "   master-zones=${master_zones}"
    print "4. node-size=${node_size}"
    print "5. node-count=${node_count}"
    print "   zones=${zones}"
    print "7. network-cidr=${network_cidr}"
    print "8. networking=${networking}"
    echo
    print "0. create"

    echo
    question
    echo

    case ${ANSWER} in
        1)
            question "Enter master size [${master_size}] : "
            if [ "${ANSWER}" != "" ]; then
                master_size=${ANSWER}
            fi
            create_cluster
            ;;
        2)
            question "Enter master count [${master_count}] : "
            if [ "${ANSWER}" != "" ]; then
                master_count=${ANSWER}
                get_master_zones
            fi
            create_cluster
            ;;
        3)
            create_cluster
            ;;
        4)
            question "Enter node size [${node_size}] : "
            if [ "${ANSWER}" != "" ]; then
                node_size=${ANSWER}
            fi
            create_cluster
            ;;
        5)
            question "Enter node count [${node_count}] : "
            if [ "${ANSWER}" != "" ]; then
                node_count=${ANSWER}
                get_node_zones
            fi
            create_cluster
            ;;
        6)
            create_cluster
            ;;
        7)
            question "Enter network cidr [${network_cidr}] : "
            if [ "${ANSWER}" != "" ]; then
                network_cidr=${ANSWER}
            fi
            create_cluster
            ;;
        8)
            question "Enter networking [${networking}] : "
            if [ "${ANSWER}" != "" ]; then
                networking=${ANSWER}
            fi
            create_cluster
            ;;
        0)
            kops create cluster \
                --cloud=${cloud} \
                --name=${KOPS_CLUSTER_NAME} \
                --state=s3://${KOPS_STATE_STORE} \
                --master-size=${master_size} \
                --master-count=${master_count} \
                --master-zones=${master_zones} \
                --node-size=${node_size} \
                --node-count=${node_count} \
                --zones=${zones} \
                --network-cidr=${network_cidr} \
                --networking=${networking}

            waiting

            get_kops_cluster

            cluster_menu
            ;;
        *)
            get_kops_cluster

            cluster_menu
            ;;
    esac
}

get_kops_cluster() {
    CLUSTER=$(kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} | wc -l | xargs)
}

save_kops_config() {
    echo "# kops config" > ${CONFIG}
    echo "KOPS_STATE_STORE=${KOPS_STATE_STORE}" >> ${CONFIG}
    echo "KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}" >> ${CONFIG}
    echo "ROOT_DOMAIN=${ROOT_DOMAIN}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}
}

clear_kops_config() {
    #KOPS_STATE_STORE=
    KOPS_CLUSTER_NAME=
    ROOT_DOMAIN=
    BASE_DOMAIN=

    save_kops_config
    . ${CONFIG}
}

read_state_store() {
    # username
    USER=${USER:=$(whoami)}

    if [ "${KOPS_STATE_STORE}" == "" ]; then
        DEFAULT="kops-state-${USER}"
    else
        DEFAULT="${KOPS_STATE_STORE}"
    fi

    echo
    question "Enter cluster store [${DEFAULT}] : "
    echo

    if [ "${ANSWER}" == "" ]; then
        KOPS_STATE_STORE="${DEFAULT}"
    else
        KOPS_STATE_STORE="${ANSWER}"
    fi

    # S3 Bucket
    BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
    if [ "${BUCKET}" == "" ]; then
        aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}
        sleep 1

        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
        if [ "${BUCKET}" == "" ]; then
            KOPS_STATE_STORE=
            clear_kops_config
            error
        fi
    fi
}

read_cluster_list() {
    CLUSTER_LIST=/tmp/kops-cluster-list

    kops get cluster --state=s3://${KOPS_STATE_STORE} > ${CLUSTER_LIST}

    IDX=0
    while read VAR; do
        ARR=(${VAR})

        if [ "${ARR[0]}" == "NAME" ]; then
            continue
        fi

        IDX=$(( ${IDX} + 1 ))

        print "${IDX}. ${ARR[0]}"
    done < ${CLUSTER_LIST}

    if [ "${IDX}" == "0" ]; then
        read_cluster_name
    else
        echo
        print "0. new"

        echo
        question "Enter cluster (0-${IDX})[1] : "

        if [ "${ANSWER}" == "" ]; then
            ANSWER="1"
        fi

        if [ "${ANSWER}" == "0" ]; then
            read_cluster_name
        else
            IDX=0
            while read VAR; do
                ARR=(${VAR})

                if [ "${IDX}" == "${ANSWER}" ]; then
                    KOPS_CLUSTER_NAME="${ARR[0]}"
                    break
                fi

                IDX=$(( ${IDX} + 1 ))
            done < ${CLUSTER_LIST}
        fi
    fi

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        clear_kops_config
        error
    fi
}

read_cluster_name() {
    DEFAULT="cluster.k8s.local"

    echo
    question "Enter your cluster name [${DEFAULT}] : "
    echo

    if [ "${ANSWER}" == "" ]; then
        KOPS_CLUSTER_NAME="${DEFAULT}"
    else
        KOPS_CLUSTER_NAME="${ANSWER}"
    fi
}

kops_get() {
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    waiting
    cluster_menu
}

kops_edit() {
    IG_LIST=/tmp/kops-ig-list

    kops get ig --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} > ${IG_LIST}

    IDX=0
    while read VAR; do
        ARR=(${VAR})

        if [ "${ARR[0]}" == "NAME" ]; then
            continue
        fi

        IDX=$(( ${IDX} + 1 ))

        print "${IDX}. ${ARR[0]}"
    done < ${IG_LIST}

    echo
    print "0. cluster"

    echo
    question
    echo

    SELECTED=

    if [ "${ANSWER}" == "0" ]; then
        SELECTED="cluster"

        kops edit ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
    else
        IDX=0
        while read VAR; do
            ARR=(${VAR})

            if [ "${IDX}" == "${ANSWER}" ]; then
                SELECTED="${ARR[0]}"
                break
            fi

            IDX=$(( ${IDX} + 1 ))
        done < ${IG_LIST}

        if [ "${SELECTED}" != "" ]; then
            kops edit ig ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
        fi
    fi

    if [ "${SELECTED}" != "" ]; then
        waiting
    fi

    cluster_menu
}

kops_update() {
    kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    waiting
    cluster_menu
}

kops_rolling_update() {
    kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    waiting
    cluster_menu
}

kops_validate() {
    kops validate cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    echo
    kubectl get pod --all-namespaces

    waiting
    cluster_menu
}

kops_export() {
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    waiting
    cluster_menu
}

kops_delete() {
    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    clear_kops_config

    waiting
    state_store
}

get_ingress_elb_name() {
    ELB_NAME=

    progress start

    IDX=0
    while [ 1 ]; do
        # ingress-nginx 의 ELB Name 을 획득
        ELB_NAME=$(kubectl get svc -n kube-ingress -o wide | grep ingress-nginx | grep LoadBalancer | awk '{print $4}' | cut -d'-' -f1)

        if [ "${ELB_NAME}" != "" ] && [ "${ELB_NAME}" != "<pending>" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))

        if [ "${IDX}" == "20" ]; then
            ELB_NAME=
            break
        fi

        progress
    done

    progress end

    print ${ELB_NAME}
}

get_ingress_elb_domain() {
    ELB_DOMAIN=

    INGRESS=$(kubectl get ns | grep kube-ingress | wc -l | xargs)

    if [ "${INGRESS}" == "0" ]; then
        return
    fi

    progress start

    IDX=0
    while [ 1 ]; do
        # ingress-nginx 의 ELB Domain 을 획득
        ELB_DOMAIN=$(kubectl get svc -n kube-ingress -o wide | grep ingress-nginx | grep amazonaws | awk '{print $4}')

        if [ "${ELB_DOMAIN}" != "" ] && [ "${ELB_DOMAIN}" != "<pending>" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))

        if [ "${IDX}" == "20" ]; then
            ELB_DOMAIN=
            break
        fi

        progress
    done

    progress end

    print ${ELB_DOMAIN}
}

get_ingress_domain() {
    ELB_IP=

    get_ingress_elb_domain

    if [ "${ELB_DOMAIN}" == "" ]; then
        return
    fi

    progress start

    IDX=0
    while [ 1 ]; do
        ELB_IP=$(dig +short ${ELB_DOMAIN} | head -n 1)

        if [ "${ELB_IP}" != "" ]; then
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

    print ${BASE_DOMAIN}
}

read_root_domain() {
    HOST_LIST=/tmp/hosted-zones

    aws route53 list-hosted-zones | jq '.HostedZones[]' | grep Name | cut -d'"' -f4 > ${HOST_LIST}

    IDX=0
    while read VAR; do
        IDX=$(( ${IDX} + 1 ))

        print "${IDX}. $(echo ${VAR} | sed 's/.$//')"
    done < ${HOST_LIST}

    ROOT_DOMAIN=

    if [ "${IDX}" != "0" ]; then
        echo
        print "0. nip.io"

        echo
        question "Enter root domain (0-${IDX})[0] : "
        echo

        if [ "${ANSWER}" != "" ]; then
            IDX=0
            while read VAR; do
                IDX=$(( ${IDX} + 1 ))

                if [ "${IDX}" == "${ANSWER}" ]; then
                    ROOT_DOMAIN="$(echo ${VAR} | sed 's/.$//')"
                    break
                fi
            done < ${HOST_LIST}
        fi
    fi
}

apply_metrics_server() {
    if [ ! -d /tmp/metrics-server ]; then
        git clone https://github.com/kubernetes-incubator/metrics-server /tmp/metrics-server
    fi

    pushd /tmp/metrics-server
    git pull
    popd

    echo
    kubectl apply -f /tmp/metrics-server/deploy/1.8+/

    echo
    kubectl get hpa

    waiting
    addons_menu
}

apply_ingress_controller() {
    read_root_domain

    BASE_DOMAIN=

    if [ "${ROOT_DOMAIN}" != "" ]; then
        DEFAULT="apps.${ROOT_DOMAIN}"
        question "Enter your ingress domain [${DEFAULT}] : "
        echo

        if [ "${ANSWER}" == "" ]; then
            BASE_DOMAIN="${DEFAULT}"
        else
            BASE_DOMAIN="${ANSWER}"
        fi
    fi

    ADDON=/tmp/ingress-nginx.yml

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_template addons/ingress-nginx-v1.6.0.yml ${ADDON}
    else
        get_template addons/ingress-nginx-v1.6.0-ssl.yml ${ADDON}

        SSL_CERT_ARN=$(aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq '[.CertificateSummaryList[] | select(.DomainName==env.DOMAIN)][0]' | grep CertificateArn | cut -d'"' -f4)

        if [ "${SSL_CERT_ARN}" == "" ]; then
            error "Certificate ARN does not exists. [*.${BASE_DOMAIN}][${REGION}]"
        fi

        print "CertificateArn: ${SSL_CERT_ARN}"

        sed -i -e "s@{{SSL_CERT_ARN}}@${SSL_CERT_ARN}@g" ${ADDON}
    fi

    echo
    kubectl apply -f ${ADDON}

    sleep 2

    echo
    kubectl get pod,svc -n kube-ingress

    echo
    print "Pending ELB..."

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_ingress_domain
    else
        get_ingress_elb_name

        # ELB 에서 Hosted Zone ID, DNS Name 을 획득
        ELB_ZONE_ID=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | grep CanonicalHostedZoneNameID | cut -d'"' -f4)
        ELB_DNS_NAME=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | grep '"DNSName"' | cut -d'"' -f4)

        # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
        ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq '.HostedZones[] | select(.Name==env.ROOT_DOMAIN)' | grep '"Id"' | cut -d'"' -f4 | cut -d'/' -f3)

        # record sets
        RECORD=/tmp/record-sets.json

        get_template addons/record-sets.json ${RECORD}

        # replace
        sed -i -e "s@{{DOMAIN}}@*.${BASE_DOMAIN}@g" "${RECORD}"
        sed -i -e "s@{{ELB_ZONE_ID}}@${ELB_ZONE_ID}@g" "${RECORD}"
        sed -i -e "s@{{ELB_DNS_NAME}}@${ELB_DNS_NAME}@g" "${RECORD}"

        cat ${RECORD}

        # Route53 의 Record Set 에 입력/수정
        aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
    fi

    save_kops_config

    waiting
    addons_menu
}

apply_dashboard() {
    ADDON=/tmp/dashboard.yml

    if [ "${ROOT_DOMAIN}" == "" ]; then
        get_template addons/dashboard-v1.8.3.yml ${ADDON}
    else
        get_template addons/dashboard-v1.8.3-ing.yml ${ADDON}

        DEFAULT="dashboard.${BASE_DOMAIN}"
        question "Enter your dashboard domain [${DEFAULT}] : "
        echo

        DOMAIN="${ANSWER}"

        if [ "${DOMAIN}" == "" ]; then
            DOMAIN="${DEFAULT}"
        fi

        sed -i -e "s@dashboard.apps.nalbam.com@${DOMAIN}@g" ${ADDON}

        print "${DOMAIN}"
    fi

    echo
    kubectl apply -f ${ADDON}

    SECRET=$(kubectl get secret -n kube-system | grep admin-token | awk '{print $1}')

    if [ "${SECRET}" == "" ]; then
        # add ServiceAccount admin
        kubectl create serviceaccount admin -n kube-system

        # add ClusterRoleBinding cluster-admin
        kubectl create clusterrolebinding cluster-admin:kube-system:admin \
                --serviceaccount=kube-system:admin \
                --clusterrole=cluster-admin
    fi

    sleep 2

    if [ "${ROOT_DOMAIN}" == "" ]; then
        echo
        kubectl get pod -n kube-system
        echo
        kubectl get svc -n kube-system -o wide
    else
        echo
        kubectl get pod -n kube-system
        echo
        kubectl get svc -n kube-system
        echo
        kubectl get ing -n kube-system
    fi

    echo
    kubectl describe secret -n kube-system $(kubectl get secret -n kube-system | grep admin-token | awk '{print $1}')

    waiting
    addons_menu
}

apply_heapster() {
    ADDON=/tmp/heapster.yml

    get_template addons/heapster-v1.7.0.yml ${ADDON}

    echo
    kubectl apply -f ${ADDON}

    sleep 2

    echo
    kubectl get pod,svc -n kube-system

    waiting
    addons_menu
}

apply_cluster_autoscaler() {
    ADDON=/tmp/cluster-autoscaler.yml

    get_template addons/cluster-autoscaler-v1.8.0.yml ${ADDON}

    MIN_NODES=2
    MAX_NODES=8
    AWS_REGION=${REGION}
    GROUP_NAME="nodes.${KOPS_CLUSTER_NAME}"

    sed -i -e "s@{{MIN_NODES}}@${MIN_NODES}@g" "${ADDON}"
    sed -i -e "s@{{MAX_NODES}}@${MAX_NODES}@g" "${ADDON}"
    sed -i -e "s@{{GROUP_NAME}}@${GROUP_NAME}@g" "${ADDON}"
    sed -i -e "s@{{AWS_REGION}}@${AWS_REGION}@g" "${ADDON}"

    echo
    kubectl apply -f ${ADDON}

    echo
    kubectl get node

    waiting
    addons_menu
}

apply_sample_spring() {
    if [ "${BASE_DOMAIN}" == "" ]; then
        get_ingress_domain
    fi

    ADDON=/tmp/sample-spring.yml

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_template sample/sample-spring.yml ${ADDON}
    else
        get_template sample/sample-spring-ing.yml ${ADDON}

        DEFAULT="sample-spring.${BASE_DOMAIN}"
        question "Enter your sample-spring domain [${DEFAULT}] : "
        echo

        DOMAIN="${ANSWER}"

        if [ "${DOMAIN}" == "" ]; then
            DOMAIN="${DEFAULT}"
        fi

        sed -i -e "s@sample-spring.apps.nalbam.com@${DOMAIN}@g" ${ADDON}

        print "${DOMAIN}"
    fi

    echo
    kubectl apply -f ${ADDON}

    sleep 2

    echo
    kubectl get pod,svc,ing -n default

    waiting
    addons_menu
}

get_template() {
    rm -rf ${2}
    if [ -f "${SHELL_DIR}/${1}" ]; then
        cp -rf "${SHELL_DIR}/${1}" ${2}
    else
        curl -s https://raw.githubusercontent.com/nalbam/kops-cui/master/${1} > ${2}
    fi
    if [ ! -f ${2} ]; then
        error "Template does not exists. [${1}]"
    fi
}

get_az_list() {
    if [ "${AZ_LIST}" == "" ]; then
        AZ_LIST="$(aws ec2 describe-availability-zones | grep ZoneName | cut -d'"' -f4 | head -3 | tr -s '\r\n' ',' | sed 's/.$//')"
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

install_tools() {
    ${SHELL_DIR}/helper/bastion.sh

    waiting
    cluster_menu
}

prepare
