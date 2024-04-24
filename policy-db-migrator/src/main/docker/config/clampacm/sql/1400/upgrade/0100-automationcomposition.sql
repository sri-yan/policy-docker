/*
 * ============LICENSE_START=======================================================
 *  Copyright (C) 2024 Nordix Foundation
 *  ================================================================================
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  SPDX-License-Identifier: Apache-2.0
 *  ============LICENSE_END=========================================================
 */

CREATE TABLE clampacm.automationcomposition (instanceId VARCHAR(255) NOT NULL, compositionId VARCHAR(255) NULL, compositionTargetId VARCHAR(255) NULL, deployState TINYINT DEFAULT NULL NULL, `description` VARCHAR(255) NULL, lockState TINYINT DEFAULT NULL NULL, name VARCHAR(255) NULL, restarting BIT NULL, stateChangeResult TINYINT DEFAULT NULL NULL, version VARCHAR(255) NULL, CONSTRAINT PK_AUTOMATIONCOMPOSITION PRIMARY KEY (instanceId));