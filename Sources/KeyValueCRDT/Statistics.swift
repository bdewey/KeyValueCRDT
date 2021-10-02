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

/// Information about the number of entries in the database.
public struct Statistics: Equatable {
  public init(entryCount: Int, authorCount: Int, tombstoneCount: Int, authorTableIsConsistent: Bool) {
    self.entryCount = entryCount
    self.authorCount = authorCount
    self.tombstoneCount = tombstoneCount
    self.authorTableIsConsistent = authorTableIsConsistent
  }

  /// How many entries are in the database.
  public let entryCount: Int

  /// How many authors are in the database.
  public let authorCount: Int

  /// How many tombstones are in the database.
  public let tombstoneCount: Int

  /// `true` if the author table is consistent with entries. If this value is `false`, you should erase version history in this database.
  public let authorTableIsConsistent: Bool
}
