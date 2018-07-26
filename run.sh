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
master_size=m4.large
master_count=1
master_zones=
node_size=m4.large
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

error() {
    echo
    echo -e "${L_PAD}$(tput setaf 2)$@$(tput sgr0)"
    echo
    exit 1
}

question() {
    Q=$1
    if [ "$Q" == "" ]; then
        Q="Enter your choice : "
    fi
    echo
    read -p "${L_PAD}$(tput setaf 2)$Q$(tput sgr0)" ANSWER
    echo
}

press_enter() {
    echo
    read -p "${L_PAD}$(tput setaf 4)Press Enter to continue...$(tput sgr0)"
    echo
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

run() {
    logo

    mkdir -p ~/.ssh
    mkdir -p ~/.aws

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
        question "Do you want to install the required tools? (awscli,kubectl,kops...) [Y/n] : "

        ANSWER=${ANSWER:-Y}

        if [ "${ANSWER}" == "Y" ]; then
            ${SHELL_DIR}/helper/bastion.sh
        else
            error
        fi
    fi

    if [ ! -r ~/.aws/config ] || [ ! -r ~/.aws/credentials ]; then
        aws configure set default.region ap-northeast-2
        aws configure

        if [ ! -r ~/.aws/config ] || [ ! -r ~/.aws/credentials ]; then
            clear_kops_config
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
        echo
        print "7. Addons.."
        echo
        print "9. Delete Cluster"
        echo
        print "x. Exit"
    fi

    question

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

            if [ "${ANSWER}" == "YES" ]; then
                kops_delete
            else
                cluster_menu
            fi
            ;;
        x)
            kops_exit
            ;;
        *)
            cluster_menu
            ;;
    esac
}

addons_menu() {
    title

    print "1. Helm init"
    echo
    print "2. Ingress Controller"
    print "3. Dashboard"
    print "4. Heapster (deprecated)"
    print "5. Metrics Server"
    print "6. Cluster Autoscaler"
    print "7. Prometheus + Grafana"
    echo
    print "9. Sample.."

    question

    case ${ANSWER} in
        1)
            helm_init
            ;;
        2)
            apply_ingress_controller
            ;;
        3)
            apply_dashboard
            ;;
        4)
            apply_heapster
            ;;
        5)
            apply_metrics_server
            ;;
        6)
            apply_cluster_autoscaler
            ;;
        7)
            apply_monitor
            ;;
        9)
            sample_menu
            ;;
        *)
            cluster_menu
            ;;
    esac
}

helm_menu() {
    title

    print "1. Helm Init"
    echo
    print "3. DevOps (Jenkins, Nexus, Registry)"
    print "4. Monitor (Prometheus, Grafana)"

    question

    case ${ANSWER} in
        1)
            helm_init
            ;;
        3)
            helm_devops
            ;;
        4)
            helm_monitor
            ;;
        *)
            addons_menu
            ;;
    esac
}

sample_menu() {
    title

    print "1. Sample Node App"
    print "2. Sample Spring App"
    echo
    print "4. Sample Redis"

    question

    case ${ANSWER} in
        1)
            apply_sample_app 'sample-node'
            ;;
        2)
            apply_sample_app 'sample-spring'
            ;;
        4)
            apply_redis_master
            ;;
        *)
            addons_menu
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

    question

    case ${ANSWER} in
        1)
            question "Enter master size [${master_size}] : "
            master_size=${ANSWER:-${master_size}}
            create_cluster
            ;;
        2)
            question "Enter master count [${master_count}] : "
            master_count=${ANSWER:-${master_count}}
            get_master_zones
            create_cluster
            ;;
        3)
            create_cluster
            ;;
        4)
            question "Enter node size [${node_size}] : "
            node_size=${ANSWER:-${node_size}}
            create_cluster
            ;;
        5)
            question "Enter node count [${node_count}] : "
            node_count=${ANSWER:-${node_count}}
            get_node_zones
            create_cluster
            ;;
        6)
            create_cluster
            ;;
        7)
            question "Enter network cidr [${network_cidr}] : "
            network_cidr=${ANSWER:-${network_cidr}}
            create_cluster
            ;;
        8)
            question "Enter networking [${networking}] : "
            networking=${ANSWER:-${networking}}
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

    question "Enter cluster store [${DEFAULT}] : "

    KOPS_STATE_STORE=${ANSWER:-${DEFAULT}}

    # S3 Bucket
    BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
    if [ "${BUCKET}" == "" ]; then
        aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}

        waiting 2

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

        question "Enter cluster (0-${IDX})[1] : "

        ANSWER=${ANSWER:-1}

        if [ "${ANSWER}" == "0" ]; then
            read_cluster_name
        else
            ARR=($(sed -n $(( ${ANSWER} + 1 ))p ${CLUSTER_LIST}))
            KOPS_CLUSTER_NAME="${ARR[0]}"
        fi
    fi

    if [ "${KOPS_CLUSTER_NAME}" == "" ]; then
        clear_kops_config
        error
    fi
}

