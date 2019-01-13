#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

L_PAD="$(printf %2s)"

command -v fzf > /dev/null && FZF=true
command -v tput > /dev/null && TPUT=true

_echo() {
    if [ -n ${TPUT} ] && [ -n $2 ]; then
        echo -e "${L_PAD}$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "${L_PAD}$1"
    fi
}

_read() {
    if [ "${3}" == "S" ]; then
        if [ -n ${TPUT} ] && [ -n $2 ]; then
            read -s -p "${L_PAD}$(tput setaf $2)$1$(tput sgr0)" PASSWORD
        else
            read -s -p "${L_PAD}$1" PASSWORD
        fi
    else
        if [ -n ${TPUT} ] && [ -n $2 ]; then
            read -p "${L_PAD}$(tput setaf $2)$1$(tput sgr0)" ANSWER
        else
            read -p "${L_PAD}$1" ANSWER
        fi
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
    echo
    _echo "$ $@" 3
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
    _read "${1:-"Enter your password : "}" 6 S
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
    if [ "x${ANSWER}" == "x" ] || [ "x${ANSWER}" == "x0" ]; then
        return
    fi
    # TEST='^[0-9]+$'
    # if ! [[ ${ANSWER} =~ ${TEST} ]]; then
    #     return
    # fi
    SELECTED=$(sed -n ${ANSWER}p ${LIST})
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

get_az_list() {
    if [ -z ${AZ_LIST} ]; then
        AZ_LIST="$(aws ec2 describe-availability-zones | jq -r '.AvailabilityZones[].ZoneName' | head -3 | tr -s '\r\n' ',' | sed 's/.$//')"
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

get_template() {
    rm -rf ${2}
    if [ -f ${SHELL_DIR}/${1} ]; then
        cat ${SHELL_DIR}/${1} > ${2}
    else
        curl -sL https://raw.githubusercontent.com/${THIS_REPO}/${THIS_NAME}/master/${1} > ${2}
    fi
    if [ ! -f ${2} ]; then
        _error "Template does not exists. [${1}]"
    fi
}

update_tools() {
    ${SHELL_DIR}/tools.sh

    _success "Please restart!"
}

update_self() {
    pushd ${SHELL_DIR}
    git pull
    popd

    _success "Please restart!"
}

logo() {
    if [ -n ${TPUT} ]; then
        tput clear
        tput setaf 3
    fi

    cat ${SHELL_DIR}/templates/kops-cui-logo.txt
    echo

    if [ -n ${TPUT} ]; then
        tput sgr0
    fi
}

config_save() {
    CONFIG=${SHELL_DIR}/build/${THIS_NAME}-config.sh
    echo "# ${THIS_NAME} config" > ${CONFIG}
    echo "CLUSTER_NAME=${CLUSTER_NAME}" >> ${CONFIG}
    echo "ROOT_DOMAIN=${ROOT_DOMAIN}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}
    echo "EFS_ID=${EFS_ID}" >> ${CONFIG}
    echo "ISTIO=${ISTIO}" >> ${CONFIG}

    _command "save ${THIS_NAME}-config"
    cat ${CONFIG}

    ENCODED=${SHELL_DIR}/build/${THIS_NAME}-config.txt

    if [ "${OS_NAME}" == "darwin" ]; then
        cat ${CONFIG} | base64 > ${ENCODED}
    else
        cat ${CONFIG} | base64 -w 0 > ${ENCODED}
    fi

    CONFIG=${SHELL_DIR}/build/${THIS_NAME}-config.yaml
    get_template templates/config.yaml ${CONFIG}

    _replace "s/REPLACE-ME/${THIS_NAME}-config/" ${CONFIG}

    sed "s/^/    /" ${ENCODED} >> ${CONFIG}

    kubectl apply -f ${CONFIG} -n default
}

config_load() {
    COUNT=$(kubectl get pod -n kube-system | wc -l | xargs)

    if [ "x${COUNT}" == "x0" ]; then
        _error "Unable to connect to the cluster."
    fi

    COUNT=$(kubectl get secret -n default | grep ${THIS_NAME}-config  | wc -l | xargs)

    if [ "x${COUNT}" != "x0" ]; then
        CONFIG=${SHELL_DIR}/build/${THIS_NAME}-config.sh

        if [ "${OS_NAME}" == "darwin" ]; then
            kubectl get secret ${THIS_NAME}-config -n default -o json | jq -r '.data.text' | base64 -D > ${CONFIG}
        else
            kubectl get secret ${THIS_NAME}-config -n default -o json | jq -r '.data.text' | base64 -d > ${CONFIG}
        fi

        _command "load ${THIS_NAME}-config"
        cat ${CONFIG}

        . ${CONFIG}
    fi
}
