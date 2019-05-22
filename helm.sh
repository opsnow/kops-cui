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
    _echo "${CLUSTER_NAME}" 4
}

prepare() {
    logo

    mkdir -p ~/.ssh
    mkdir -p ~/.aws
    mkdir -p ${SHELL_DIR}/build/${THIS_NAME}

    NEED_TOOL=
    command -v jq > /dev/null      || export NEED_TOOL=jq
    command -v git > /dev/null     || export NEED_TOOL=git
    command -v aws > /dev/null     || export NEED_TOOL=awscli
    command -v kubectl > /dev/null || export NEED_TOOL=kubectl
    command -v helm > /dev/null    || export NEED_TOOL=helm

    if [ ! -z ${NEED_TOOL} ]; then
        question "Do you want to install the required tools? (awscli,kubectl,helm...) [Y/n] : "

        if [ "${ANSWER:-Y}" == "Y" ]; then
            ${SHELL_DIR}/tools.sh
        else
            _error "Need install tools."
        fi
    fi

    REGION="$(aws configure get default.region)"
}

run() {
    prepare

    get_cluster

    config_load

    main_menu
}

press_enter() {
    _result "$(date)"

    _read "Press Enter to continue..." 5
    echo

    case ${1} in
        main)
            main_menu
            ;;
        kube-ingress)
            charts_menu "kube-ingress"
            ;;
        kube-system)
            charts_menu "kube-system"
            ;;
        monitor)
            charts_menu "monitor"
            ;;
        devops)
            charts_menu "devops"
            ;;
        sample)
            charts_menu "sample"
            ;;
        batch)
            charts_menu "batch"
            ;;
        istio)
            istio_menu
            ;;
    esac
}

main_menu() {
    title

    echo
    _echo "1. helm init"
    echo
    _echo "2. kube-ingress.."
    _echo "3. kube-system.."
    _echo "4. monitor.."
    _echo "5. devops.."
    _echo "6. sample.."
    _echo "7. batch.."
    echo
    _echo "i. istio.."
    echo
    _echo "d. remove"
    echo
    _echo "c. check PV"
    _echo "v. save variables"
    echo
    _echo "u. update self"
    _echo "t. update tools"
    echo
    _echo "x. Exit"

    question

    case ${ANSWER} in
        1)
            helm_init
            press_enter main
            ;;
        2)
            charts_menu "kube-ingress"
            ;;
        3)
            charts_menu "kube-system"
            ;;
        4)
            charts_menu "monitor"
            ;;
        5)
            charts_menu "devops"
            ;;
        6)
            charts_menu "sample"
            ;;
        7)
            charts_menu "batch"
            ;;
        i)
            istio_menu
            ;;
        d)
            helm_delete
            press_enter main
            ;;
        c)
            validate_pv
            press_enter main
            ;;
        v)
            variables_save
            press_enter main
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
            main_menu
            ;;
    esac
}

listup_ing_rules() {
    SERVICE_NAME="nginx-ingress-private-controller"
    ELB_DNS=$(kubectl -n kube-ingress get svc ${SERVICE_NAME} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

    ELB_ID=$(echo ${ELB_DNS} | cut -d'-' -f 1)

    SG_ID=$(aws elb describe-load-balancers --load-balancer-name ${ELB_ID} | jq -r '.LoadBalancerDescriptions[] | .SecurityGroups[]')

    _command "aws ec2 describe-security-groups --group-id ${SG_ID} | jq -r '.SecurityGroups[] | .IpPermissions'"
    export SG_INGRESS_RULE=$(aws ec2 describe-security-groups --group-id ${SG_ID} | jq -r '.SecurityGroups[] | .IpPermissions')

    echo $SG_INGRESS_RULE
}

remove_ing_rule() {

    listup_ing_rules
    ALL_RULE=$(echo $SG_INGRESS_RULE | jq -rc . )

    _command "aws ec2 revoke-security-group-ingress --group-id $SG_ID --ip-permissions $ALL_RULE"
    aws ec2 revoke-security-group-ingress --group-id $SG_ID --ip-permissions "${ALL_RULE}"
    listup_ing_rules

}

istio_menu() {
    title

    echo
    _echo "1. install"
    _echo "2. install istio-remote"
    echo
    _echo "3. injection show"
    _echo "4. injection enable"
    _echo "5. injection disable"
    echo
    _echo "6. import config to secret"
    _echo "7. export config"
    _echo "8. show pod IPs"
    echo
    _echo "9. remove"

    question

    case ${ANSWER} in
        1)
            istio_install
            press_enter istio
            ;;
        2)
            istio_remote_install
            press_enter istio
            ;;
        3)
            istio_injection
            press_enter istio
            ;;
        4)
            istio_injection "enable"
            press_enter istio
            ;;
        5)
            istio_injection "disable"
            press_enter istio
            ;;
        6)
            istio_import_config_to_secret
            press_enter istio
            ;;
        7)
            istio_export_config
            press_enter istio
            ;;
        8)
            istio_show_pod_ips
            press_enter istio
            ;;
        9)
            istio_delete
            press_enter istio
            ;;
        *)
            main_menu
            ;;
    esac
}

charts_menu() {
    title

    NAMESPACE=$1

    LIST=${SHELL_DIR}/build/${CLUSTER_NAME}/charts-list

    # find chart
    ls ${SHELL_DIR}/charts/${NAMESPACE} | sort | sed 's/.yaml//' > ${LIST}

    # select
    select_one

    if [ -z ${SELECTED} ]; then
        main_menu
        return
    fi

    # create_cluster_role_binding admin ${NAMESPACE}

    # helm install
    helm_install ${SELECTED} ${NAMESPACE}

    press_enter ${NAMESPACE}
}

