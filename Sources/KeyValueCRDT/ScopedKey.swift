import Foundation

/// A scope/key pair.
public struct ScopedKey: Hashable, ExpressibleByStringLiteral {
  public init(scope: String = "", key: String) {
    self.scope = scope
    self.key = key
  }

  public init(stringLiteral: String) {
    self.scope = ""
    self.key = stringLiteral
  }

  /// The scope that contains the key.
  public let scope: String

  /// The key.
  public let key: String
}

internal extension ScopedKey {
  init(_ entryRecord: EntryRecord) {
    self.scope = entryRecord.scope
    self.key = entryRecord.key
  }
}
