import Foundation

/// A read-only snapshot of a ``Value`` at a specific point in time.
public struct Version: Equatable {
  /// The ID of the author of this version.
  public let authorID: UUID

  /// When this version was created.
  public let timestamp: Date

  /// The value associated with this version.
  public let value: Value

  /// Construct a Version from an EntryRecord
  init(_ record: EntryRecord) {
    self.authorID = record.authorId
    self.timestamp = record.modifiedTimestamp
    self.value = record.value
  }
}

extension Array where Element == Version {
  public var text: String? {
    get throws {
      if isEmpty {
        return nil
      } else if count > 1 {
        throw KeyValueCRDTError.versionConflict
      }
      return self[0].value.text
    }
  }
}
