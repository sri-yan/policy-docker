#!/bin/bash
#
# ===========LICENSE_START====================================================
#  Copyright (C) 2019-2021 AT&T Intellectual Property. All rights reserved.
#  Modifications Copyright 2021-2024 Nordix Foundation.
# ============================================================================
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
# ============LICENSE_END=====================================================
#

source "${SCRIPTS}"/node-templates.sh

source "${WORKSPACE}"/compose/start-compose.sh drools-applications

sleep 10
unset http_proxy https_proxy

export SUITES="drools-applications-test.robot"
export KAFKA_IP="localhost:${KAFKA_PORT}"

# wait for the app to start up
"${SCRIPTS}"/wait_for_rest.sh localhost ${PAP_PORT}
"${SCRIPTS}"/wait_for_rest.sh localhost ${DROOLS_APPS_PORT}
"${SCRIPTS}"/wait_for_rest.sh localhost ${DROOLS_APPS_TELEMETRY_PORT}

# give enough time for the controllers to come up
sleep 15

ROBOT_VARIABLES="-v DATA:${DATA} -v DROOLS_IP:localhost:${DROOLS_APPS_PORT}
-v DROOLS_IP_2:localhost:${DROOLS_APPS_TELEMETRY_PORT} -v POLICY_API_IP:localhost:${API_PORT}
-v POLICY_PAP_IP:localhost:${PAP_PORT} -v KAFKA_IP:${KAFKA_IP}"