helm_install() {
    helm_check

    NAME=${1}
    NAMESPACE=${2}

    create_namespace ${NAMESPACE}

    EXTRA_VALUES=

    # helm check FAILED
    # COUNT=$(helm ls -a | grep ${NAME} | grep ${NAMESPACE} | grep "FAILED" | wc -l | xargs)
    # if [ "x${COUNT}" != "x0" ]; then
    #     _command "helm delete --purge ${NAME}"
    #     helm delete --purge ${NAME}
    # fi

    # helm chart
    CHART=${SHELL_DIR}/build/${CLUSTER_NAME}/helm-${NAME}.yaml
    get_template charts/${NAMESPACE}/${NAME}.yaml ${CHART}

    # chart repository
    REPO=$(cat ${CHART} | grep '# chart-repo:' | awk '{print $3}')
    if [ "${REPO}" == "" ]; then
        REPO="stable/${NAME}"
    else
        PREFIX="$(echo ${REPO} | cut -d'/' -f1)"
        if [ "${PREFIX}" == "custom" ]; then
            REPO="${SHELL_DIR}/${REPO}"
        elif [ "${PREFIX}" != "stable" ]; then
            helm_repo "${PREFIX}"
        fi
    fi

    # chart config
    VERSION=$(cat ${CHART} | grep '# chart-version:' | awk '{print $3}')
    INGRESS=$(cat ${CHART} | grep '# chart-ingress:' | awk '{print $3}')

    _result "${REPO} version: ${VERSION}"

    # installed chart version
    LATEST=$(helm ls ${NAME} | grep ${NAME} | head -1 | awk '{print $9}')

    if [ "${LATEST}" != "" ]; then
        _result "installed version: ${LATEST}"
    fi

    # latest chart version
    LATEST=$(helm search ${NAME} | grep ${REPO} | head -1 | awk '{print $2}')

    if [ "${LATEST}" != "" ]; then
        _result "latest chart version: ${LATEST}"

        if [ "${VERSION}" != "" ] && [ "${VERSION}" != "latest" ] && [ "${VERSION}" != "${LATEST}" ]; then
            LIST=${SHELL_DIR}/build/${CLUSTER_NAME}/version-list
            echo "${VERSION} " > ${LIST}
            echo "${LATEST} (latest) " >> ${LIST}

            # select
            select_one

            if [ "${SELECTED}" != "" ]; then
                VERSION="$(echo "${SELECTED}" | cut -d' ' -f1)"
            fi

            _result "${VERSION}"
        fi

        if [ "${VERSION}" == "" ] || [ "${VERSION}" == "latest" ]; then
            _replace "s/chart-version:.*/chart-version: ${LATEST}/g" ${CHART}
        fi
    fi

    # global
    _replace "s/AWS_REGION/${REGION}/g" ${CHART}
    _replace "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ${CHART}
    _replace "s/NAMESPACE/${NAMESPACE}/g" ${CHART}

    # for cert-manager
    if [ "${NAME}" == "cert-manager" ]; then
        # https://github.com/helm/charts/blob/master/stable/cert-manager/README.md
        kubectl apply \
            -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
    fi

    # for nginx-ingress
    if [[ "${NAME}" == "nginx-ingress"* ]]; then
        get_base_domain

        get_replicas ${NAMESPACE} ${NAME}-controller
        if [ "${REPLICAS}" != "" ]; then
            EXTRA_VALUES="${EXTRA_VALUES} --set controller.replicaCount=${REPLICAS}"
        fi

        get_cluster_ip ${NAMESPACE} ${NAME}-controller
        if [ "${CLUSTER_IP}" != "" ]; then
            EXTRA_VALUES="${EXTRA_VALUES} --set controller.service.clusterIP=${CLUSTER_IP}"

            get_cluster_ip ${NAMESPACE} ${NAME}-controller-metrics
            if [ "${CLUSTER_IP}" != "" ]; then
                EXTRA_VALUES="${EXTRA_VALUES} --set controller.metrics.service.clusterIP=${CLUSTER_IP}"
            fi

            get_cluster_ip ${NAMESPACE} ${NAME}-controller-stats
            if [ "${CLUSTER_IP}" != "" ]; then
                EXTRA_VALUES="${EXTRA_VALUES} --set controller.stats.service.clusterIP=${CLUSTER_IP}"
            fi

            get_cluster_ip ${NAMESPACE} ${NAME}-default-backend
            if [ "${CLUSTER_IP}" != "" ]; then
                EXTRA_VALUES="${EXTRA_VALUES} --set defaultBackend.service.clusterIP=${CLUSTER_IP}"
            fi
        fi
    fi

    # for external-dns
    if [ "${NAME}" == "external-dns" ]; then
        replace_chart ${CHART} "AWS_ACCESS_KEY"

        if [ "${ANSWER}" != "" ]; then
            replace_password ${CHART} "AWS_SECRET_KEY" "****"
        fi
    fi

    # for cluster-autoscaler
    if [ "${NAME}" == "cluster-autoscaler" ]; then
        get_cluster_ip ${NAMESPACE} ${NAME}
        if [ "${CLUSTER_IP}" != "" ]; then
            EXTRA_VALUES="${EXTRA_VALUES} --set service.clusterIP=${CLUSTER_IP}"
        fi
    fi

    # for efs-provisioner
    if [ "${NAME}" == "efs-provisioner" ]; then
        efs_create
    fi

    # for k8s-spot-termination-handler
    if [ "${NAME}" == "k8s-spot-termination-handler" ]; then
        replace_chart ${CHART} "SLACK_URL"
    fi

    # for vault
    if [ "${NAME}" == "vault" ]; then
        replace_chart ${CHART} "AWS_ACCESS_KEY"

        if [ "${ANSWER}" != "" ]; then
            _replace "s/#:STORAGE://g" ${CHART}

            replace_password ${CHART} "AWS_SECRET_KEY" "****"

            replace_chart ${CHART} "AWS_BUCKET" "${CLUSTER_NAME}-vault"
        fi
    fi

    # for argo
    if [ "${NAME}" == "argo" ]; then
        replace_chart ${CHART} "ARTIFACT_REPOSITORY" "${CLUSTER_NAME}-artifact"
    fi
    # for argocd
    if [ "${NAME}" == "argocd" ]; then
        replace_chart ${CHART} "GITHUB_ORG"

        if [ "${ANSWER}" != "" ]; then
            _replace "s/#:GITHUB://g" ${CHART}

            _result "New Application: https://github.com/organizations/${ANSWER}/settings/applications"

            _result "Homepage: https://${NAME}-${NAMESPACE}.${BASE_DOMAIN}"
            _result "Callback: https://${NAME}-${NAMESPACE}.${BASE_DOMAIN}/api/dex/callback"

            replace_password ${CHART} "GITHUB_CLIENT_ID" "****"

            replace_password ${CHART} "GITHUB_CLIENT_SECRET" "****"
        fi
    fi

    # for jenkins
    if [ "${NAME}" == "jenkins" ]; then
        # admin password
        replace_password ${CHART}

        # jenkins jobs
        ${SHELL_DIR}/templates/jenkins/jobs.sh ${CHART}
    fi

    # for sonatype-nexus
    if [ "${NAME}" == "sonatype-nexus" ]; then
        # admin password
        replace_password ${CHART}
    fi

    # for prometheus
    if [ "${NAME}" == "prometheus" ]; then
        replace_chart ${CHART} "SLACK_TOKEN"

        # kube-state-metrics
        COUNT=$(kubectl get pods -n kube-system | grep kube-state-metrics | wc -l | xargs)
        if [ "x${COUNT}" == "x0" ]; then
            _replace "s/KUBE_STATE_METRICS/true/g" ${CHART}
        else
            _replace "s/KUBE_STATE_METRICS/false/g" ${CHART}
        fi
    fi

    # for grafana
    if [ "${NAME}" == "grafana" ]; then
        # admin password
        replace_password ${CHART}

        # auth.google
        replace_chart ${CHART} "G_CLIENT_ID"

        if [ "${ANSWER}" != "" ]; then
            _replace "s/#:G_AUTH://g" ${CHART}

            replace_password ${CHART} "G_CLIENT_SECRET" "****"

            replace_chart ${CHART} "G_ALLOWED_DOMAINS"
        else
            # auth.ldap
            replace_chart ${CHART} "GRAFANA_LDAP"

            if [ "${ANSWER}" != "" ]; then
                _replace "s/#:LDAP://g" ${CHART}
            fi
        fi
    fi

    # for datadog
    if [ "${NAME}" == "datadog" ]; then
        # api key
        replace_password ${CHART} "API_KEY" "****"
        # app key
        replace_password ${CHART} "APP_KEY" "****"

        # kube-state-metrics
        COUNT=$(kubectl get pods -n kube-system | grep kube-state-metrics | wc -l | xargs)
        if [ "x${COUNT}" == "x0" ]; then
            _replace "s/KUBE_STATE_METRICS/true/g" ${CHART}
        else
            _replace "s/KUBE_STATE_METRICS/false/g" ${CHART}
        fi
    fi

    # for newrelic-infrastructure
    if [ "${NAME}" == "newrelic-infrastructure" ]; then
        # license key
        replace_password ${CHART} "LICENSE_KEY" "****"
    fi

    # for jaeger
    if [ "${NAME}" == "jaeger" ]; then
        # host
        replace_chart ${CHART} "CUSTOM_HOST" "elasticsearch.domain.com"
        # port
        replace_chart ${CHART} "CUSTOM_PORT" "80"
    fi

    # for fluentd-elasticsearch
    if [ "${NAME}" == "fluentd-elasticsearch" ]; then
        # host
        replace_chart ${CHART} "CUSTOM_HOST" "elasticsearch.domain.com"
        # port
        replace_chart ${CHART} "CUSTOM_PORT" "80"
    fi

    # for elasticsearch-snapshot
    if [ "${NAME}" == "elasticsearch-snapshot" ]; then
        _replace "s/AWS_REGION/${REGION}/g" ${CHART}

        replace_chart ${CHART} "SCHEDULE" "0 0 * * *"

        replace_chart ${CHART} "RESTART" "OnFailure" # "Always", "OnFailure", "Never"

        replace_chart ${CHART} "CONFIGMAP_NAME" "${NAME}"
    fi

    # for efs-mount
    if [ "${EFS_ID}" != "" ]; then
        _replace "s/#:EFS://g" ${CHART}
    fi

    # for master node
    NODE=$(cat ${CHART} | grep '# chart-node:' | awk '{print $3}')
    if [ "${NODE}" == "master" ]; then
        COUNT=$(kubectl get no | grep Ready | grep master | wc -l | xargs)
        if [ "x${COUNT}" != "x0" ]; then
            _replace "s/#:MASTER://g" ${CHART}
        fi
    fi

    # for istio
    if [ "${ISTIO}" == "true" ]; then
        COUNT=$(kubectl get ns ${NAMESPACE} --show-labels | grep 'istio-injection=enabled' | wc -l | xargs)
        if [ "x${COUNT}" != "x0" ]; then
            ISTIO_ENABLED=true
        else
            ISTIO_ENABLED=false
        fi
    else
        ISTIO_ENABLED=false
    fi
    _replace "s/ISTIO_ENABLED/${ISTIO_ENABLED}/g" ${CHART}

    # for ingress
    if [ "${INGRESS}" == "true" ]; then
        if [ -z ${BASE_DOMAIN} ]; then
            DOMAIN=

            _replace "s/SERVICE_TYPE/LoadBalancer/g" ${CHART}
            _replace "s/INGRESS_ENABLED/false/g" ${CHART}
        else
            DOMAIN="${NAME}-${NAMESPACE}.${BASE_DOMAIN}"

            _replace "s/SERVICE_TYPE/ClusterIP/g" ${CHART}
            _replace "s/INGRESS_ENABLED/true/g" ${CHART}
            _replace "s/INGRESS_DOMAIN/${DOMAIN}/g" ${CHART}
            _replace "s/BASE_DOMAIN/${BASE_DOMAIN}/g" ${CHART}
        fi
        _replace "s/#:ING://g" ${CHART}
    fi

    # check exist persistent volume
    COUNT=$(cat ${CHART} | grep '# chart-pvc:' | wc -l | xargs)
    if [ "x${COUNT}" != "x0" ]; then
        LIST=${SHELL_DIR}/build/${CLUSTER_NAME}/pvc-${NAME}-yaml
        cat ${CHART} | grep '# chart-pvc:' | awk '{print $3,$4,$5}' > ${LIST}
        while IFS='' read -r line || [[ -n "$line" ]]; do
            ARR=(${line})
            check_exist_pv ${NAMESPACE} ${ARR[0]} ${ARR[1]} ${ARR[2]}
            RELEASED=$?
            if [ "${RELEASED}" -gt "0" ]; then
                echo "  To use an existing volume, remove the PV's '.claimRef.uid' attribute to make the PV an 'Available' status and try again."
                return
            fi
        done < "${LIST}"
    fi

    # helm install
    if [ "${VERSION}" == "" ] || [ "${VERSION}" == "latest" ]; then
        _command "helm upgrade --install ${NAME} ${REPO} --namespace ${NAMESPACE} --values ${CHART}"
        helm upgrade --install ${NAME} ${REPO} --namespace ${NAMESPACE} --values ${CHART} ${EXTRA_VALUES}
    else
        _command "helm upgrade --install ${NAME} ${REPO} --namespace ${NAMESPACE} --values ${CHART} --version ${VERSION}"
        helm upgrade --install ${NAME} ${REPO} --namespace ${NAMESPACE} --values ${CHART} --version ${VERSION} ${EXTRA_VALUES}
    fi

    # config save
    config_save

    # create pdb
    PDB_MIN=$(cat ${CHART} | grep '# chart-pdb:' | awk '{print $3}')
    PDB_MAX=$(cat ${CHART} | grep '# chart-pdb:' | awk '{print $4}')
    if [ "${PDB_MIN}" != "" ] || [ "${PDB_MAX}" != "" ]; then
        create_pdb ${NAMESPACE} ${NAME} ${PDB_MIN:-N} ${PDB_MAX:-N}
    fi

    _command "helm history ${NAME}"
    helm history ${NAME}

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}"

    _command "kubectl get deploy,pod,svc,ing,pvc,pv -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing,pvc,pv -n ${NAMESPACE}

    # for argo
    if [ "${NAME}" == "argo" ]; then
        create_cluster_role_binding admin default default
    fi

    # for jenkins
    if [ "${NAME}" == "jenkins" ]; then
        create_cluster_role_binding admin ${NAMESPACE} default
    fi

    # for nginx-ingress
    if [[ "${NAME}" == "nginx-ingress"* ]]; then
        set_base_domain "${NAME}"
    fi

    # for nginx-ingress-private
    if [ "${NAME}" == "nginx-ingress-private" ]; then
        question "ingress rule delete all? (YES/[no]) : "
        if [ "${ANSWER}" == "YES" ]; then
            remove_ing_rule
        fi
    fi

    # for efs-provisioner
    if [ "${NAME}" == "efs-provisioner" ]; then
        _command "kubectl get sc -n ${NAMESPACE}"
        kubectl get sc -n ${NAMESPACE}
    fi

    # for kubernetes-dashboard
    if [ "${NAME}" == "kubernetes-dashboard" ]; then
        create_cluster_role_binding view ${NAMESPACE} ${NAME}-view true
    fi

    # chart ingress = true
    if [ "${INGRESS}" == "true" ]; then
        if [ -z ${BASE_DOMAIN} ]; then
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

