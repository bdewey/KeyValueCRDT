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

public extension Resolver where Self == LastWriterWinsResolver {
  static var lastWriterWins: LastWriterWinsResolver { LastWriterWinsResolver() }
}

public extension Array where Element == Version {
  /// Picks a single value from the version array using `resolver`.
  func resolved(with resolver: Resolver) -> Value? {
    resolver.resolveVersions(self)
  }
}
