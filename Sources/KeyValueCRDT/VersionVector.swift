import Foundation

struct VersionVector<Key, Value> where Key: Hashable, Value: Comparable {
  /// Maps an author ID to the largest update sequence number (USN) for that author.
  fileprivate var versions: [Key: Value] = [:]

  /// True if the receiver dominates the other version vector.
  ///
  /// A version vector `A` dominates a version vector `B` if, for every version in `B`, the corresponding version in `A` is greater than or equal to the version from `B`.
  ///
  /// The implication is a version vector dominates itself.
  func dominates(_ other: VersionVector) -> Bool {
    for (author, usn) in other.versions {
      guard let localUSN = versions[author] else {
        return false
      }
      if localUSN < usn {
        return false
      }
    }
    return true
  }

  /// Computes the "need list" of items we need to match another version vector.
  func needList(toMatch other: VersionVector<Key, Value>) -> [(key: Key, value: Value?)] {
    var needs: [(key: Key, value: Value?)] = []
    for (key, value) in other {
      guard let localValue = versions[key] else {
        needs.append((key: key, value: nil))
        continue
      }
      if value > localValue {
        needs.append((key: key, value: localValue))
      }
    }
    return needs
  }

  mutating func formUnion(_ other: Self) {
    for (key, value) in other {
      if let localValue = versions[key], localValue >= value {
        // Nothing -- we already have a better value
      } else {
        versions[key] = value
      }
    }
  }
}

// MARK: - Collection

extension VersionVector: Collection {
  typealias Index = Dictionary<Key, Value>.Index

  var startIndex: Index { versions.startIndex }
  var endIndex: Index { versions.endIndex }
  func index(after i: Index) -> Index {
    versions.index(after: i)
  }

  subscript(position: Index) -> (key: Key, value: Value) {
    versions[position]
  }

  subscript(key: Key) -> Value? { versions[key] }
}

// MARK: - Author

/// Used to identify an author in a ``VersionVector``
///
/// When looking up authors in a version vector, the `id` is the *strong* identifier -- if the `id` matches, the authors are the same, even if the name is different.
struct AuthorVersionIdentifier: Hashable {
  let id: UUID
  let name: String

  init(_ record: AuthorRecord) {
    self.id = record.id
    self.name = record.name
  }

  static func == (lhs: AuthorVersionIdentifier, rhs: AuthorVersionIdentifier) -> Bool {
    return lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension VersionVector where Key == AuthorVersionIdentifier, Value == Int {
  /// Construct a VersionVector with the contents of the Author table.
  /// - precondition: Each `id` in `records` must be unique.
  init(_ records: [AuthorRecord]) {
    self.versions = Dictionary(uniqueKeysWithValues: records.map({ (key: AuthorVersionIdentifier($0), value: $0.usn) }))
  }
}
