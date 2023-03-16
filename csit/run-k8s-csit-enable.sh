#!/bin/bash
#
# ============LICENSE_START====================================================
#  Copyright (C) 2022-2023 Nordix Foundation.
# =============================================================================
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
# ============LICENSE_END======================================================

# This script spins up kubernetes cluster in Microk8s for deploying policy helm charts.
# Runs CSITs in kubernetes.

if [ -z "${WORKSPACE}" ]; then
    WORKSPACE=$(git rev-parse --show-toplevel)
    export WORKSPACE
fi

CSIT_SCRIPT="scripts/run-test.sh"
ROBOT_DOCKER_IMAGE="policy-csit-robot"
POLICY_CLAMP_ROBOT="policy-clamp-test.robot"
POLICY_API_ROBOT="api-test.robot api-slas.robot"
POLICY_PAP_ROBOT="pap-test.robot pap-slas.robot"
POLICY_APEX_PDP_ROBOT="apex-pdp-test.robot apex-slas.robot"
POLICY_XACML_PDP_ROBOT="xacml-pdp-test.robot"
POLICY_DROOLS_PDP_ROBOT="drools-pdp-test.robot"
POLICY_DISTRIBUTION_ROBOT="distribution-test.robot"
POLICY_API_CONTAINER="policy-api"
POLICY_PAP_CONTAINER="policy-pap"
POLICY_CLAMP_CONTAINER="policy-clamp-runtime-acm"
POLICY_APEX_CONTAINER="policy-apex-pdp"
POLICY_DROOLS_CONTAINER="policy-drools-pdp"
POLICY_XACML_CONTAINER="policy-xacml-pdp"
POLICY_DISTRIBUTION_CONTAINER="policy-distribution"
SET_VALUES=""

DISTRIBUTION_CSAR=${WORKSPACE}/csit/resources/tests/data/csar
DIST_TEMP_FOLDER=/tmp/distribution

export PROJECT=""
export ROBOT_FILE=""
export ROBOT_LOG_DIR=${WORKSPACE}/csit/archives
export READINESS_CONTAINERS=()

function spin_microk8s_cluster() {
    echo "Verify if Microk8s cluster is running.."
    microk8s version
    exitcode="${?}"

    if [ "$exitcode" -ne 0 ]; then
        echo "Microk8s cluster not available, Spinning up the cluster.."
        sudo snap install microk8s --classic --channel=1.25/stable

        if [ "${?}" -ne 0 ]; then
            echo "Failed to install kubernetes cluster. Aborting.."
            return 1
        fi
        echo "Microk8s cluster installed successfully"
        sudo usermod -a -G microk8s $USER
        echo "Enabling DNS and helm3 plugins"
        sudo microk8s.enable dns helm3 hostpath-storage
        echo "Creating configuration file for Microk8s"
        sudo mkdir -p $HOME/.kube
        sudo chown -R $USER:$USER $HOME/.kube
        sudo microk8s kubectl config view --raw >$HOME/.kube/config
        sudo chmod 600 $HOME/.kube/config
        echo "K8s installation completed"
        echo "----------------------------------------"
    else
        echo "K8s cluster is already running"
        echo "----------------------------------------"
        return 0
    fi

}

function teardown_cluster() {
    echo "Removing k8s cluster and k8s configuration file"
    sudo microk8s helm uninstall csit-policy
    sudo microk8s helm uninstall prometheus
    sudo microk8s helm uninstall csit-robot
    rm -rf ${WORKSPACE}/helm/policy/Chart.lock
    sudo rm -rf /dockerdata-nfs/mariadb-galera/
    echo "K8s Cluster removed"
    echo "Clean up docker"
    docker image prune -f
}

function build_robot_image() {
    echo "Build docker image for robot framework"
    cd ${WORKSPACE}/csit/resources || exit
    clone_models
    if [ "${PROJECT}" == "distribution" ] || [ "${PROJECT}" == "policy-distribution" ]; then
        copy_csar_file
    fi
    echo "Build robot framework docker image"
    docker login -u docker -p docker nexus3.onap.org:10001
    docker build . --file Dockerfile \
        --build-arg CSIT_SCRIPT="$CSIT_SCRIPT" \
        --build-arg ROBOT_FILE="$ROBOT_FILE" \
        --tag "${ROBOT_DOCKER_IMAGE}" --no-cache
    echo "---------------------------------------------"
}

