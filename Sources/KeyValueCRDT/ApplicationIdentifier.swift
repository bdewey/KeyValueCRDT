// 

import Foundation
import GRDB

/// Stores information about the application that created the key-value store.
public struct ApplicationIdentifier: Codable, Comparable {
  public init(id: String, majorVersion: Int, minorVersion: Int, applicationDescription: String? = nil) {
    self.id = id
    self.majorVersion = majorVersion
    self.minorVersion = minorVersion
    self.applicationDescription = applicationDescription
  }

  /// Application identifier, in reverse-DNS. Primary key of this table.
  var id: String

  /// Major version number of the file format.
  var majorVersion: Int

  /// Minor version number of the file format.
  var minorVersion: Int

  /// Optional application description.
  var applicationDescription: String?

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