read_cluster_name() {
    # WORD=$(cat ${SHELL_DIR}/addons/words.txt | shuf -n 1)
    WORD="demo"

    DEFAULT="${WORD}.k8s.local"
    question "Enter your cluster name [${DEFAULT}] : "

    KOPS_CLUSTER_NAME=${ANSWER:-${DEFAULT}}
}

kops_get() {
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    press_enter
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

    question

    SELECTED=

    if [ "${ANSWER}" == "0" ]; then
        SELECTED="cluster"
    elif [ "${ANSWER}" != "" ]; then
        ARR=($(sed -n $(( ${ANSWER} + 1 ))p ${IG_LIST}))
        SELECTED="ig ${ARR[0]}"
    fi

    if [ "${SELECTED}" != "" ]; then
        kops edit ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

        press_enter
    fi

    cluster_menu
}

kops_update() {
    kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    press_enter
    cluster_menu
}

kops_rolling_update() {
    kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    press_enter
    cluster_menu
}

kops_validate() {
    kops validate cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    echo
    kubectl get pod --all-namespaces

    press_enter
    cluster_menu
}

kops_export() {
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    press_enter
    cluster_menu
}

kops_delete() {
    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    clear_kops_config

    rm -rf ~/.helm ~/.draft

    press_enter
    state_store
}

get_elb_domain() {
    ELB_DOMAIN=

    progress start

    IDX=0
    while [ 1 ]; do
        # ELB Domain 을 획득
        if [ "$2" == "" ]; then
            ELB_DOMAIN=$(kubectl get svc --all-namespaces -o wide | grep LoadBalancer | grep $1 | awk '{print $5}' | head -1)
        else
            ELB_DOMAIN=$(kubectl get svc -n $2 -o wide | grep LoadBalancer | grep $1 | awk '{print $4}' | head -1)
        fi

        if [ "${ELB_DOMAIN}" != "" ] && [ "${ELB_DOMAIN}" != "<pending>" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))

        if [ "${IDX}" == "100" ]; then
            ELB_DOMAIN=
            break
        fi

        progress
    done

    progress end

    print ${ELB_DOMAIN}
}

get_ingress_elb_name() {
    ELB_NAME=

    get_elb_domain "nginx-ingress"
    echo

    ELB_NAME=$(echo ${ELB_DOMAIN} | cut -d'-' -f1)

    print ${ELB_NAME}
}

get_ingress_nip_io() {
    ELB_IP=

    get_elb_domain "nginx-ingress"

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

        question "Enter root domain (0-${IDX})[0] : "

        if [ "${ANSWER}" != "" ]; then
            ROOT_DOMAIN=$(sed -n ${ANSWER}p ${HOST_LIST} | sed 's/.$//')
        fi
    fi
}

git_checkout() {
    GIT_USER=$1
    GIT_NAME=$2

    if [ ! -d /tmp/${GIT_USER}/${GIT_NAME} ]; then
        mkdir -p /tmp/${GIT_USER}
        git clone https://github.com/${GIT_USER}/${GIT_NAME} /tmp/${GIT_USER}/${GIT_NAME}
    fi

    pushd /tmp/${GIT_USER}/${GIT_NAME}
    if [ "$3" != "" ]; then
        git checkout $3
    fi
    git pull
    popd
}