helm_delete() {
    NAME=

    TEMP=${SHELL_DIR}/build/${CLUSTER_NAME}/helm-temp
    LIST=${SHELL_DIR}/build/${CLUSTER_NAME}/helm-list

    _command "helm ls --all"

    # find all
    helm ls --all --output json \
        | jq -r '"NAMESPACE NAME STATUS REVISION CHART",
                (.Releases[] | "\(.Namespace) \(.Name) \(.Status) \(.Revision) \(.Chart)")' \
        | column -t > ${TEMP}

    printf "\n     $(head -1 ${TEMP})"

    cat ${TEMP} | grep -v "NAMESPACE" | sort > ${LIST}

    # select
    select_one

    if [ "${SELECTED}" == "" ]; then
        return
    fi

    NAME="$(echo ${SELECTED} | awk '{print $2}')"

    if [ "${NAME}" == "" ]; then
        return
    fi

    # for nginx-ingress
    if [[ "${NAME}" == "nginx-ingress"* ]]; then
        ROOT_DOMAIN=
        BASE_DOMAIN=
    fi

    # for efs-provisioner
    if [ "${NAME}" == "efs-provisioner" ]; then
        efs_delete
    fi

    # helm delete
    _command "helm delete --purge ${NAME}"
    helm delete --purge ${NAME}

    # for argo
    if [ "${NAME}" == "argo" ]; then
        COUNT=$(kubectl get pod -n devops | grep argo | grep Running | wc -l | xargs)

        if [ "x${COUNT}" == "x0" ]; then
            delete_crds "argoproj.io"
        fi
    fi

    # config save
    config_save
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

    # default pdb
    default_pdb "${NAMESPACE}"

    # waiting 5
    waiting_pod "${NAMESPACE}" "tiller"

    _command "kubectl get pod,svc -n ${NAMESPACE}"
    kubectl get pod,svc -n ${NAMESPACE}

    helm_repo_update
}

helm_repo() {
    _NAME=$1
    _REPO=$2

    if [ "${_REPO}" == "" ]; then
        if [ "${_NAME}" == "incubator" ]; then
            _REPO="https://storage.googleapis.com/kubernetes-charts-incubator"
        elif [ "${_NAME}" == "argo" ]; then
            _REPO="https://argoproj.github.io/argo-helm"
        elif [ "${_NAME}" == "monocular" ]; then
            _REPO="https://helm.github.io/monocular"
        fi
    fi

    if [ "${_REPO}" != "" ]; then
        COUNT=$(helm repo list | grep -v NAME | awk '{print $1}' | grep "${_NAME}" | wc -l | xargs)

        if [ "x${COUNT}" == "x0" ]; then
            _command "helm repo add ${_NAME} ${_REPO}"
            helm repo add ${_NAME} ${_REPO}

            helm_repo_update
        fi
    fi
}

