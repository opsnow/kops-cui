#!/bin/bash

SHELL_DIR=$(dirname $0)

OS_NAME="$(uname | awk '{print tolower($0)}')"

L_PAD="$(printf %3s)"

CONFIG=

ANSWER=
CLUSTER=

REGION=
AZ_LIST=

KOPS_STATE_STORE=
KOPS_CLUSTER_NAME=
KOPS_TERRAFORM=
KOPS_AWS_NAT=

ROOT_DOMAIN=
BASE_DOMAIN=

cloud=aws
master_size=c4.large
master_count=1
master_zones=
node_size=m4.large
node_count=2
topology=private
zones=
network_cidr=10.0.0.0/16
networking=calico
vpc=

# nat=$(aws ec2 describe-subnets --filters Name=tag:KubernetesCluster,Values=chewie.k8s.local)

print() {
    echo -e "${L_PAD}$@"
}

success() {
    echo -e "${L_PAD}$(tput setaf 6)$@$(tput sgr0)"
}

error() {
    echo
    echo -e "${L_PAD}$(tput setaf 1)$@$(tput sgr0)"
    echo

    exit 1
}

question() {
    Q=${1:-"Enter your choice : "}
    echo
    read -p "${L_PAD}$(tput setaf 2)$Q$(tput sgr0)" ANSWER
    echo
}

press_enter() {
    echo
    read -p "${L_PAD}$(tput setaf 4)Press Enter to continue...$(tput sgr0)"
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
            monitor_menu
            ;;
        devops)
            devops_menu
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
    print " |_|\_\___/|_|   |____/   \____|\___/|___|  by OpsNow "
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

    get_kops_config

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
    command -v helm > /dev/null    || export NEED_TOOL=helm
    command -v terraform > /dev/null || export NEED_TOOL=terraform

    if [ ! -z ${NEED_TOOL} ]; then
        question "Do you want to install the required tools? (awscli,kubectl,kops,helm...) [Y/n] : "

        ANSWER=${ANSWER:-Y}

        if [ "${ANSWER}" == "Y" ]; then
            ${SHELL_DIR}/helper/bastion.sh
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

    get_kops_cluster

    cluster_menu
}

cluster_menu() {
    title

    if [ "x${CLUSTER}" == "x0" ]; then
        print "1. Create Cluster"
        print "2. Update Tools"
    else
        print "1. Get Cluster"
        print "2. Edit Cluster"
        print "3. Update Cluster"
        print "4. Rolling Update"
        print "5. Validate Cluster"
        print "6. Export Kube Config"
        print "7. AWS NAT Gateway"
        echo
        print "9. Delete Cluster"
        echo
        print "11. Addons.."
        echo
        print "x. Exit"
    fi

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
                install_tools
            else
                kops_edit
            fi
            press_enter cluster
            ;;
        3)
            kops_update
            press_enter cluster
            ;;
        4)
            question "Are you sure? (YES/[no]) : "

            if [ "${ANSWER}" == "YES" ]; then
                kops_rolling_update
                press_enter cluster
            else
                cluster_menu
            fi
            ;;
        5)
            kops_validate
            press_enter cluster
            ;;
        6)
            kops_export
            press_enter cluster
            ;;
        7)
            KOPS_AWS_NAT=true
            save_kops_config

            kops_nat_gateway apply -auto-approve
            press_enter cluster
            ;;
        9)
            question "Are you sure? (YES/[no]) : "

            if [ "${ANSWER}" == "YES" ]; then
                kops_delete
                press_enter state
            else
                cluster_menu
            fi
            ;;
        11)
            addons_menu
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

    print "1. helm init"
    echo
    print "2. nginx-ingress"
    print "3. kubernetes-dashboard"
    print "4. heapster (deprecated)"
    print "5. metrics-server"
    print "6. cluster-autoscaler"
    echo
    print "9. remove"
    echo
    print "11. sample.."
    print "12. monitor.."
    # print "13. devops.."

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
            helm_apply kubernetes-dashboard kube-system false
            echo
            SECRET=$(kubectl get secret -n ${NAMESPACE} | grep ${APP_NAME}-token | awk '{print $1}')
            kubectl describe secret ${SECRET} -n ${NAMESPACE} | grep 'token:'
            press_enter addons
            ;;
        4)
            helm_apply heapster kube-system
            press_enter addons
            ;;
        5)
            helm_apply metrics-server kube-system
            echo
            kubectl get hpa
            press_enter addons
            ;;
        6)
            helm_apply cluster-autoscaler kube-system
            echo
            success "# Edit InstanceGroup for Auto-discovery"
            echo
            echo "spec:"
            echo "  cloudLabels:"
            echo "    k8s.io/cluster-autoscaler/enabled: \"\""
            echo "    kubernetes.io/cluster/${KOPS_CLUSTER_NAME}: owned"
            press_enter addons
            ;;
        9)
            helm_remove
            press_enter addons
            ;;
        11)
            sample_menu
            ;;
        12)
            monitor_menu
            ;;
        13)
            devops_menu
            ;;
        *)
            cluster_menu
            ;;
    esac
}

