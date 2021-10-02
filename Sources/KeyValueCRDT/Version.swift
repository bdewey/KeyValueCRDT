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

/// A read-only snapshot of a ``Value`` at a specific point in time.
public struct Version: Equatable {
  /// The ID of the author of this version.
  public let authorID: UUID

  /// When this version was created.
  public let timestamp: Date

  /// The value associated with this version.
  public let value: Value

  internal init(authorID: UUID, timestamp: Date, value: Value) {
    self.authorID = authorID
    self.timestamp = timestamp
    self.value = value
  }

  /// Construct a Version from an EntryRecord
  internal init(_ record: EntryRecord) {
    self.authorID = record.authorId
    self.timestamp = record.timestamp
    self.value = record.value
  }
}

public extension Array where Element == Version {
  var text: String? {
    get throws {
      if isEmpty {
        return nil
      } else if count > 1 {
        throw KeyValueCRDTError.versionConflict
      }
      return self[0].value.text
    }
  }

  var json: String? {
    get throws {
      if isEmpty {
        return nil
      } else if count > 1 {
        throw KeyValueCRDTError.versionConflict
      }
      return self[0].value.json
    }
  }

  var blob: Data? {
    get throws {
      if isEmpty {
        return nil
      } else if count > 1 {
        throw KeyValueCRDTError.versionConflict
      }
      return self[0].value.blob
    }
  }

  var isDeleted: Bool {
    get throws {
      if isEmpty {
        return false // "deleted" is different from "doesn't exist"
      } else if count > 1 {
        throw KeyValueCRDTError.versionConflict
      }
      return self[0].value == .null
    }
  }
}
