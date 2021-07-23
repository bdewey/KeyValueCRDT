import Foundation

/// Information about the number of entries in the database.
public struct Statistics: Equatable {
  public init(entryCount: Int, authorCount: Int, tombstoneCount: Int) {
    self.entryCount = entryCount
    self.authorCount = authorCount
    self.tombstoneCount = tombstoneCount
  }

  /// How many entries are in the database.
  public let entryCount: Int

  /// How many authors are in the database.
  public let authorCount: Int

  /// How many tombstones are in the database.
  public let tombstoneCount: Int
}