sample_menu() {
    title

    print "1. sample-redis"
    echo
    print "2. sample-web"
    print "3. sample-node"
    print "4. sample-spring"
    print "5. sample-tomcat"
    print "6. sample-webpack"

    question

    case ${ANSWER} in
        1)
            apply_sample sample-redis default
            press_enter sample
            ;;
        2)
            apply_sample sample-web default true
            press_enter sample
            ;;
        3)
            apply_sample sample-node default true
            press_enter sample
            ;;
        4)
            apply_sample sample-spring default true
            press_enter sample
            ;;
        5)
            apply_sample sample-tomcat default true
            press_enter sample
            ;;
        6)
            apply_sample sample-webpack default true
            press_enter sample
            ;;
        *)
            addons_menu
            ;;
    esac
}

monitor_menu() {
    title

    print "1. prometheus"
    print "2. grafana"

    question

    case ${ANSWER} in
        1)
            helm_apply prometheus monitor true
            press_enter monitor
            ;;
        2)
            helm_apply grafana monitor true
            press_enter monitor
            ;;
        *)
            addons_menu
            ;;
    esac
}

devops_menu() {
    title

    print "1. jenkins"
    print "2. docker-registry"
    print "3. chartmuseum"
    print "4. sonarqube"
    print "5. sonatype-nexus"

    question

    case ${ANSWER} in
        1)
            create_cluster_role_binding cluster-admin devops
            helm_apply jenkins devops true
            press_enter devops
            ;;
        2)
            helm_apply docker-registry devops true
            press_enter devops
            ;;
        3)
            helm_apply chartmuseum devops true
            press_enter devops
            ;;
        4)
            helm_apply sonarqube devops true
            press_enter devops
            ;;
        5)
            helm_apply sonatype-nexus devops true
            press_enter devops
            ;;
        *)
            addons_menu
            ;;
    esac
}

create_menu() {
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
    print "3. node-size=${node_size}"
    print "4. node-count=${node_count}"
    print "   zones=${zones}"
    print "5. network-cidr=${network_cidr}"
    print "6. networking=${networking}"
    # print "7. vpc=${vpc}"
    echo
    print "0. create"
    # print "t. terraform"

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
            question "Enter vpc id [${vpc}] : "
            vpc=${ANSWER:-${vpc}}
            create_menu
            ;;
        0)
            KOPS_TERRAFORM=
            save_kops_config

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
                --networking=${networking} \
                --vpc=${vpc}

            press_enter

            get_kops_cluster

            cluster_menu
            ;;
        t)
            KOPS_TERRAFORM=true
            save_kops_config

            mkdir -p ${KOPS_CLUSTER_NAME}

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
                --networking=${networking} \
                --vpc=${vpc} \
                --target=terraform \
                --out=terraform-${KOPS_CLUSTER_NAME}

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

get_kops_config() {
    mkdir -p ~/.kops-cui

    CONFIG=~/.kops-cui/config

    if [ -f ${CONFIG} ]; then
        . ${CONFIG}
    fi
}