apply_ingress_controller() {
    NAMESPACE="kube-ingress"

    create_namespace ${NAMESPACE}

    read_root_domain

    BASE_DOMAIN=

    if [ "${ROOT_DOMAIN}" != "" ]; then
        WORD=$(echo ${KOPS_CLUSTER_NAME} | cut -d'.' -f1)

        DEFAULT="${WORD}.${ROOT_DOMAIN}"
        question "Enter your ingress domain [${DEFAULT}] : "

        BASE_DOMAIN=${ANSWER:-${DEFAULT}}
    fi

    CHART=/tmp/nginx-ingress.yaml
    get_template charts/nginx-ingress.yaml ${CHART}

    if [ "${BASE_DOMAIN}" != "" ]; then
        get_ssl_cert_arn

        if [ "${SSL_CERT_ARN}" == "" ]; then
            set_record_cname
            echo
        fi
        if [ "${SSL_CERT_ARN}" == "" ]; then
            error "Certificate ARN does not exists. [*.${BASE_DOMAIN}][${REGION}]"
        fi

        print "CertificateArn: ${SSL_CERT_ARN}"
        echo

        sed -i -e "s@aws-load-balancer-ssl-cert:.*@aws-load-balancer-ssl-cert: ${SSL_CERT_ARN}@" ${CHART}
    fi

    # nginx-ingress
    COUNT=$(helm ls | grep nginx-ingress | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/nginx-ingress --name nginx-ingress --namespace ${NAMESPACE} -f ${CHART}
    else
        helm upgrade nginx-ingress stable/nginx-ingress -f ${CHART}
    fi

    waiting 2

    helm history nginx-ingress
    echo
    kubectl get pod,svc -n ${NAMESPACE}
    echo

    print "Pending ELB..."

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_ingress_nip_io
    else
        get_ingress_elb_name
        echo

        set_record_alias
        echo
    fi

    save_kops_config

    press_enter
    addons_menu
}

get_ssl_cert_arn() {
    # get certificate arn
    SSL_CERT_ARN=$(aws acm list-certificates | DOMAIN="*.${BASE_DOMAIN}" jq '[.CertificateSummaryList[] | select(.DomainName==env.DOMAIN)][0]' | grep CertificateArn | cut -d'"' -f4)
}

set_record_cname() {
    # request certificate
    SSL_CERT_ARN=$(aws acm request-certificate --domain-name "*.${BASE_DOMAIN}" --validation-method DNS | grep CertificateArn | cut -d'"' -f4)

    print "Request Certificate..."

    waiting 2

    # domain validate
    CERT_DNS_NAME=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq '.Certificate.DomainValidationOptions[].ResourceRecord' | grep Name | cut -d'"' -f4)
    CERT_DNS_VALUE=$(aws acm describe-certificate --certificate-arn ${SSL_CERT_ARN} | jq '.Certificate.DomainValidationOptions[].ResourceRecord' | grep Value | cut -d'"' -f4)

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq '.HostedZones[] | select(.Name==env.ROOT_DOMAIN)' | grep '"Id"' | cut -d'"' -f4 | cut -d'/' -f3)

    # record sets
    RECORD=/tmp/record-sets-cname.json
    get_template addons/record-sets-cname.json ${RECORD}

    # replace
    sed -i -e "s/DOMAIN/${CERT_DNS_NAME}/g" ${RECORD}
    sed -i -e "s/DNS_NAME/${CERT_DNS_VALUE}/g" ${RECORD}

    cat ${RECORD}

    # Route53 의 Record Set 에 입력/수정
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

set_record_alias() {
    # ELB 에서 Hosted Zone ID, DNS Name 을 획득
    ELB_ZONE_ID=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | grep CanonicalHostedZoneNameID | cut -d'"' -f4)
    ELB_DNS_NAME=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NAME} | grep '"DNSName"' | cut -d'"' -f4)

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq '.HostedZones[] | select(.Name==env.ROOT_DOMAIN)' | grep '"Id"' | cut -d'"' -f4 | cut -d'/' -f3)

    if [ "${ZONE_ID}" == "" ]; then
        return
    fi

    # record sets
    RECORD=/tmp/record-sets-alias.json
    get_template addons/record-sets-alias.json ${RECORD}

    # replace
    sed -i -e "s/DOMAIN/*.${BASE_DOMAIN}/g" ${RECORD}
    sed -i -e "s/ZONE_ID/${ELB_ZONE_ID}/g" ${RECORD}
    sed -i -e "s/DNS_NAME/${ELB_DNS_NAME}/g" ${RECORD}

    cat ${RECORD}

    # Route53 의 Record Set 에 입력/수정
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

