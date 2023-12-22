//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

import Foundation

public enum KeyValueCRDTError: Error, Sendable {
  /// The CRDT database has a new version schema that this version does not understand.
  case databaseSchemaTooNew

  /// The CRDT database has application data stored in a new version format that this version does not understand.
  case applicationDataTooNew

  /// The CRDT database has application data that comes from another application.
  case incompatibleApplications

  /// There are conflicting versions of a value in a code path that asserted there should be only one.
  case versionConflict

  /// Attempted to write invalid JSON as a JSON string.
  case invalidJSON

  /// Something's wrong with the author table.
  case authorTableInconsistency

  case mergeSourceIncompatible
  case mergeSourceRequiresUpgrade
}