read_kops_config() {
    COUNT=$(aws s3 ls s3://${KOPS_STATE_STORE} | grep ${KOPS_CLUSTER_NAME}.kops-cui | wc -l | xargs)

    if [ "x${COUNT}" == "x0" ]; then
        save_kops_config
    else
        aws s3 cp s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui ${CONFIG} --quiet
    fi

    if [ -f ${CONFIG} ]; then
        . ${CONFIG}
    fi
}

save_kops_config() {
    echo "# kops config" > ${CONFIG}
    echo "KOPS_STATE_STORE=${KOPS_STATE_STORE}" >> ${CONFIG}
    echo "KOPS_CLUSTER_NAME=${KOPS_CLUSTER_NAME}" >> ${CONFIG}
    echo "KOPS_TERRAFORM=${KOPS_TERRAFORM}" >> ${CONFIG}
    echo "KOPS_AWS_NAT=${KOPS_AWS_NAT}" >> ${CONFIG}
    echo "ROOT_DOMAIN=${ROOT_DOMAIN}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}

    if [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        aws s3 cp ${CONFIG} s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui --quiet
    fi
}

clear_kops_config() {
    export KOPS_STATE_STORE=
    export KOPS_CLUSTER_NAME=
    export KOPS_TERRAFORM=
    export KOPS_AWS_NAT=
    export ROOT_DOMAIN=
    export BASE_DOMAIN=

    save_kops_config

    . ${CONFIG}
}

delete_kops_config() {
    if [ ! -z ${KOPS_CLUSTER_NAME} ]; then
        aws s3 rm s3://${KOPS_STATE_STORE}/${KOPS_CLUSTER_NAME}.kops-cui
    fi

    clear_kops_config
}

read_state_store() {
    if [ ! -z ${KOPS_STATE_STORE} ]; then
        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
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
    BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
    if [ -z ${BUCKET} ]; then
        aws s3 mb s3://${KOPS_STATE_STORE} --region ${REGION}

        waiting 2

        BUCKET=$(aws s3api get-bucket-acl --bucket ${KOPS_STATE_STORE} | jq '.Owner.ID')
        if [ -z ${BUCKET} ]; then
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

    if [ "x${IDX}" == "x0" ]; then
        read_cluster_name
    else
        echo
        print "0. new"

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
    kops get --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
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

    if [ "x${ANSWER}" == "x0" ]; then
        SELECTED="cluster"
    elif [ ! -z ${ANSWER} ]; then
        ARR=($(sed -n $(( ${ANSWER} + 1 ))p ${IG_LIST}))
        SELECTED="ig ${ARR[0]}"
    fi

    if [ "${SELECTED}" != "" ]; then
        kops edit ${SELECTED} --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
    fi
}

kops_update() {
    if [ -z ${KOPS_TERRAFORM} ]; then
        kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes
    else
        kops update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes \
                            --target=terraform --out=terraform-${KOPS_CLUSTER_NAME}
    fi
}

kops_rolling_update() {
    kops rolling-update cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --force --yes
}

kops_validate() {
    kops validate cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}

    echo
    kubectl get pod --all-namespaces
}

kops_export() {
    kops export kubecfg --name ${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE}
}

kops_nat_gateway() {
    CMD=${1:-plan}
    OPT=${2}

    SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=tag:KubernetesCluster,Values=${KOPS_CLUSTER_NAME} | jq '.Subnets[] | {SubnetId}' | grep SubnetId | cut -d'"' -f4 | tr -s '\r\n' ',' | sed 's/.$//')

    if [ ! -z ${SUBNET_IDS} ]; then
        TF=/tmp/tf-${KOPS_CLUSTER_NAME}

        rm -rf ${TF}
        mkdir -p ${TF}

        cp -rf ${SHELL_DIR}/terraform/nat.tf ${TF}/

        sed -i -e "s/REGION/${REGION}/g" ${TF}/nat.tf
        sed -i -e "s/KOPS_STATE_STORE/${KOPS_STATE_STORE}/g" ${TF}/nat.tf
        sed -i -e "s/KOPS_CLUSTER_NAME/${KOPS_CLUSTER_NAME}/g" ${TF}/nat.tf
        sed -i -e "s/SUBNET_IDS/${SUBNET_IDS}/g" ${TF}/nat.tf

        pushd ${TF}
        terraform init
        terraform ${CMD} ${OPT}
        popd
    fi
}

