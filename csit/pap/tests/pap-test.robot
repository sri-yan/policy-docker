*** Settings ***
Library    Collections
Library    RequestsLibrary
Library    OperatingSystem
Library    json
Resource    ${CURDIR}/../../common-library.robot

*** Keywords ***
GetReq
    [Arguments]  ${url}
    ${auth}=  PolicyAdminAuth
    ${resp}=  PerformGetRequest  ${POLICY_PAP_IP}  ${url}  200  null  ${auth}
    [return]  ${resp}

*** Test Cases ***
LoadPolicy
    [Documentation]  Create a policy named 'onap.restart.tca' and version '1.0.0' using specific api
    ${postjson}=  Get file  ${DATA}/vCPE.policy.monitoring.input.tosca.json
    CreatePolicy  /policy/api/v1/policytypes/onap.policies.monitoring.tcagen2/versions/1.0.0/policies  200  ${postjson}  onap.restart.tca  1.0.0

Healthcheck
    [Documentation]  Verify policy pap health check
    ${resp}=  GetReq  /policy/pap/v1/healthcheck
    Should Be Equal As Strings  ${resp.json()['code']}  200

Consolidated Healthcheck
    [Documentation]  Verify policy consolidated health check
    ${resp}=  GetReq  /policy/pap/v1/components/healthcheck
    Should Be Equal As Strings  ${resp.json()['healthy']}  True

Metrics
    [Documentation]  Verify policy pap is exporting prometheus metrics
    ${auth}=  PolicyAdminAuth
    ${resp}=  GetMetrics  ${POLICY_PAP_IP}  ${auth}
    Should Contain  ${resp.text}  http_server_requests_seconds_count{exception="None",method="GET",outcome="SUCCESS",status="200",uri="/policy/pap/v1/healthcheck",} 1.0
    Should Contain  ${resp.text}  http_server_requests_seconds_count{exception="None",method="GET",outcome="SUCCESS",status="200",uri="/policy/pap/v1/components/healthcheck",} 1.0
    Should Contain  ${resp.text}  spring_data_repository_invocations_seconds_count{exception="None",method="save",repository="PdpGroupRepository",state="SUCCESS",} 1.0
    Should Contain  ${resp.text}  spring_data_repository_invocations_seconds_count{exception="None",method="findByKeyName",repository="PdpGroupRepository",state="SUCCESS",} 1.0
    Should Contain  ${resp.text}  spring_data_repository_invocations_seconds_count{exception="None",method="findAll",repository="PdpGroupRepository",state="SUCCESS",} 1.0
    Should Contain  ${resp.text}  spring_data_repository_invocations_seconds_count{exception="None",method="findAll",repository="PolicyStatusRepository",state="SUCCESS",} 1.0

Statistics
    [Documentation]  Verify policy pap statistics
    ${resp}=  GetReq  /policy/pap/v1/statistics
    Should Be Equal As Strings  ${resp.json()['code']}  200

AddPdpGroup
    [Documentation]  Add a new PdpGroup named 'testGroup' in the policy database
    ${postjson}=  Get file  ${CURDIR}/data/create.group.request.json
    ${auth}=  PolicyAdminAuth
    PerformPostRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/groups/batch  200  ${postjson}  null  ${auth}

QueryPdpGroupsBeforeActivation
    [Documentation]  Verify PdpGroups before activation
    QueryPdpGroups  2  defaultGroup  ACTIVE  0  testGroup  PASSIVE  0

ActivatePdpGroup
    [Documentation]  Change the state of PdpGroup named 'testGroup' to ACTIVE
    ${auth}=  PolicyAdminAuth
    PerformPutRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/groups/testGroup  200  state=ACTIVE  ${auth}

QueryPdpGroupsAfterActivation
    [Documentation]  Verify PdpGroups after activation
    QueryPdpGroups  2  defaultGroup  ACTIVE  0  testGroup  ACTIVE  0

DeployPdpGroups
    [Documentation]  Deploy policies in PdpGroups
    ${postjson}=  Get file  ${CURDIR}/data/deploy.group.request.json
    ${auth}=  PolicyAdminAuth
    PerformPostRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/deployments/batch  202  ${postjson}  null  ${auth}

QueryPdpGroupsAfterDeploy
    [Documentation]  Verify PdpGroups after undeploy
    QueryPdpGroups  2  defaultGroup  ACTIVE  0  testGroup  ACTIVE  1

QueryPolicyAuditAfterDeploy
    [Documentation]  Verify policy audit record after deploy
    QueryPolicyAudit  /policy/pap/v1/policies/audit  200  testGroup  pdpTypeA  onap.restart.tca  DEPLOYMENT

UndeployPolicy
    [Documentation]  Undeploy a policy named 'onap.restart.tca' from PdpGroups
    ${auth}=  PolicyAdminAuth
    PerformDeleteRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/policies/onap.restart.tca  202  ${auth}

QueryPdpGroupsAfterUndeploy
    [Documentation]  Verify PdpGroups after undeploy
    QueryPdpGroups  2  defaultGroup  ACTIVE  0  testGroup  ACTIVE  0

QueryPolicyAuditAfterUnDeploy
    [Documentation]  Verify policy audit record after undeploy
    QueryPolicyAudit  /policy/pap/v1/policies/audit  200  testGroup  pdpTypeA  onap.restart.tca  UNDEPLOYMENT

DeactivatePdpGroup
    [Documentation]  Change the state of PdpGroup named 'testGroup' to PASSIVE
    ${auth}=  PolicyAdminAuth
    PerformPutRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/groups/testGroup  200  state=PASSIVE  ${auth}

DeletePdpGroups
    [Documentation]  Delete the PdpGroup named 'testGroup' from policy database
    ${auth}=  PolicyAdminAuth
    PerformDeleteRequest  ${POLICY_PAP_IP}  /policy/pap/v1/pdps/groups/testGroup  200  ${auth}

QueryPdpGroupsAfterDelete
    [Documentation]    Verify PdpGroups after delete
    QueryPdpGroups  1  defaultGroup  ACTIVE  0  null  null  null
