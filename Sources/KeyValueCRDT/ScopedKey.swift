import Foundation

/// A scope/key pair.
public struct ScopedKey: Hashable {
  public init(scope: String = "", key: String) {
    self.scope = scope
    self.key = key
  }

  /// The scope that contains the key.
  public let scope: String

  /// The key.
  public let key: String
}