kops_delete() {
    if [ ! -z ${KOPS_AWS_NAT} ]; then
        kops_nat_gateway destroy -auto-approve
    fi

    kops delete cluster --name=${KOPS_CLUSTER_NAME} --state=s3://${KOPS_STATE_STORE} --yes

    delete_kops_config

    rm -rf ~/.helm ~/.draft
}

get_elb_domain() {
    ELB_DOMAIN=

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

    print ${ELB_DOMAIN}
}

get_ingress_elb_name() {
    ELB_NAME=

    get_elb_domain "nginx-ingress"
    echo

    ELB_NAME=$(echo ${ELB_DOMAIN} | cut -d'-' -f1)

    print ${ELB_NAME}
}

get_ingres_domain() {
    if [ -z $2 ]; then
        DOMAIN=$(kubectl get ing --all-namespaces -o wide | grep $1 | awk '{print $3}' | head -1)
    else
        DOMAIN=$(kubectl get ing $1 -n $2 -o wide | grep $1 | awk '{print $2}' | head -1)
    fi
}

get_ingress_nip_io() {
    ELB_IP=

    get_elb_domain "nginx-ingress"

    if [ -z ${ELB_DOMAIN} ]; then
        return
    fi

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

        if [ ! -z ${ANSWER} ]; then
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
    if [ ! -z $3 ]; then
        git checkout $3
    fi
    git pull
    popd
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

    if [ -z ${ZONE_ID} ]; then
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

helm_nginx_ingress() {
    APP_NAME="nginx-ingress"
    NAMESPACE=${1:-kube-ingress}

    create_namespace ${NAMESPACE}

    helm_check

    read_root_domain

    BASE_DOMAIN=

    if [ ! -z ${ROOT_DOMAIN} ]; then
        WORD=$(echo ${KOPS_CLUSTER_NAME} | cut -d'.' -f1)

        DEFAULT="${WORD}.${ROOT_DOMAIN}"
        question "Enter your ingress domain [${DEFAULT}] : "

        BASE_DOMAIN=${ANSWER:-${DEFAULT}}
    fi

    CHART=/tmp/${APP_NAME}.yaml
    get_template charts/${APP_NAME}.yaml ${CHART}

    if [ ! -z ${BASE_DOMAIN} ]; then
        get_ssl_cert_arn

        if [ -z ${SSL_CERT_ARN} ]; then
            set_record_cname
            echo
        fi
        if [ -z ${SSL_CERT_ARN} ]; then
            error "Certificate ARN does not exists. [*.${BASE_DOMAIN}][${REGION}]"
        fi

        print "CertificateArn: ${SSL_CERT_ARN}"
        echo

        sed -i -e "s@aws-load-balancer-ssl-cert:.*@aws-load-balancer-ssl-cert: ${SSL_CERT_ARN}@" ${CHART}
    fi

    helm upgrade --install ${APP_NAME} stable/${APP_NAME} --namespace ${NAMESPACE} -f ${CHART}

    waiting 2

    helm history ${APP_NAME}
    echo
    kubectl get pod,svc -n ${NAMESPACE}
    echo

    print "Pending ELB..."

    if [ -z ${BASE_DOMAIN} ]; then
        get_ingress_nip_io
        echo
    else
        get_ingress_elb_name
        echo

        set_record_alias
        echo
    fi

    save_kops_config
}

helm_apply() {
    APP_NAME=${1}
    NAMESPACE=${2:-default}
    INGRESS=${3}
    DOMAIN=

    create_namespace ${NAMESPACE}

    helm_check

    CHART=/tmp/${APP_NAME}.yaml
    get_template charts/${APP_NAME}.yaml ${CHART}

    # for jenkins jobs
    if [ "${APP_NAME}" == "jenkins" ]; then
        ${SHELL_DIR}/jobs/replace.sh ${CHART}
        echo
    fi

    sed -i -e "s/CLUSTER_NAME/${KOPS_CLUSTER_NAME}/" ${CHART}
    sed -i -e "s/AWS_REGION/${REGION}/" ${CHART}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            sed -i -e "s/SERVICE_TYPE/LoadBalancer/" ${CHART}
            sed -i -e "s/INGRESS_ENABLED/false/" ${CHART}
        else
            DOMAIN="${APP_NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            sed -i -e "s/SERVICE_TYPE/ClusterIP/" ${CHART}
            sed -i -e "s/INGRESS_ENABLED/true/" ${CHART}
            sed -i -e "s/INGRESS_DOMAIN/${DOMAIN}/" ${CHART}
        fi
    fi

    helm upgrade --install ${APP_NAME} stable/${APP_NAME} --namespace ${NAMESPACE} -f ${CHART}

    waiting 2

    helm history ${APP_NAME}
    echo
    kubectl get pod,svc,ing -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ] || [ "${INGRESS}" == "false" ]; then
            echo
            get_elb_domain ${APP_NAME} ${NAMESPACE}
            echo
            success "${APP_NAME}: https://${ELB_DOMAIN}"
        else
            echo
            # get_ingres_domain ${APP_NAME} ${NAMESPACE}
            success "${APP_NAME}: https://${DOMAIN}"
        fi
    fi
}