function start_csit() {
    build_robot_image
    if [ "${?}" -eq 0 ]; then
        echo "Importing robot image into microk8s registry"
        docker save -o policy-csit-robot.tar ${ROBOT_DOCKER_IMAGE}:latest
        sudo microk8s ctr image import policy-csit-robot.tar
        rm -rf ${WORKSPACE}/csit/resources/policy-csit-robot.tar
        rm -rf ${WORKSPACE}/csit/resources/tests/models/
        echo "---------------------------------------------"
        echo "Installing Robot framework pod for running CSIT"
        cd ${WORKSPACE}/helm
        mkdir -p ${ROBOT_LOG_DIR}
        sudo microk8s helm install csit-robot robot --set robot="$ROBOT_FILE" --set "readiness={${READINESS_CONTAINERS[*]}}" --set robotLogDir=$ROBOT_LOG_DIR
        print_robot_log
        teardown_cluster
    fi
}

function print_robot_log() {
    count_pods=0
    while [[ ${count_pods} -eq 0 ]]; do
        echo "Waiting for pods to come up..."
        sleep 5
        count_pods=$(sudo microk8s kubectl get pods --output name | wc -l)
    done
    sudo microk8s kubectl get po
    robotpod=$(sudo microk8s kubectl get po | grep policy-csit)
    podName=$(echo "$robotpod" | awk '{print $1}')
    echo "The robot tests will begin once the policy components {${READINESS_CONTAINERS[*]}} are up and running..."
    sudo microk8s kubectl wait --for=jsonpath='{.status.phase}'=Running --timeout=10m pod/"$podName"
    sudo microk8s kubectl logs -f "$podName"
    echo "Please check the logs of policy-csit-robot pod for the test execution results"
}

function clone_models() {
    GERRIT_BRANCH=$(awk -F= '$1 == "defaultbranch" { print $2 }' "${WORKSPACE}"/.gitreview)
    echo GERRIT_BRANCH="${GERRIT_BRANCH}"
    # download models examples
    git clone -b "${GERRIT_BRANCH}" --single-branch https://github.com/onap/policy-models.git "${WORKSPACE}"/csit/resources/tests/models

    # create a couple of variations of the policy definitions
    sed -e 's!Measurement_vGMUX!ADifferentValue!' \
        tests/models/models-examples/src/main/resources/policies/vCPE.policy.monitoring.input.tosca.json \
        >tests/models/models-examples/src/main/resources/policies/vCPE.policy.monitoring.input.tosca.v1_2.json

    sed -e 's!"version": "1.0.0"!"version": "2.0.0"!' \
        -e 's!"policy-version": 1!"policy-version": 2!' \
        tests/models/models-examples/src/main/resources/policies/vCPE.policy.monitoring.input.tosca.json \
        >tests/models/models-examples/src/main/resources/policies/vCPE.policy.monitoring.input.tosca.v2.json
}

function copy_csar_file() {
    zip -F ${DISTRIBUTION_CSAR}/sample_csar_with_apex_policy.csar \
        --out ${DISTRIBUTION_CSAR}/csar_temp.csar -q
    # Remake temp directory
    sudo rm -rf "${DIST_TEMP_FOLDER}"
    sudo mkdir "${DIST_TEMP_FOLDER}"
    sudo cp ${DISTRIBUTION_CSAR}/csar_temp.csar ${DISTRIBUTION_CSAR}/temp.csar
    sudo mv ${DISTRIBUTION_CSAR}/temp.csar ${DIST_TEMP_FOLDER}/sample_csar_with_apex_policy.csar
}

