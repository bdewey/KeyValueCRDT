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
import GRDB

internal struct TombstoneRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "tombstone"
  var scope: String
  var key: String
  var authorId: UUID
  var usn: Int
  var deletingAuthorId: UUID
  var deletingUsn: Int

  enum Column {
    static let scope = GRDB.Column(CodingKeys.scope)
    static let key = GRDB.Column(CodingKeys.key)
    static let authorId = GRDB.Column(CodingKeys.authorId)
    static let usn = GRDB.Column(CodingKeys.usn)
    static let deletingAuthorId = GRDB.Column(CodingKeys.deletingAuthorId)
    static let deletingUsn = GRDB.Column(CodingKeys.deletingUsn)
  }
}

extension TombstoneRecord {
  init(_ entryRecord: EntryRecord, deletingAuthorId: UUID, deletingUsn: Int) {
    self.scope = entryRecord.scope
    self.key = entryRecord.key
    self.authorId = entryRecord.authorId
    self.usn = entryRecord.usn
    self.deletingAuthorId = deletingAuthorId
    self.deletingUsn = deletingUsn
  }
}
