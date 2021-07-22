import Foundation

/// Information about the number of entries in the database.
public struct Statistics: Equatable {
  public init(entryCount: Int, authorCount: Int, tombstoneCount: Int) {
    self.entryCount = entryCount
    self.authorCount = authorCount
    self.tombstoneCount = tombstoneCount
  }

  /// How many entries are in the database.
  let entryCount: Int

  /// How many authors are in the database.
  let authorCount: Int

  /// How many tombstones are in the database.
  let tombstoneCount: Int
}