function get_robot_file() {
    case $PROJECT in

    clamp | policy-clamp)
        export ROBOT_FILE=$POLICY_CLAMP_ROBOT
        export READINESS_CONTAINERS=($POLICY_CLAMP_CONTAINER)
        ;;

    api | policy-api)
        export ROBOT_FILE=$POLICY_API_ROBOT
        export READINESS_CONTAINERS=($POLICY_API_CONTAINER)
        ;;

    pap | policy-pap)
        export ROBOT_FILE=$POLICY_PAP_ROBOT
        export READINESS_CONTAINERS=($POLICY_APEX_CONTAINER,$POLICY_PAP_CONTAINER,$POLICY_API_CONTAINER,$POLICY_DROOLS_CONTAINER,
            $POLICY_XACML_CONTAINER)
        ;;

    apex-pdp | policy-apex-pdp)
        export ROBOT_FILE=$POLICY_APEX_PDP_ROBOT
        export READINESS_CONTAINERS=($POLICY_APEX_CONTAINER,$POLICY_API_CONTAINER,$POLICY_PAP_CONTAINER)
        ;;

    xacml-pdp | policy-xacml-pdp)
        export ROBOT_FILE=($POLICY_XACML_PDP_ROBOT)
        export READINESS_CONTAINERS=($POLICY_API_CONTAINER,$POLICY_PAP_CONTAINER,$POLICY_XACML_CONTAINER)
        ;;

    drools-pdp | policy-drools-pdp)
        export ROBOT_FILE=($POLICY_DROOLS_PDP_ROBOT)
        export READINESS_CONTAINERS=($POLICY_DROOLS_CONTAINER)
        ;;

    distribution | policy-distribution)
        export ROBOT_FILE=($POLICY_DISTRIBUTION_ROBOT)
        export READINESS_CONTAINERS=($POLICY_APEX_CONTAINER,$POLICY_API_CONTAINER,$POLICY_PAP_CONTAINER,
            $POLICY_DISTRIBUTION_CONTAINER)
        ;;

    *)
        echo "unknown project supplied"
        ;;
    esac

}

function set_charts() {
    case $PROJECT in

    clamp | policy-clamp)
        export SET_VALUES="--set $POLICY_CLAMP_CONTAINER.enabled=true"
        ;;

    api | policy-api)
        export SET_VALUES="--set $POLICY_API_CONTAINER.enabled=true"
        ;;

    pap | policy-pap)
        export SET_VALUES="--set $POLICY_APEX_CONTAINER.enabled=true --set $POLICY_PAP_CONTAINER.enabled=true --set $POLICY_API_CONTAINER.enabled=true 
    --set $POLICY_DROOLS_CONTAINER.enabled=true --set $POLICY_XACML_CONTAINER.enabled=true"
        ;;

    apex-pdp | policy-apex-pdp)
        export SET_VALUES="--set $POLICY_APEX_CONTAINER.enabled=true --set $POLICY_PAP_CONTAINER.enabled=true --set $POLICY_API_CONTAINER.enabled=true"
        ;;

    xacml-pdp | policy-xacml-pdp)
        export SET_VALUES="--set $POLICY_PAP_CONTAINER.enabled=true --set $POLICY_API_CONTAINER.enabled=true --set $POLICY_XACML_CONTAINER.enabled=true"
        ;;

    drools-pdp | policy-drools-pdp)
        export SET_VALUES="--set $POLICY_DROOLS_CONTAINER.enabled=true"
        ;;

    distribution | policy-distribution)
        export SET_VALUES="--set $POLICY_APEX_CONTAINER.enabled=true --set $POLICY_PAP_CONTAINER.enabled=true --set $POLICY_API_CONTAINER.enabled=true 
    --set $POLICY_DISTRIBUTION_CONTAINER.enabled=true"
        ;;

    *)
        echo "all charts to be deployed"
        ;;
    esac

}

OPERATION="$1"
PROJECT="$2"

if [ $OPERATION == "install" ]; then
    spin_microk8s_cluster
    if [ "${?}" -eq 0 ]; then
        set_charts
        echo "Installing policy helm charts in the default namespace"
        cd ${WORKSPACE}/helm || exit
        sudo microk8s helm dependency build policy
        sudo microk8s helm install csit-policy policy ${SET_VALUES}
        sudo microk8s helm install prometheus prometheus
        echo "Policy chart installation completed"
        echo "-------------------------------------------"
    fi

    if [ "$PROJECT" ]; then
        export $PROJECT
        export ROBOT_LOG_DIR=${WORKSPACE}/csit/archives/${PROJECT}
        get_robot_file
        echo "CSIT will be invoked from $ROBOT_FILE"
        echo "Readiness containers: ${READINESS_CONTAINERS[*]}"
        echo "-------------------------------------------"
        start_csit
    else
        echo "No project supplied for running CSIT"
    fi

elif [ $OPERATION == "uninstall" ]; then
    teardown_cluster
else
    echo "Invalid arguments provided. Usage: $0 [option..] {install {project} | uninstall}"
fi
