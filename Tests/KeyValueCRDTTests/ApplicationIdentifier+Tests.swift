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
import KeyValueCRDT

internal extension ApplicationIdentifier {
  static let tests = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 1, minorVersion: 0)
  static let testsV2 = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 2, minorVersion: 0)
  static let testsV21 = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 2, minorVersion: 1)
  static let differentApplication = ApplicationIdentifier(id: "org.brians-brain.dreaming", majorVersion: 13, minorVersion: 0)
}
