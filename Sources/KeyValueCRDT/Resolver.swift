// Copyright (c) 2018-2021  Brian Dewey. Covered by the Apache 2.0 license.

import Foundation

/// A `Resolver` is responsible for picking a single value from an array of possible values.
public protocol Resolver {
  /// Given an array of versions, returns the "winning" value according to some algorithm.
  func resolveVersions(_ versions: [Version]) -> Value?
}

/// Resolves conflicting versions by picking the one with the highest timestamp.
public struct LastWriterWinsResolver: Resolver {
  public func resolveVersions(_ versions: [Version]) -> Value? {
    versions.max(by: { $0.timestamp < $1.timestamp })?.value
  }
}

extension Resolver where Self == LastWriterWinsResolver {
  public static var lastWriterWins: LastWriterWinsResolver { LastWriterWinsResolver() }
}

extension Array where Element == Version {
  /// Picks a single value from the version array using `resolver`.
  public func resolved(with resolver: Resolver) -> Value? {
    resolver.resolveVersions(self)
  }
}