helm_repo_update() {
    _command "helm repo list"
    helm repo list

    _command "helm repo update"
    helm repo update
}

create_namespace() {
    _NAMESPACE=$1

    CHECK=

    _command "kubectl get ns ${_NAMESPACE}"
    kubectl get ns ${_NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _result "${_NAMESPACE}"

        _command "kubectl create ns ${_NAMESPACE}"
        kubectl create ns ${_NAMESPACE}
    fi
}

create_service_account() {
    _NAMESPACE=$1
    _ACCOUNT=$2

    create_namespace ${_NAMESPACE}

    CHECK=

    _command "kubectl get sa ${_ACCOUNT} -n ${_NAMESPACE}"
    kubectl get sa ${_ACCOUNT} -n ${_NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _result "${_NAMESPACE}:${_ACCOUNT}"

        _command "kubectl create sa ${_ACCOUNT} -n ${_NAMESPACE}"
        kubectl create sa ${_ACCOUNT} -n ${_NAMESPACE}
    fi
}

create_cluster_role_binding() {
    _ROLE=$1
    _NAMESPACE=$2
    _ACCOUNT=${3:-default}
    _TOKEN=${4:-false}

    create_service_account ${_NAMESPACE} ${_ACCOUNT}

    CHECK=

    _command "kubectl get clusterrolebinding ${_ROLE}:${_NAMESPACE}:${_ACCOUNT}"
    kubectl get clusterrolebinding ${_ROLE}:${_NAMESPACE}:${_ACCOUNT} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _result "${_ROLE}:${_NAMESPACE}:${_ACCOUNT}"

        _command "kubectl create clusterrolebinding ${_ROLE}:${_NAMESPACE}:${_ACCOUNT} --clusterrole=${_ROLE} --serviceaccount=${_NAMESPACE}:${_ACCOUNT}"
        kubectl create clusterrolebinding ${_ROLE}:${_NAMESPACE}:${_ACCOUNT} --clusterrole=${_ROLE} --serviceaccount=${_NAMESPACE}:${_ACCOUNT}
    fi

    if [ "${_TOKEN}" == "true" ]; then
        SECRET=$(kubectl get secret -n ${_NAMESPACE} | grep ${_ACCOUNT}-token | awk '{print $1}')

        _command "kubectl describe secret ${SECRET} -n ${_NAMESPACE}"
        kubectl describe secret ${SECRET} -n ${_NAMESPACE} | grep 'token:'
    fi
}

get_replicas() {
    REPLICAS=$(kubectl get deployment -n ${1} -o json | jq -r ".items[] | select(.metadata.name == \"${2}\") | .spec.replicas")
}

get_cluster_ip() {
    CLUSTER_IP=$(kubectl get svc -n ${1} -o json | jq -r ".items[] | select(.metadata.name == \"${2}\") | .spec.clusterIP")
}

default_pdb() {
    _NAMESPACE=${1}

    create_pdb ${_NAMESPACE} coredns 1 N k8s-app kube-dns

    create_pdb ${_NAMESPACE} kube-dns 1 N k8s-app
    create_pdb ${_NAMESPACE} kube-dns-autoscaler N 1 k8s-app

    create_pdb ${_NAMESPACE} tiller-deploy N 1 tiller
}

create_pdb() {
    _NAMESPACE=${1}
    _PDB_NAME=${2}
    _PDB_MIN=${3:-N}
    _PDB_MAX=${4:-N}
    _LABELS=${5:-app}
    _APP_NAME=${6:-${_PDB_NAME}}

    COUNT=$(kubectl get deploy -n kube-system | grep ${_PDB_NAME} | grep -v NAME | wc -l | xargs)
    if [ "x${COUNT}" == "x0" ]; then
        return
    fi

    if [ "${_PDB_NAME}" == "heapster" ]; then
        _APP_NAME="heapster-heapster"
    fi

    YAML=${SHELL_DIR}/build/${CLUSTER_NAME}/pdb-${_PDB_NAME}.yaml
    get_template templates/pdb/pdb-${_LABELS}.yaml ${YAML}

    _replace "s/PDB_NAME/${_PDB_NAME}/g" ${YAML}
    _replace "s/APP_NAME/${_APP_NAME}/g" ${YAML}

    if [ "${_PDB_MIN}" != "N" ]; then
        _replace "s/PDB_MIN/${_PDB_MIN}/g" ${YAML}
        _replace "s/#:MIN://g" ${YAML}
    fi

    if [ "${_PDB_MAX}" != "N" ]; then
        _replace "s/PDB_MAX/${_PDB_MAX}/g" ${YAML}
        _replace "s/#:MAX://g" ${YAML}
    fi

    delete_pdb ${_NAMESPACE} ${_PDB_NAME}

    _command "kubectl apply -n ${_NAMESPACE} -f ${YAML}"
    kubectl apply -n ${_NAMESPACE} -f ${YAML}
}

delete_pdb() {
    _NAMESPACE=${1}
    _PDB_NAME=${2}

    COUNT=$(kubectl get pdb -n kube-system | grep ${_PDB_NAME} | grep -v NAME | wc -l | xargs)
    if [ "x${COUNT}" != "x0" ]; then
        _command "kubectl delete pdb ${_PDB_NAME} -n ${_NAMESPACE}"
        kubectl delete pdb ${_PDB_NAME} -n ${_NAMESPACE}
    fi
}

check_exist_pv() {
    NAMESPACE=${1}
    PVC_NAME=${2}
    PVC_ACCESS_MODE=${3}
    PVC_SIZE=${4}
    PV_NAME=

    PV_NAMES=$(kubectl get pv | grep ${PVC_NAME} | awk '{print $1}')
    for PvName in ${PV_NAMES}; do
        if [ "$(kubectl get pv ${PvName} -o json | jq -r '.spec.claimRef.name')" == "${PVC_NAME}" ]; then
            PV_NAME=${PvName}
        fi
    done

    if [ -z ${PV_NAME} ]; then
        echo "No PersistentVolume."
        # Create a new pvc
        create_pvc ${NAMESPACE} ${PVC_NAME} ${PVC_ACCESS_MODE} ${PVC_SIZE}
    else
        PV_JSON=${SHELL_DIR}/build/${CLUSTER_NAME}/pv-${PVC_NAME}.json

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

    YAML=${SHELL_DIR}/build/${CLUSTER_NAME}/pvc-${PVC_NAME}.yaml
    get_template templates/pvc.yaml ${YAML}

    _replace "s/PVC_NAME/${PVC_NAME}/g" ${YAML}
    _replace "s/PVC_SIZE/${PVC_SIZE}/g" ${YAML}
    _replace "s/PVC_ACCESS_MODE/${PVC_ACCESS_MODE}/g" ${YAML}

    # for efs-provisioner
    if [ ! -z ${EFS_ID} ]; then
        _replace "s/#:EFS://g" ${YAML}
    fi

    # for static pvc
    if [ ! -z ${PV_NAME} ]; then
        _replace "s/#:PV://g" ${YAML}
        _replace "s/PV_NAME/${PV_NAME}/g" ${YAML}
    fi

    _command "kubectl create -n ${NAMESPACE} -f ${YAML}"
    kubectl create -n ${NAMESPACE} -f ${YAML}

    waiting_for isBound ${NAMESPACE} ${PVC_NAME}

    _command "kubectl get pvc,pv -n ${NAMESPACE}"
    kubectl get pvc,pv -n ${NAMESPACE}
}

isBound() {
    NAMESPACE=${1}
    PVC_NAME=${2}

    PVC_STATUS=$(kubectl get pvc -n ${NAMESPACE} ${PVC_NAME} -o json | jq -r '.status.phase')
    if [ "${PVC_STATUS}" != "Bound" ]; then
        return 1
    fi
}

isEFSAvailable() {
    FILE_SYSTEMS=$(aws efs describe-file-systems --file-system-id ${EFS_ID} --region ${REGION})
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
            return 0
        fi
    fi

    return 1
}

isMountTargetAvailable() {
    MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${REGION})
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
            return 0
        fi
    fi

    return 1
}

isMountTargetDeleted() {
    MOUNT_TARGET_LENGTH=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${REGION} | jq -r '.MountTargets | length')
    if [ ${MOUNT_TARGET_LENGTH} == 0 ]; then
        return 0
    else
        return 1
    fi
}

