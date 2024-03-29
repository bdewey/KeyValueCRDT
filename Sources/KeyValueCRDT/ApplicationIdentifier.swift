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

/// Stores information about the application that created the key-value store.
public struct ApplicationIdentifier: Codable, Comparable, Sendable {
  public init(id: String, majorVersion: Int, minorVersion: Int, applicationDescription: String? = nil) {
    self.id = id
    self.majorVersion = majorVersion
    self.minorVersion = minorVersion
    self.applicationDescription = applicationDescription
  }

  /// Application identifier, in reverse-DNS. Primary key of this table.
  public var id: String

  /// Major version number of the file format.
  public var majorVersion: Int

  /// Minor version number of the file format.
  public var minorVersion: Int

  /// Optional application description.
  public var applicationDescription: String?

  public static func < (lhs: ApplicationIdentifier, rhs: ApplicationIdentifier) -> Bool {
    (lhs.id, lhs.majorVersion, lhs.minorVersion) < (rhs.id, rhs.majorVersion, rhs.minorVersion)
  }

  public enum ComparisonResult {
    case compatible
    case incompatible
    case requiresUpgrade
    case currentVersionIsTooOld
  }

  public func compare(to other: ApplicationIdentifier?) -> ComparisonResult {
    guard let other = other else {
      return .requiresUpgrade
    }
    if id != other.id {
      return .incompatible
    }
    if other.majorVersion > majorVersion {
      return .currentVersionIsTooOld
    }
    if (majorVersion, minorVersion) > (other.majorVersion, other.minorVersion) {
      return .requiresUpgrade
    } else {
      return .compatible
    }
  }
}

// TODO: Is there a way to keep the "this is a database record" private without creating another type?
extension ApplicationIdentifier: FetchableRecord, PersistableRecord {
  public static let databaseTableName = "applicationIdentifier"
}

internal extension ApplicationDataUpgrader {
  func upgrade(database: KeyValueDatabase) throws {
    let comparisonResult = expectedApplicationIdentifier.compare(to: try database.applicationIdentifier)
    switch comparisonResult {
    case .compatible:
      // nothing to do
      break
    case .incompatible:
      throw KeyValueCRDTError.incompatibleApplications
    case .requiresUpgrade:
      try upgradeApplicationData(in: database)
      try database.setApplicationIdentifier(expectedApplicationIdentifier)
    case .currentVersionIsTooOld:
      throw KeyValueCRDTError.applicationDataTooNew
    }
  }
}