helm_remove() {
    helm ls

    question "Enter chart name : "

    if [ ! -z ${ANSWER} ]; then
        helm delete --purge ${ANSWER}
    fi
}

helm_check() {
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

    helm init --upgrade --service-account=${ACCOUNT}

    waiting 5

    kubectl get pod,svc -n ${NAMESPACE}
    echo
    helm repo update
    echo
    helm ls
}

helm_uninit() {
    NAMESPACE="kube-system"
    ACCOUNT="tiller"

    kubectl delete deployment tiller-deploy -n ${NAMESPACE}
    echo
    kubectl delete clusterrolebinding cluster-admin:${NAMESPACE}:${ACCOUNT}
    echo
    kubectl delete serviceaccount ${ACCOUNT} -n ${NAMESPACE}
}

create_namespace() {
    NAMESPACE=$1

    CHECK=
    kubectl get ns ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        kubectl create ns ${NAMESPACE}
        echo
    fi
}

create_service_account() {
    NAMESPACE=$1
    ACCOUNT=$2

    create_namespace ${NAMESPACE}

    print "${NAMESPACE}:${ACCOUNT}"
    echo

    CHECK=
    kubectl get sa ${ACCOUNT} -n ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        kubectl create sa ${ACCOUNT} -n ${NAMESPACE}
        echo
    fi
}

create_cluster_role_binding() {
    ROLL=$1
    NAMESPACE=$2
    ACCOUNT=${3:-default}

    create_service_account ${NAMESPACE} ${ACCOUNT}

    print "${ROLL}:${NAMESPACE}:${ACCOUNT}"
    echo

    CHECK=
    kubectl get clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        kubectl create clusterrolebinding ${ROLL}:${NAMESPACE}:${ACCOUNT} --clusterrole=${ROLL} --serviceaccount=${NAMESPACE}:${ACCOUNT}
        echo
    fi
}

apply_sample() {
    APP_NAME=${1}
    NAMESPACE=${2:-default}
    INGRESS=${3}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_ingress_nip_io
        fi
    fi

    SAMPLE=/tmp/${APP_NAME}.yml
    get_template sample/${APP_NAME}.yml ${SAMPLE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            sed -i -e "s/SERVICE_TYPE/LoadBalancer/" ${SAMPLE}
        else
            DOMAIN="${APP_NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            sed -i -e "s/SERVICE_TYPE/ClusterIP/" ${SAMPLE}
            sed -i -e "s/INGRESS_DOMAIN/${DOMAIN}/" ${SAMPLE}
        fi
    fi

    kubectl apply -f ${SAMPLE}

    waiting 2

    kubectl get pod,svc,ing -n ${NAMESPACE}

    if [ ! -z ${INGRESS} ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            get_elb_domain ${APP_NAME} ${NAMESPACE}

            echo
            success "${APP_NAME}: https://${ELB_DOMAIN}"
        else
            echo
            success "${APP_NAME}: https://${DOMAIN}"
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
        error "Template does not exists. [${1}]"
    fi
}

get_az_list() {
    if [ -z ${AZ_LIST} ]; then
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
}

kops_exit() {
    echo
    print "See you soon!"
    echo
    exit 0
}

run