delete_pvc() {
    NAMESPACE=$1
    PVC_NAME=$2

#    POD=$(kubectl -n ${NAMESPACE} get pod -l app=${PVC_NAME} -o jsonpath='{.items[0].metadata.name}')
    _command "kubectl -n ${NAMESPACE} get pod | grep ${PVC_NAME} | awk '{print \$1}'"
    POD=$(kubectl -n ${NAMESPACE} get pod | grep ${PVC_NAME} | awk '{print $1}')
    # Should be deleted releated POD
    if [ -z $POD ]; then
        _command "kubectl delete pvc $PVC_NAME -n $NAMESPACE"
        question "Continue? (YES/[no]) : "
        if [ "${ANSWER}" == "YES" ]; then
            kubectl delete pvc $PVC_NAME -n $NAMESPACE
            echo "Delete PVC $PVC_NAME -n $NAMESPACE"
        fi

    else
        echo "Retry after complete pod($POD) deletion."
    fi
}

delete_save_pv() {
    PV_DIR=$1
    PV_NAME=$2

    # get currnent pv yaml
    YAML=${PV_DIR}/pv-${PV_NAME}.yaml
    _command "kubectl get pv $PV_NAME -o yaml > ${YAML}"
    kubectl get pv $PV_NAME -o yaml > ${YAML}

    _command "kubectl delete pv $PV_NAME"
    question "Continue? (YES/[no]) : "
    if [ "${ANSWER}" == "YES" ]; then
        kubectl delete pv $PV_NAME
    fi
}

validate_pv() {
    # Get efs provisioner mounted EFS fs-id
    _command "kubectl -n kube-system get pod -l app=efs-provisioner -o jsonpath='{.items[0].metadata.name}'"
    EFS_POD=$(kubectl -n kube-system get pod -l app=efs-provisioner -o jsonpath='{.items[0].metadata.name}')

    _command "kubectl exec ${EFS_POD} -n kube-system -- df | grep amazonaws.com | awk '{print \$1}'"
    MNT_SERVER=$(kubectl exec ${EFS_POD} -n kube-system -- df | grep amazonaws.com | awk '{print $1}')

    # list up pv's nfs server fs-id
    PV_LIST=${SHELL_DIR}/build/pv-list
    kubectl get pv | grep -v "NAME" | awk '{print $1, $6}' > ${PV_LIST}

    # variable for current wrong pv list
    WRONG_PV_LIST=${SHELL_DIR}/build/wrong-pv-list
    rm -f $WRONG_PV_LIST

    # Compare pv server and EFS fs-id
    # Save wrong pv list
    while IFS='' read -r line || [[ -n "$line" ]]; do
        ARR=(${line})
        _command "kubectl get pv ${ARR[0]} -o jsonpath='{.spec.nfs.server}'"
        MNT_PV=$(kubectl get pv ${ARR[0]} -o jsonpath='{.spec.nfs.server}')
        echo "check efs-id "
        echo "    EFS-PROVISIONER :${MNT_SERVER}"
        echo "    PersistentVolume:${MNT_PV}"

        if [[ "$MNT_SERVER" == "$MNT_PV"* ]]; then
            echo "PASS - ${line} have CORRECT EFS-ID"
        else
            echo "WARNNING - ${line} have WRONG EFS-ID"
            echo "${line}" >> ${WRONG_PV_LIST}
        fi
    done < "${PV_LIST}"

    # delete_pvc, if you want.
    if [ -f ${WRONG_PV_LIST} ]; then
        # check pv list for delete
        cat ${WRONG_PV_LIST}
        question "Would you like to delete PV, PVC? (YES/[no]) : "
        if [ "${ANSWER}" == "YES" ]; then
            # save pv yaml files.
            PV_DIR=${SHELL_DIR}/build/${CLUSTER_NAME}/old-pv
            mkdir -p ${PV_DIR}

            # iter for delete and save
            while IFS='' read -r -u9 line || [[ -n "$line" ]]; do
                ARR=(${line})
                while IFS='/' read -ra NS_NM; do
                    NAMESPACE=${NS_NM[0]}
                    PVC_NAME=${NS_NM[1]}
                done <<< "${ARR[1]}"

                delete_pvc ${NAMESPACE} ${PVC_NAME}
                delete_save_pv ${PV_DIR} ${ARR[0]}
            done 9< "${WRONG_PV_LIST}"

            echo "Saved PV list."
            ls -aslF ${PV_DIR}
            echo "Edit for new EFS and command kubectl apply -f ..."
        fi
    fi
}

efs_create() {
    CONFIG_SAVE=true

    if [ "${EFS_ID}" == "" ]; then
        EFS_ID=$(aws efs describe-file-systems --creation-token ${CLUSTER_NAME} --region ${REGION} | jq -r '.FileSystems[].FileSystemId')
    fi

    question "Input your file system id. [${EFS_ID}] : "
    EFS_ID=${ANSWER:-${EFS_ID}}

    if [ "${EFS_ID}" == "" ]; then
        echo
        echo "Creating a elastic file system"

        EFS_ID=$(aws efs create-file-system --creation-token ${CLUSTER_NAME} --region ${REGION} | jq -r '.FileSystemId')
        aws efs create-tags \
            --file-system-id ${EFS_ID} \
            --tags Key=Name,Value=efs.${CLUSTER_NAME} \
            --region ap-northeast-2
    fi

    if [ "${EFS_ID}" == "" ]; then
        _error "Not found the EFS."
    fi

    _result "EFS_ID=${EFS_ID}"

    # replace EFS_ID
    _replace "s/EFS_ID/${EFS_ID}/g" ${CHART}

    # owned
    OWNED=$(aws efs describe-file-systems --file-system-id ${EFS_ID} | jq -r '.FileSystems[].Tags[] | values[]' | grep "kubernetes.io/cluster/${CLUSTER_NAME}")
    if [ "${OWNED}" != "" ]; then
        return
    fi

    # get the security group id
    WORKER_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=nodes.${CLUSTER_NAME}" | jq -r '.SecurityGroups[0].GroupId')
    if [ -z ${WORKER_SG_ID} ] || [ "${WORKER_SG_ID}" == "null" ]; then
        _error "Not found the security group for the nodes."
    fi

    _result "WORKER_SG_ID=${WORKER_SG_ID}"

    # get vpc id
    VPC_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=nodes.${CLUSTER_NAME}" | jq -r '.SecurityGroups[0].VpcId')

    if [ -z ${VPC_ID} ]; then
        _error "Not found the VPC."
    fi

    _result "VPC_ID=${VPC_ID}"

    # get subent ids
    VPC_PRIVATE_SUBNETS_LENGTH=$(aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=shared" "Name=tag:SubnetType,Values=Private" | jq '.Subnets | length')
    if [ ${VPC_PRIVATE_SUBNETS_LENGTH} -gt 0 ]; then
        VPC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=shared" "Name=tag:SubnetType,Values=Private" | jq -r '(.Subnets[].SubnetId)')
    else
        VPC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=shared" | jq -r '(.Subnets[].SubnetId)')
    fi

    _result "VPC_SUBNETS=$(echo ${VPC_SUBNETS} | xargs)"

    # create a security group for efs mount targets
    EFS_SG_LENGTH=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${CLUSTER_NAME}" | jq '.SecurityGroups | length')
    if [ ${EFS_SG_LENGTH} -eq 0 ]; then
        echo
        echo "Creating a security group for mount targets"

        EFS_SG_ID=$(aws ec2 create-security-group \
            --region ${REGION} \
            --group-name efs-sg.${CLUSTER_NAME} \
            --description "Security group for EFS mount targets" \
            --vpc-id ${VPC_ID} | jq -r '.GroupId')

        aws ec2 authorize-security-group-ingress \
            --group-id ${EFS_SG_ID} \
            --protocol tcp \
            --port 2049 \
            --source-group ${WORKER_SG_ID} \
            --region ${REGION}
    else
        EFS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${CLUSTER_NAME}" | jq -r '.SecurityGroups[].GroupId')
    fi

    # echo "Security group for mount targets:"
    _result "EFS_SG_ID=${EFS_SG_ID}"

    echo
    echo "Waiting for the state of the EFS to be available."
    waiting_for isEFSAvailable

    # create mount targets
    EFS_MOUNT_TARGET_LENGTH=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${REGION} | jq -r '.MountTargets | length')
    if [ ${EFS_MOUNT_TARGET_LENGTH} -eq 0 ]; then
        echo "Creating mount targets"

        for SubnetId in ${VPC_SUBNETS}; do
            EFS_MOUNT_TARGET_ID=$(aws efs create-mount-target \
                --file-system-id ${EFS_ID} \
                --subnet-id ${SubnetId} \
                --security-group ${EFS_SG_ID} \
                --region ${REGION} | jq -r '.MountTargetId')
            EFS_MOUNT_TARGET_IDS=(${EFS_MOUNT_TARGET_IDS[@]} ${EFS_MOUNT_TARGET_ID})
        done
    else
        EFS_MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${REGION} | jq -r '.MountTargets[].MountTargetId')
    fi

    _result "EFS_MOUNT_TARGET_IDS=$(echo ${EFS_MOUNT_TARGET_IDS[@]} | xargs)"

    echo
    echo "Waiting for the state of the EFS mount targets to be available."
    waiting_for isMountTargetAvailable
}