apply_dashboard() {
    NAMESPACE="kube-system"

    # create_namespace ${NAMESPACE}

    CHART=/tmp/dashboard.yaml
    get_template charts/dashboard.yaml ${CHART}

    # kubernetes-dashboard
    COUNT=$(helm ls | grep kubernetes-dashboard | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/kubernetes-dashboard --name kubernetes-dashboard --namespace ${NAMESPACE} -f ${CHART}
    else
        helm upgrade kubernetes-dashboard stable/kubernetes-dashboard -f ${CHART}
    fi

    waiting 2

    helm history kubernetes-dashboard
    echo
    kubectl get pod -n ${NAMESPACE} | grep -E 'NAME|kubernetes-dashboard'
    echo
    kubectl get svc -n ${NAMESPACE} -o wide | grep -E 'NAME|kubernetes-dashboard'
    echo
    kubectl describe secret -n ${NAMESPACE} $(kubectl get secret -n ${NAMESPACE} | grep kubernetes-dashboard-token | awk '{print $1}')

    get_elb_domain "kubernetes-dashboard" ${NAMESPACE}

    echo
    print "URL: https://${ELB_DOMAIN}"

    press_enter
    addons_menu
}

apply_heapster() {
    NAMESPACE="kube-system"

    # create_namespace ${NAMESPACE}

    # heapster
    COUNT=$(helm ls | grep heapster | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/heapster --name heapster --namespace ${NAMESPACE}
    else
        helm upgrade heapster stable/heapster
    fi

    waiting 2

    helm history heapster
    echo
    kubectl get pod -n ${NAMESPACE} | grep -E 'NAME|heapster'
    echo
    kubectl get svc -n ${NAMESPACE} | grep -E 'NAME|heapster'

    press_enter
    addons_menu
}

apply_metrics_server() {
    NAMESPACE="kube-system"

    # create_namespace ${NAMESPACE}

    # metrics-server
    COUNT=$(helm ls | grep metrics-server | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/metrics-server --name metrics-server --namespace ${NAMESPACE}
    else
        helm upgrade metrics-server stable/metrics-server
    fi

    waiting 2

    helm history metrics-server
    echo
    kubectl get pod -n ${NAMESPACE} | grep -E 'NAME|metrics-server'
    echo
    kubectl get svc -n ${NAMESPACE} | grep -E 'NAME|metrics-server'
    echo
    kubectl get hpa

    press_enter
    addons_menu
}

apply_cluster_autoscaler() {
    NAMESPACE="kube-system"

    # create_namespace ${NAMESPACE}

    CHART=/tmp/cluster-autoscaler.yaml
    get_template charts/cluster-autoscaler.yaml ${CHART}

    # cluster-autoscaler
    COUNT=$(helm ls | grep cluster-autoscaler | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/cluster-autoscaler --name cluster-autoscaler --namespace ${NAMESPACE} -f ${CHART} \
             --set "autoDiscovery.clusterName=${KOPS_CLUSTER_NAME}" \
             --set "awsRegion=${REGION}"
    else
        helm upgrade cluster-autoscaler stable/cluster-autoscaler -f ${CHART} \
             --set "autoDiscovery.clusterName=${KOPS_CLUSTER_NAME}" \
             --set "awsRegion=${REGION}"
    fi

    waiting 2

    helm history cluster-autoscaler
    echo
    kubectl get pod -n ${NAMESPACE} | grep -E 'NAME|cluster-autoscaler'
    echo
    kubectl get svc -n ${NAMESPACE} | grep -E 'NAME|cluster-autoscaler'

    press_enter
    addons_menu
}

apply_monitor() {
    NAMESPACE="monitor"

    create_namespace ${NAMESPACE}

    CHART=/tmp/grafana.yaml
    get_template charts/grafana.yaml ${CHART}

    if [ "${BASE_DOMAIN}" == "" ]; then
        sed -i -e "s/enabled:.*/enabled: false/" ${CHART}
        sed -i -e "s/ClusterIP/LoadBalancer/" ${CHART}
    else
        DEFAULT="grafana-${NAMESPACE}.${BASE_DOMAIN}"
        question "Enter your grafana domain [${DEFAULT}] : "

        DOMAIN=${ANSWER:-${DEFAULT}}

        sed -i -e "s/enabled:.*/enabled: true/" ${CHART}
        sed -i -e "s/grafana.domain.com/${DOMAIN}/" ${CHART}

        print "${DOMAIN}"
        echo
    fi

    # grafana
    COUNT=$(helm ls | grep grafana | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/grafana --name grafana --namespace ${NAMESPACE} -f ${CHART}
    else
        helm upgrade grafana stable/grafana -f ${CHART}
    fi

    # prometheus
    COUNT=$(helm ls | grep prometheus | grep ${NAMESPACE} | wc -l | xargs)

    if [ "${COUNT}" == "0" ]; then
        helm install stable/prometheus --name prometheus --namespace ${NAMESPACE}
    else
        helm upgrade prometheus stable/prometheus
    fi

    waiting 2

    helm history prometheus
    echo
    helm history grafana
    echo
    kubectl get pod,svc,ing -n ${NAMESPACE}

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_elb_domain "grafana" ${NAMESPACE}

        echo
        print "URL: https://${ELB_DOMAIN}"
    else
        echo
        print "URL: https://${DOMAIN}"
    fi

    press_enter
    addons_menu
}

helm_init() {
    NAMESPACE="kube-system"

    # create_namespace ${NAMESPACE}

    TILLER=$(kubectl get serviceaccount -n ${NAMESPACE} | grep 'tiller' | wc -l | xargs)

    if [ "${TILLER}" == "0" ]; then
        kubectl create serviceaccount tiller -n ${NAMESPACE}
        echo
    fi

    ROLL=$(kubectl get clusterrolebinding | grep 'cluster-admin' | grep 'tiller' | wc -l | xargs)

    if [ "${ROLL}" == "0" ]; then
        kubectl create clusterrolebinding cluster-admin:${NAMESPACE}:tiller --clusterrole=cluster-admin --serviceaccount=${NAMESPACE}:tiller
        echo
    fi

    helm init --upgrade --service-account=tiller

    waiting 2

    kubectl get pod,svc -n ${NAMESPACE}

    press_enter
    addons_menu
}

helm_uninit() {
    NAMESPACE="kube-system"

    kubectl delete deployment tiller-deploy -n ${NAMESPACE}
    echo
    kubectl delete clusterrolebinding tiller
    echo
    kubectl delete serviceaccount tiller -n ${NAMESPACE}
}

create_namespace() {
    kubectl get namespace $1 > /dev/null 2>&1 || kubectl create namespace $1
}

apply_redis_master() {
    NAMESPACE="default"

    # create_namespace ${NAMESPACE}

    ADDON=/tmp/sample-redis.yml
    get_template sample/sample-redis.yml ${ADDON}

    kubectl apply -f ${ADDON}

    waiting 2

    kubectl get pod,svc -n ${NAMESPACE}

    press_enter
    sample_menu
}

apply_sample_app() {
    NAMESPACE="default"

    # create_namespace ${NAMESPACE}

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_ingress_nip_io
    fi

    APP_NAME=$1

    ADDON=/tmp/${APP_NAME}.yml

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_template sample/${APP_NAME}.yml ${ADDON}
    else
        get_template sample/${APP_NAME}-ing.yml ${ADDON}

        DEFAULT="${APP_NAME}.${BASE_DOMAIN}"
        question "Enter your ${APP_NAME} domain [${DEFAULT}] : "

        DOMAIN=${ANSWER:-${DEFAULT}}

        sed -i -e "s/${APP_NAME}.domain.com/${DOMAIN}/g" ${ADDON}

        print "${DOMAIN}"
        echo
    fi

    kubectl apply -f ${ADDON}

    waiting 2

    kubectl get pod,svc,ing -n ${NAMESPACE}

    if [ "${BASE_DOMAIN}" == "" ]; then
        get_elb_domain "${APP_NAME}" ${NAMESPACE}

        echo
        print "URL: https://${ELB_DOMAIN}"
    else
        echo
        print "URL: https://${DOMAIN}"
    fi

    press_enter
    sample_menu
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

    press_enter
    cluster_menu
}

kops_exit() {
    echo
    print "See you soon!"
    echo
    exit 0
}

run