efs_delete() {
    CONFIG_SAVE=true

    if [ "${EFS_ID}" == "" ]; then
        return
    fi

    # owned
    OWNED=$(aws efs describe-file-systems --file-system-id ${EFS_ID} | jq -r '.FileSystems[].Tags[] | values[]' | grep "kubernetes.io/cluster/${CLUSTER_NAME}")
    if [ "${OWNED}" == "" ]; then
        # delete mount targets
        EFS_MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${REGION} | jq -r '.MountTargets[].MountTargetId')
        for MountTargetId in ${EFS_MOUNT_TARGET_IDS}; do
            echo "Deleting the mount targets"
            aws efs delete-mount-target --mount-target-id ${MountTargetId}
        done

        echo "Waiting for the EFS mount targets to be deleted."
        waiting_for isMountTargetDeleted

        # delete security group for efs mount targets
        EFS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=efs-sg.${CLUSTER_NAME}" | jq -r '.SecurityGroups[0].GroupId')
        if [ -n ${EFS_SG_ID} ]; then
            echo "Deleting the security group for mount targets"
            aws ec2 delete-security-group --group-id ${EFS_SG_ID}
        fi

        # delete efs
        if [ -n ${EFS_ID} ]; then
            echo "Deleting the elastic file system"
            aws efs delete-file-system --file-system-id ${EFS_ID} --region ${REGION}
        fi
    fi

    EFS_ID=

    _result "EFS_ID=${EFS_ID}"
}

istio_init() {
    helm_check

    NAME="istio"
    NAMESPACE="istio-system"

    ISTIO_TMP=${SHELL_DIR}/build/istio
    mkdir -p ${ISTIO_TMP}

    CHART=${SHELL_DIR}/charts/istio/istio.yaml
    VERSION=$(cat ${CHART} | grep '# chart-version:' | awk '{print $3}')

    if [ "${VERSION}" == "" ] || [ "${VERSION}" == "latest" ]; then
        VERSION=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | jq -r '.tag_name')
    fi

    _result "${NAME} ${VERSION}"

    # istio download
    if [ ! -d ${ISTIO_TMP}/${NAME}-${VERSION} ]; then
        if [ "${OS_NAME}" == "darwin" ]; then
            OSEXT="osx"
        else
            OSEXT="linux"
        fi

        URL="https://github.com/istio/istio/releases/download/${VERSION}/istio-${VERSION}-${OSEXT}.tar.gz"

        pushd ${ISTIO_TMP}
        curl -sL "${URL}" | tar xz
        popd
    fi

    ISTIO_DIR=${ISTIO_TMP}/${NAME}-${VERSION}/install/kubernetes/helm/istio
}

istio_secret() {
    YAML=${SHELL_DIR}/build/${CLUSTER_NAME}/istio-secret.yaml
    get_template templates/istio-secret.yaml ${YAML}

    replace_base64 ${YAML} "USERNAME" "admin"
    replace_base64 ${YAML} "PASSWORD" "password"

    _command "kubectl apply -n ${NAMESPACE} -f ${YAML}"
    kubectl apply -n ${NAMESPACE} -f ${YAML}
}

istio_show_pod_ips() {
    export PILOT_POD_IP=$(kubectl -n istio-system get pod -l istio=pilot -o jsonpath='{.items[0].status.podIP}')
    export POLICY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=policy -o jsonpath='{.items[0].status.podIP}')
    export STATSD_POD_IP=$(kubectl -n istio-system get pod -l istio=statsd-prom-bridge -o jsonpath='{.items[0].status.podIP}')
    export TELEMETRY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=telemetry -o jsonpath='{.items[0].status.podIP}')
    export ZIPKIN_POD_IP=$(kubectl -n istio-system get pod -l app=jaeger -o jsonpath='{range .items[*]}{.status.podIP}{end}')

    echo "export PILOT_POD_IP=$PILOT_POD_IP"
    echo "export POLICY_POD_IP=$POLICY_POD_IP"
    echo "export STATSD_POD_IP=$STATSD_POD_IP"
    echo "export TELEMETRY_POD_IP=$TELEMETRY_POD_IP"
    echo "export ZIPKIN_POD_IP=$ZIPKIN_POD_IP"
}

istio_import_config_to_secret() {
    ls -lrt
    question "Enter your env files : "
    source ${ANSWER}

    _command "kubectl create secret generic ${CLUSTER_NAME} --from-file ${KUBECFG_FILE} -n ${NAMESPACE}"
    kubectl create secret generic ${CLUSTER_NAME} --from-file ${KUBECFG_FILE} -n ${NAMESPACE}

    _command "kubectl label secret ${CLUSTER_NAME} istio/multiCluster=true -n ${NAMESPACE}"
    kubectl label secret ${CLUSTER_NAME} istio/multiCluster=true -n ${NAMESPACE}

    _command "kubectl get secret ${CLUSTER_NAME} -n ${NAMESPACE} -o json"
    kubectl get secret ${CLUSTER_NAME} -n ${NAMESPACE} -o json
}

istio_export_config() {
    export WORK_DIR=$(pwd)
    CLUSTER_NAME=$(kubectl config view --minify=true -o "jsonpath={.clusters[].name}")
    export KUBECFG_FILE=${WORK_DIR}/${CLUSTER_NAME}
    export KUBECFG_ENV_FILE="${WORK_DIR}/${CLUSTER_NAME}-remote-cluster-env-vars"
    SERVER=$(kubectl config view --minify=true -o "jsonpath={.clusters[].cluster.server}")
    NAMESPACE=istio-system
    SERVICE_ACCOUNT=istio-multi
    SECRET_NAME=$(kubectl get sa ${SERVICE_ACCOUNT} -n ${NAMESPACE} -o jsonpath='{.secrets[].name}')
    CA_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o "jsonpath={.data['ca\.crt']}")
    TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o "jsonpath={.data['token']}" | base64 --decode)

    cat <<EOF > ${KUBECFG_FILE}
apiVersion: v1
clusters:
- cluster:
   certificate-authority-data: ${CA_DATA}
   server: ${SERVER}
 name: ${CLUSTER_NAME}
contexts:
- context:
   cluster: ${CLUSTER_NAME}
   user: ${CLUSTER_NAME}
 name: ${CLUSTER_NAME}
current-context: ${CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: ${CLUSTER_NAME}
 user:
   token: ${TOKEN}
EOF

    cat <<EOF > ${KUBECFG_ENV_FILE}
export CLUSTER_NAME=${CLUSTER_NAME}
export KUBECFG_FILE=${KUBECFG_FILE}
export NAMESPACE=${NAMESPACE}
EOF

    _command "cat ${KUBECFG_FILE}"
    cat ${KUBECFG_FILE}

    _command "cat ${KUBECFG_ENV_FILE}"
    cat ${KUBECFG_ENV_FILE}

    _command "ls -aslF ${KUBECFG_FILE} ${KUBECFG_ENV_FILE}"
    ls -aslF ${KUBECFG_FILE} ${KUBECFG_ENV_FILE}
#    ls -aslF ${KUBECFG_FILE}
#    ls -aslF ${KUBECFG_ENV_FILE}
}

waiting_istio_init() {
    SEC=10
    RET=0
    IDX=0
    while true; do
        RET=$(echo -e `kubectl get crds | grep 'istio.io\|certmanager.k8s.io' | wc -l`)
        printf ${RET}

        if [ ${RET} -gt 52 ]; then
            echo " init ok"
            break
        elif [ "x${IDX}" == "x${SEC}" ]; then
            _result "Timeout"
            break
        fi

        IDX=$(( ${IDX} + 1 ))
        sleep 2
    done
}

istio_install() {
    istio_init

    create_namespace ${NAMESPACE}

    # istio 1.1.x init
    if [[ "${VERSION}" == "1.1."* ]]; then
        _command "helm upgrade --install ${ISTIO_DIR}-init --name istio-init --namespace ${NAMESPACE}"
        helm upgrade --install istio-init ${ISTIO_DIR}-init --namespace ${NAMESPACE}

        # result will be more than 53
        waiting_istio_init
    fi

    CHART=${SHELL_DIR}/build/${CLUSTER_NAME}/${NAME}.yaml
    get_template charts/istio/${NAME}.yaml ${CHART}

    # # ingress
    # if [ -z ${BASE_DOMAIN} ]; then
    #     _replace "s/SERVICE_TYPE/LoadBalancer/g" ${CHART}
    #     _replace "s/INGRESS_ENABLED/false/g" ${CHART}
    # else
    #     _replace "s/SERVICE_TYPE/ClusterIP/g" ${CHART}
    #     _replace "s/INGRESS_ENABLED/true/g" ${CHART}
    #     _replace "s/BASE_DOMAIN/${BASE_DOMAIN}/g" ${CHART}
    # fi

    # # istio secret
    # istio_secret

    # helm install
    _command "helm upgrade --install ${NAME} ${ISTIO_DIR} --namespace ${NAMESPACE} --values ${CHART}"
    helm upgrade --install ${NAME} ${ISTIO_DIR} --namespace ${NAMESPACE} --values ${CHART}

    # kiali sa
    # create_cluster_role_binding view ${NAMESPACE} kiali-service-account

    ISTIO=true
    CONFIG_SAVE=true

    # save config (ISTIO)
    config_save

    # waiting 2
    waiting_pod "${NAMESPACE}" "${NAME}"

    # set_base_domain "istio-ingressgateway"

    _command "helm history ${NAME}"
    helm history ${NAME}

    _command "kubectl get deploy,pod,svc,ing -n ${NAMESPACE}"
    kubectl get deploy,pod,svc,ing -n ${NAMESPACE}
}

istio_remote_install() {
    istio_init

    RNAME="istio-remote"

    RISTIO_DIR="${ISTIO_DIR}-remote"

    create_namespace ${NAMESPACE}

    CHART=${SHELL_DIR}/build/${THIS_NAME}-istio-${NAME}.yaml
    get_template charts/istio/${NAME}.yaml ${CHART}

    if [ -z ${PILOT_POD_IP} ]; then
        echo "PILOT_POD_IP=$PILOT_POD_IP"
    fi
    if [ -z ${POLICY_POD_IP} ]; then
        echo "POLICY_POD_IP=$POLICY_POD_IP"
    fi
    if [ -z ${STATSD_POD_IP} ]; then
        echo "STATSD_POD_IP=$STATSD_POD_IP"
    fi
    if [ -z ${TELEMETRY_POD_IP} ]; then
        echo "TELEMETRY_POD_IP=$TELEMETRY_POD_IP"
    fi
    if [ -z ${ZIPKIN_POD_IP} ]; then
        echo "ZIPKIN_POD_IP=$ZIPKIN_POD_IP"
    fi

    _command "helm upgrade --install ${RNAME} ${RISTIO_DIR} --namespace ${NAMESPACE} --set global.remotePilotAddress=${PILOT_POD_IP} --set global.remotePolicyAddress=${POLICY_POD_IP} --set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} --set global.proxy.envoyStatsd.enabled=true --set global.proxy.envoyStatsd.host=${STATSD_POD_IP} --set global.remoteZipkinAddress=${ZIPKIN_POD_IP}"
    helm upgrade --install ${RNAME} ${RISTIO_DIR} --namespace ${NAMESPACE} \
                 --set global.remotePilotAddress=${PILOT_POD_IP} \
                 --set global.remotePolicyAddress=${POLICY_POD_IP} \
                 --set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} \
                 --set global.proxy.envoyStatsd.enabled=true \
                 --set global.proxy.envoyStatsd.host=${STATSD_POD_IP} \
                 --set global.remoteZipkinAddress=${ZIPKIN_POD_IP}

    ISTIO=true
    CONFIG_SAVE=true

    # save config (ISTIO)
    config_save

    # waiting 2
    waiting_pod "${NAMESPACE}" "${RNAME}"

    _command "helm history ${RNAME}"
    helm history ${RNAME}

    _command "kubectl get deploy,pod,svc -n ${NAMESPACE}"
    kubectl get deploy,pod,svc -n ${NAMESPACE}
}

istio_injection() {
    CMD=$1

    if [ -z ${CMD} ]; then
        _command "kubectl get ns --show-labels"
        kubectl get ns --show-labels
        return
    fi

    LIST=${SHELL_DIR}/build/${CLUSTER_NAME}/istio-ns-list

    # find
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
    istio_init

    # helm delete
    _command "helm delete --purge ${NAME}"
    helm delete --purge ${NAME}

    _command "helm delete --purge istio-init"
    helm delete --purge istio-init

    # delete crds
    delete_crds "istio.io"

    # delete ns
    _command "kubectl delete namespace ${NAMESPACE}"
    kubectl delete namespace ${NAMESPACE}

    ISTIO=
    CONFIG_SAVE=true

    # save config (ISTIO)
    config_save
}

delete_crds() {
    # delete crds
    LIST="$(kubectl get crds | grep ${1} | awk '{print $1}')"
    if [ "${LIST}" != "" ]; then
        _command "kubectl delete crds *.${1}"
        kubectl delete crds ${LIST}
    fi
}

get_cluster() {
    # config list
    LIST=${SHELL_DIR}/build/${THIS_NAME}/config-list
    kubectl config view -o json | jq -r '.contexts[].name' | sort > ${LIST}

    # select
    select_one true

    if [ "${SELECTED}" == "" ]; then
        _error
    fi

    CLUSTER_NAME="${SELECTED}"

    mkdir -p ${SHELL_DIR}/build/${CLUSTER_NAME}

    _command "kubectl config use-context ${CLUSTER_NAME}"
    kubectl config use-context ${CLUSTER_NAME}
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
    LIST=${SHELL_DIR}/build/${THIS_NAME}/hosted-zones

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
    _command "aws acm list-certificates | DOMAIN="${SUB_DOMAIN}.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn'"
    SSL_CERT_ARN=$(aws acm list-certificates | DOMAIN="${SUB_DOMAIN}.${BASE_DOMAIN}" jq -r '.CertificateSummaryList[] | select(.DomainName==env.DOMAIN) | .CertificateArn')
}

req_ssl_cert_arn() {
    if [ -z ${ROOT_DOMAIN} ] || [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # request certificate
    _command "aws acm request-certificate --domain-name "${SUB_DOMAIN}.${BASE_DOMAIN}" --validation-method DNS | jq -r '.CertificateArn'"
    SSL_CERT_ARN=$(aws acm request-certificate --domain-name "${SUB_DOMAIN}.${BASE_DOMAIN}" --validation-method DNS | jq -r '.CertificateArn')

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
    RECORD=${SHELL_DIR}/build/${CLUSTER_NAME}/record-sets-cname.json
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
    RECORD=${SHELL_DIR}/build/${CLUSTER_NAME}/record-sets-alias.json
    get_template templates/record-sets-alias.json ${RECORD}

    # replace
    _replace "s/DOMAIN/${SUB_DOMAIN}.${BASE_DOMAIN}/g" ${RECORD}
    _replace "s/ZONE_ID/${ELB_ZONE_ID}/g" ${RECORD}
    _replace "s/DNS_NAME/${ELB_DNS_NAME}/g" ${RECORD}

    cat ${RECORD}

    question "Would you like to change route53? (YES/[no]) : "

    if [ "${ANSWER}" == "YES" ]; then
        # update route53 record
        _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
        aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
    else
        _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
    fi
}

set_record_delete() {
    if [ -z ${ROOT_DOMAIN} ] || [ -z ${BASE_DOMAIN} ]; then
        return
    fi

    # Route53 에서 해당 도메인의 Hosted Zone ID 를 획득
    _command "aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3"
    ZONE_ID=$(aws route53 list-hosted-zones | ROOT_DOMAIN="${ROOT_DOMAIN}." jq -r '.HostedZones[] | select(.Name==env.ROOT_DOMAIN) | .Id' | cut -d'/' -f3)

    if [ -z ${ZONE_ID} ]; then
        return
    fi

    # record sets
    RECORD=${SHELL_DIR}/build/${CLUSTER_NAME}/record-sets-delete.json
    get_template templates/record-sets-delete.json ${RECORD}

    # replace
    _replace "s/DOMAIN/${SUB_DOMAIN}.${BASE_DOMAIN}/g" ${RECORD}

    cat ${RECORD}

    # update route53 record
    _command "aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}"
    aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file://${RECORD}
}

set_base_domain() {
    POD="${1:-nginx-ingress}"

    SUB_DOMAIN=${2:-"*"}

    _result "Pending ELB..."

    if [ -z ${BASE_DOMAIN} ]; then
        get_ingress_nip_io ${POD}
    else
        get_ingress_elb_name ${POD}

        set_record_alias
    fi
}

get_base_domain() {
    SUB_DOMAIN=${1:-"*"}

    PREV_ROOT_DOMAIN="${ROOT_DOMAIN}"
    PREV_BASE_DOMAIN="${BASE_DOMAIN}"

    ROOT_DOMAIN=
    BASE_DOMAIN=

    read_root_domain

    # base domain
    if [ ! -z ${ROOT_DOMAIN} ]; then
        if [ "${PREV_ROOT_DOMAIN}" != "" ] && [ "${ROOT_DOMAIN}" == "${PREV_ROOT_DOMAIN}" ]; then
            DEFAULT="${PREV_BASE_DOMAIN}"
        else
            WORD=$(echo ${CLUSTER_NAME} | cut -d'.' -f1)
            DEFAULT="${WORD}.${ROOT_DOMAIN}"
        fi

        question "Enter your ingress domain [${DEFAULT}] : "

        BASE_DOMAIN=${ANSWER:-${DEFAULT}}
    fi

    # certificate
    if [ ! -z ${BASE_DOMAIN} ]; then
        get_ssl_cert_arn

        if [ -z ${SSL_CERT_ARN} ]; then
            req_ssl_cert_arn
        fi
        if [ -z ${SSL_CERT_ARN} ]; then
            _error "Certificate ARN does not exists. [${ROOT_DOMAIN}][${SUB_DOMAIN}.${BASE_DOMAIN}][${REGION}]"
        fi

        _result "CertificateArn: ${SSL_CERT_ARN}"

        TEXT="aws-load-balancer-ssl-cert"
        _replace "s@${TEXT}:.*@${TEXT}: ${SSL_CERT_ARN}@" ${CHART}

        TEXT="external-dns.alpha.kubernetes.io/hostname"
        _replace "s@${TEXT}:.*@${TEXT}: \"${SUB_DOMAIN}.${BASE_DOMAIN}.\"@" ${CHART}
    fi

    # private ingress controller should not be BASE_DOMAIN
    if [[ "${BASE_DOMAIN}" == *"private"* ]]; then
        BASE_DOMAIN="${PREV_BASE_DOMAIN}"
    fi

    CONFIG_SAVE=true
}

replace_chart() {
    _CHART=${1}
    _KEY=${2}
    _DEFAULT=${3}

    if [ "${_DEFAULT}" != "" ]; then
        question "Enter ${_KEY} [${_DEFAULT}] : "
        if [ "${ANSWER}" == "" ]; then
            ANSWER=${_DEFAULT}
        fi
    else
        question "Enter ${_KEY} : "
    fi

    _result "${_KEY}: ${ANSWER}"

    _replace "s|${_KEY}|${ANSWER}|g" ${CHART}
}

replace_password() {
    _CHART=${1}
    _KEY=${2:-PASSWORD}
    _DEFAULT=${3:-password}

    password "Enter ${_KEY} [${_DEFAULT}] : "
    if [ "${ANSWER}" == "" ]; then
        ANSWER=${_DEFAULT}
    fi

    echo
    _result "${_KEY}: [hidden]"

    _replace "s|${_KEY}|${ANSWER}|g" ${_CHART}
}

replace_base64() {
    _CHART=${1}
    _KEY=${2:-PASSWORD}
    _DEFAULT=${3:-password}

    password "Enter ${_KEY} [${_DEFAULT}] : "
    if [ "${ANSWER}" == "" ]; then
        ANSWER=${_DEFAULT}
    fi

    echo
    _result "${_KEY}: [encoded]"

    _replace "s|${_KEY}|$(echo ${ANSWER} | base64)|g" ${_CHART}
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

waiting_deploy() {
    _NS=${1}
    _NM=${2}
    SEC=${3:-10}

    _command "kubectl get deploy -n ${_NS} | grep ${_NM}"
    kubectl get deploy -n ${_NS} | head -1

    DEPLOY=${SHELL_DIR}/build/${THIS_NAME}/waiting-pod

    IDX=0
    while true; do
        kubectl get deploy -n ${_NS} | grep ${_NM} | head -1 > ${DEPLOY}
        cat ${DEPLOY}

        CURRENT=$(cat ${DEPLOY} | awk '{print $5}' | cut -d'/' -f1)

        if [ "x${CURRENT}" != "x0" ]; then
            break
        elif [ "x${IDX}" == "x${SEC}" ]; then
            _result "Timeout"
            break
        fi

        IDX=$(( ${IDX} + 1 ))
        sleep 2
    done
}

waiting_pod() {
    _NS=${1}
    _NM=${2}
    SEC=${3:-10}

    _command "kubectl get pod -n ${_NS} | grep ${_NM}"
    kubectl get pod -n ${_NS} | head -1

    POD=${SHELL_DIR}/build/${THIS_NAME}/waiting-pod

    IDX=0
    while true; do
        kubectl get pod -n ${_NS} | grep ${_NM} | head -1 > ${POD}
        cat ${POD}

        READY=$(cat ${POD} | awk '{print $2}' | cut -d'/' -f1)
        STATUS=$(cat ${POD} | awk '{print $3}')

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

run
