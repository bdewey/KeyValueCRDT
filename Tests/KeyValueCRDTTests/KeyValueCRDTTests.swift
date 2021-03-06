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

import Combine
import Foundation
import GRDB
import KeyValueCRDT
import XCTest

final class KeyValueCRDTTests: XCTestCase {
  func testSimpleStorage() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: "test")
    try crdt.writeText("Hello, world!", to: "key")
    let result = try crdt.read(key: "key")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.value, .text("Hello, world!"))
  }

  func testMultipleWritesFromOneAuthorMakeOneVersion() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: "test")
    try crdt.writeText("Hello, world!", to: "key")
    try crdt.writeText("Goodbye, world!", to: "key")
    let result = try crdt.read(key: "key")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.value, .text("Goodbye, world!"))
    XCTAssertEqual(try crdt.read(key: "key").text, "Goodbye, world!")
    XCTAssertNil(try crdt.read(key: "key").json)
  }

  func testDelete() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: "test")
    try crdt.writeText("Hello, world!", to: "key")
    try crdt.delete(key: "key")
    let result = try crdt.read(key: "key")
    XCTAssert(try result.isDeleted)
  }

  func testMerge() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)

    try alice.writeText("alice", to: TestKey.alice)
    try alice.writeText("alice shared", to: TestKey.shared)

    try bob.writeText("bob", to: TestKey.bob)
    try bob.writeText("bob shared", to: TestKey.shared)

    // Neither copy dominates the other -- they each have changes the other needs to see
    XCTAssertFalse(try alice.dominates(other: bob))
    XCTAssertFalse(try bob.dominates(other: alice))
    try alice.merge(source: bob)

    // Post-merge, Alice dominates bob but not vice-versa
    XCTAssertTrue(try alice.dominates(other: bob))
    XCTAssertFalse(try bob.dominates(other: alice))
    XCTAssertEqual(try alice.read(key: TestKey.alice).text, "alice")
    XCTAssertEqual(try alice.read(key: TestKey.bob).text, "bob")
    XCTAssertEqual(try alice.read(key: TestKey.shared).count, 2)

    let expectedKeys = Set([
      ScopedKey(key: TestKey.alice),
      ScopedKey(key: TestKey.bob),
      ScopedKey(key: TestKey.shared),
    ])
    XCTAssertEqual(Set(try alice.keys), expectedKeys)
  }

  func testMergeDoesNotAllowTimeTravel() throws {
    let original = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try original.writeText("Version 1", to: "test")
    let modified = try KeyValueDatabase(databaseWriter: try original.makeMemoryDatabaseQueue(), authorDescription: .alice)
    try modified.writeText("Version 2", to: "test")

    // Changing `modified` doesn't change `original`
    XCTAssertEqual(try original.read(key: "test").text, "Version 1")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")

    // Merging `original` into `modified` should be a no-op, since `modified` subsumes `original`
    try modified.merge(source: original)
    XCTAssertEqual(try original.read(key: "test").text, "Version 1")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")
  }

  func testMergeWillMoveForwardInTime() throws {
    let original = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try original.writeText("Version 1", to: "test")
    let modified = try KeyValueDatabase(databaseWriter: try original.makeMemoryDatabaseQueue(), authorDescription: .alice)
    try modified.writeText("Version 2", to: "test")

    // Changing `modified` doesn't change `original`
    XCTAssertEqual(try original.read(key: "test").text, "Version 1")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")

    try original.merge(source: modified)
    XCTAssertEqual(try original.read(key: "test").text, "Version 2")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")
  }

  func testMergeUpdatesAuthorRecord() throws {
    let original = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try original.writeText("Version 1", to: "test")
    let modified = try KeyValueDatabase(databaseWriter: try original.makeMemoryDatabaseQueue(), authorDescription: .alice)
    for i in 2 ... 100 {
      try modified.writeText("Version \(i)", to: "test")
    }

    // Changing `modified` doesn't change `original`
    XCTAssertEqual(try original.read(key: "test").text, "Version 1")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 100")

    // This will bring all of the changes from "modified" back to "original"
    try original.merge(source: modified)
    XCTAssertEqual(try original.read(key: "test").text, "Version 100")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 100")

    // Here's the catch. If we forget to update the author record inside `original`, then the writes we make here
    // will look "old" even though we're up-to-date.
    try original.writeText("Modified after merge", to: "test")
    XCTAssertEqual(try original.read(key: "test").text, "Modified after merge")
    try modified.merge(source: original)
    XCTAssertEqual(try modified.read(key: "test").text, "Modified after merge")
  }

  func testCreateDeleteUpdates() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    try alice.writeText("v1", to: "test")
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").text, "v1")
    try bob.delete(key: "test")
    XCTAssert(try bob.read(key: "test").isDeleted)
    try alice.merge(source: bob)
    XCTAssert(try alice.read(key: "test").isDeleted)
  }

  func testCreateDeleteConflict() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    try alice.writeText("v1", to: "test")
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").text, "v1")
    try bob.delete(key: "test")
    XCTAssert(try bob.read(key: "test").isDeleted)
    try alice.writeText("v2", to: "test")

    // At this point, Bob has deleted the key and Alice has changed it: Conflict.
    // We need to see both versions when we read.
    try alice.merge(source: bob)
    XCTAssertEqual(try alice.read(key: "test").count, 2)

    // And we should wind up with the same state when we merge the other way
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").count, 2)

    XCTAssertEqual(try alice.statistics, try bob.statistics)
  }

  func testWritesResolveConflicts() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    let charlie = try KeyValueDatabase(fileURL: nil, authorDescription: .charlie)
    try alice.writeText("alice", to: "test")
    try bob.writeText("bob", to: "test")
    try charlie.merge(source: alice)
    try charlie.merge(source: bob)
    XCTAssertEqual(try charlie.read(key: "test").count, 2)
    try charlie.writeText("resolved", to: "test")
    XCTAssertEqual(try charlie.read(key: "test").text, "resolved")
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").count, 2)
    try bob.merge(source: charlie)
    XCTAssertEqual(try bob.read(key: "test").text, "resolved")
  }

  func testDeletedKeysDontShowUp() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    try alice.writeText("v1", to: "test")
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").text, "v1")
    try bob.delete(key: "test")
    XCTAssert(try bob.read(key: "test").isDeleted)
    try alice.writeText("v2", to: "test")

    // At this point, Bob has deleted the key and Alice has changed it: Conflict.
    // We need to see both versions when we read.
    try alice.merge(source: bob)
    XCTAssertEqual(try alice.read(key: "test").count, 2)

    // There's 1 key that has two values
    XCTAssertEqual(try alice.keys.count, 1)
    XCTAssertEqual(try alice.statistics.entryCount, 2)
    try alice.delete(key: "test")
    XCTAssertEqual(try alice.keys.count, 0)
    XCTAssertEqual(try alice.statistics.entryCount, 1)
  }

  func testKeyScopingWorks() throws {
    let database = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try database.writeText("scope 1", to: "test", scope: "scope 1")
    try database.writeText("scope 2", to: "test", scope: "scope 2")
    XCTAssertEqual(try database.keys.count, 2)
    XCTAssertEqual("scope 1", try database.read(key: "test", scope: "scope 1").text)
    XCTAssertEqual("scope 2", try database.read(key: "test", scope: "scope 2").text)

    try database.writeText("bonus", to: "bonus")
    XCTAssertEqual(try database.keys.count, 3)
    XCTAssertEqual(
      Set([ScopedKey(scope: "scope 1", key: "test"), ScopedKey(scope: "scope 2", key: "test")]),
      Set(try database.keys(key: "test"))
    )
    XCTAssertEqual(
      Set([ScopedKey(scope: "scope 1", key: "test")]),
      Set(try database.keys(scope: "scope 1"))
    )
  }

  func testSearch() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try crdt.writeText("Four score and seven years ago", to: "gettysburg")
    try crdt.writeText("Shall I compare thee to a summer's day?", to: "shakespeare")
    XCTAssertEqual([ScopedKey(key: "shakespeare")], try crdt.searchText(for: "summer"))
  }

  func testStoreJSON() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try crdt.writeJson(#"{"a": 21}"#, to: "json")
    XCTAssertEqual(#"{"a": 21}"#, try crdt.read(key: "json").json)
  }

  func testInvalidJSONThrows() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    XCTAssertThrowsError(try crdt.writeJson("This isn't JSON", to: "not json"), "This is a mistake") { error in
      XCTAssert(error is KeyValueCRDTError)
      if let error = error as? KeyValueCRDTError {
        XCTAssertEqual(KeyValueCRDTError.invalidJSON, error)
      }
    }
  }

  func testStoreBlob() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    let data = "Hello, world!".data(using: .utf8)!
    try crdt.writeBlob(data, to: "test")
    XCTAssertEqual(data, try crdt.read(key: "test").blob)
  }

  func testBulkRead() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)

    try alice.writeText("alice", to: TestKey.alice)
    try alice.writeText("alice shared", to: TestKey.shared)

    try bob.writeText("bob", to: TestKey.bob)
    try bob.writeText("bob shared", to: TestKey.shared)

    try alice.merge(source: bob)
    let results = try alice.bulkRead()
    XCTAssertEqual(try results[ScopedKey(key: TestKey.alice)]?.text, "alice")
    XCTAssertEqual(try results[ScopedKey(key: TestKey.bob)]?.text, "bob")
    XCTAssertEqual(results[ScopedKey(key: TestKey.shared)]?.count, 2)

    let filteredResults = try alice.bulkRead(key: TestKey.alice)
    XCTAssertEqual(filteredResults.count, 1)
    XCTAssertEqual(try filteredResults[ScopedKey(key: TestKey.alice)]?.text, "alice")
  }

  func testBulkWrite() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let values: [ScopedKey: Value] = [
      ScopedKey(key: TestKey.alice): .text("Alice"),
      ScopedKey(key: TestKey.shared): .json("42"),
    ]
    try crdt.bulkWrite(values)
    XCTAssertEqual(try crdt.statistics.entryCount, 2)
    XCTAssertEqual(try crdt.read(key: TestKey.alice).text, "Alice")
    XCTAssertEqual(try crdt.read(key: TestKey.shared).json, "42")
  }

  func testBackup() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let values: [ScopedKey: Value] = [
      ScopedKey(key: TestKey.alice): .text("Alice"),
      ScopedKey(key: TestKey.shared): .json("42"),
    ]
    try crdt.bulkWrite(values)
    let backup = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    try crdt.backup(to: backup)
    XCTAssertTrue(try crdt.dominates(other: backup))
    XCTAssertTrue(try backup.dominates(other: crdt))
  }

  func testBackupClobbersExistingData() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let values: [ScopedKey: Value] = [
      ScopedKey(key: TestKey.alice): .text("Alice"),
      ScopedKey(key: TestKey.shared): .json("42"),
    ]
    try crdt.bulkWrite(values)
    let backup = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    try backup.writeText("Hi bob", to: TestKey.bob)
    XCTAssertFalse(try crdt.dominates(other: backup))
    XCTAssertFalse(try backup.dominates(other: crdt))
    try crdt.backup(to: backup)
    XCTAssertTrue(try crdt.dominates(other: backup))
    XCTAssertTrue(try backup.dominates(other: crdt))
    XCTAssertEqual(try backup.read(key: TestKey.shared).json, "42")
    XCTAssertEqual(try backup.read(key: TestKey.bob).count, 0)
  }

  func testBackupDoesNotUpdateDestinationAuthorRecord() throws {
    let crdt = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    XCTAssertEqual(try crdt.writeText("v1", to: "test"), 1)
    XCTAssertEqual(try crdt.writeText("v2", to: "test"), 2)
    XCTAssertEqual(try crdt.writeText("v3", to: "test"), 3)

    let copy = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try crdt.backup(to: copy)
    XCTAssertEqual(try copy.read(key: "test").text, "v3")
    XCTAssertEqual(try copy.writeText("v4", to: "test"), 1)
  }

  func testEraseVersionHistory() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)
    let charlie = try KeyValueDatabase(fileURL: nil, authorDescription: .charlie)
    try alice.writeText("alice", to: "test")
    try bob.writeText("bob", to: "test")
    try charlie.merge(source: alice)
    try charlie.merge(source: bob)
    XCTAssertEqual(try charlie.read(key: "test").count, 2)
    try charlie.writeText("resolved", to: "test")
    XCTAssertEqual(try charlie.read(key: "test").text, "resolved")
    try bob.merge(source: alice)
    XCTAssertEqual(try bob.read(key: "test").count, 2)
    try bob.merge(source: charlie)
    XCTAssertEqual(try bob.read(key: "test").text, "resolved")
    XCTAssertEqual(Statistics(entryCount: 1, authorCount: 3, tombstoneCount: 2, authorTableIsConsistent: true), try bob.statistics)
    try bob.eraseVersionHistory()
    XCTAssertEqual(Statistics(entryCount: 1, authorCount: 1, tombstoneCount: 0, authorTableIsConsistent: true), try bob.statistics)
  }

  func testEraseVersionHistoryWorksWithNewAuthor() throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("usntest.kvcrdt")
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }
    do {
      let crdt = try KeyValueDatabase(fileURL: fileURL, authorDescription: .alice)
      XCTAssertEqual(try crdt.writeText("v1", to: "test"), 1)
      XCTAssertEqual(try crdt.writeText("v2", to: "test"), 2)
    }
    do {
      let crdt = try KeyValueDatabase(fileURL: fileURL, authorDescription: .bob)
      try crdt.eraseVersionHistory()
      XCTAssertEqual(try crdt.read(key: "test").text, "v2")
    }
  }

  func testAuthorUsnResets() throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("usntest.kvcrdt")
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }
    do {
      let crdt = try KeyValueDatabase(fileURL: fileURL, authorDescription: .alice)
      XCTAssertEqual(try crdt.writeText("v1", to: "test"), 1)
      XCTAssertEqual(try crdt.writeText("v2", to: "test"), 2)
    }
    do {
      let crdt = try KeyValueDatabase(fileURL: fileURL, authorDescription: .alice)
      XCTAssertEqual(try crdt.writeText("v3", to: "test"), 1)
    }
  }

  func testMergeChangesArePublished() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)

    let bobGotValueExpectaton = expectation(description: "Bob got the updated value")

    let cancelable = bob.readPublisher(key: "test").sink { _ in } receiveValue: { values in
      if (try? values["test"]?.text) == "hello, world" {
        bobGotValueExpectaton.fulfill()
      }
    }
    defer {
      cancelable.cancel()
    }

    try alice.writeText("hello, world", to: "test")
    XCTAssertEqual(try bob.merge(source: alice), ["test"])
    waitForExpectations(timeout: 3)
  }

  func testComparePublishers() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    try alice.bulkWrite(["key1": "value 1", "key2": "value 2"])

    // `readPublisher` is "hot" -- it publishes the current value at the time you subscribe.
    // `readPublisher` also republishes *everything* when *anything that matches* changes.
    // This is useful to get a consistent view of the data in the database.
    let readPublisherExpectation = expectation(description: "read publisher")
    let readPublisherSubscription = alice.readPublisher(keyPrefix: "key").sink(receiveCompletion: { _ in }) { versions in
      let values = versions.mapValues { versionArray in
        versionArray.map { $0.value }
      }
      let expectedValues: [ScopedKey: [Value]] = ["key1": ["value 1"], "key2": ["updated"]]
      if values == expectedValues {
        readPublisherExpectation.fulfill()
      }
    }
    defer {
      readPublisherSubscription.cancel()
    }

    // In contrast, `updatedValuesPublisher` is "cold". It publishes only values that change after they change.
    let updatedValueExpectation = expectation(description: "updated value publisher")
    let valuesSubscription = alice.updatedValuesPublisher.sink { scopedKey, versions in
      XCTAssertEqual(scopedKey, "key2")
      XCTAssertEqual(try! versions.text, "updated")
      updatedValueExpectation.fulfill()
    }
    defer {
      valuesSubscription.cancel()
    }

    try alice.writeText("updated", to: "key2")

    waitForExpectations(timeout: 3)
  }

  func testUpdatedValuesPublisherOnMerge() throws {
    let alice = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob)

    try alice.writeText("alice's version", to: "shared")
    try bob.writeText("bob's version", to: "shared")
    try bob.writeText("bob solo", to: "bob")

    let sharedKeyExpectation = expectation(description: "shared key")
    let soloKeyExpectation = expectation(description: "solo key")

    let subscription = alice.updatedValuesPublisher.sink { scopedKey, versions in
      if scopedKey == "shared" {
        sharedKeyExpectation.fulfill()
      }
      if scopedKey == "bob" {
        soloKeyExpectation.fulfill()
        XCTAssertEqual(try? versions.text, "bob solo")
      }
    }
    defer {
      subscription.cancel()
    }

    try alice.merge(source: bob)
    waitForExpectations(timeout: 3)
  }

  func testApplicationIdentifier() throws {
    let database = try KeyValueDatabase(fileURL: nil, authorDescription: .alice)
    XCTAssertNil(try database.applicationIdentifier)
    try database.setApplicationIdentifier(.tests)
    XCTAssertEqual(try database.applicationIdentifier, .tests)
    try database.setApplicationIdentifier(.testsV2)
    XCTAssertEqual(try database.applicationIdentifier, .testsV2)
  }

  func testUnversionedDataUpgrade() throws {
    let storage = try DatabaseQueue(path: ":memory:")
    var didUpgradeData = false
    let upgrader = UpgradeToV2 {
      didUpgradeData = true
    }
    let database = try KeyValueDatabase(databaseWriter: storage, authorDescription: "first", upgrader: upgrader)
    XCTAssertTrue(didUpgradeData)
    XCTAssertEqual(try database.applicationIdentifier, upgrader.expectedApplicationIdentifier)

    var didUpgradeDataOnReopen = false
    let upgradeOnReopen = UpgradeToV2 {
      didUpgradeDataOnReopen = true
    }
    let d2 = try KeyValueDatabase(databaseWriter: storage, authorDescription: "second", upgrader: upgradeOnReopen)
    XCTAssertFalse(didUpgradeDataOnReopen)
    XCTAssertEqual(try d2.applicationIdentifier, upgrader.expectedApplicationIdentifier)
  }

  func testCannotOpenIncompatibleData() throws {
    let storage = try DatabaseQueue(path: ":memory:")
    let originalDatabase = try KeyValueDatabase(databaseWriter: storage, authorDescription: .alice, upgrader: UpgradeToV2(didUpgrade: {}))
    XCTAssertEqual(try originalDatabase.applicationIdentifier, .testsV2)
    XCTAssertThrowsError(try KeyValueDatabase(databaseWriter: storage, authorDescription: .bob, upgrader: DifferentApplicationUpgrader()))
  }

  func testCannotOpenTooNewData() throws {
    let storage = try DatabaseQueue(path: ":memory:")
    let original = try KeyValueDatabase(databaseWriter: storage, authorDescription: .bob)
    try original.setApplicationIdentifier(.tests)
    var didUpgrade = false
    let originalDatabase = try KeyValueDatabase(databaseWriter: storage, authorDescription: .alice, upgrader: UpgradeToV2(didUpgrade: { didUpgrade = true }))
    XCTAssertTrue(didUpgrade)
    XCTAssertEqual(try originalDatabase.applicationIdentifier, .testsV2)
    XCTAssertThrowsError(try KeyValueDatabase(databaseWriter: storage, authorDescription: .bob, upgrader: UpgradeToV1()))
  }

  func testCanOpenWithMinorDifference() throws {
    let storage = try DatabaseQueue(path: ":memory:")
    _ = try KeyValueDatabase(databaseWriter: storage, authorDescription: .alice, upgrader: GenericUpgrader(.testsV21))
    var didUpgrade = false
    let v2database = try KeyValueDatabase(databaseWriter: storage, authorDescription: .bob, upgrader: GenericUpgrader(.testsV2, upgradeBlock: { didUpgrade = true }))
    XCTAssertFalse(didUpgrade)
    XCTAssertEqual(try v2database.applicationIdentifier, .testsV21)
  }

  func testCannotMergeIncompatibleDatabases() throws {
    let aliceStorage = try DatabaseQueue(path: ":memory:")
    let alice = try KeyValueDatabase(databaseWriter: aliceStorage, authorDescription: .alice, upgrader: GenericUpgrader(.tests))
    let bob = try KeyValueDatabase(fileURL: nil, authorDescription: .bob, upgrader: GenericUpgrader(.testsV2))

    // Alice doesn't understand Bob, so this is an error.
    XCTAssertThrowsError(try alice.merge(source: bob))

    // This is also an error, because Alice should be upgraded.
    XCTAssertThrowsError(try bob.merge(source: alice))

    let upgradedAlice = try KeyValueDatabase(databaseWriter: aliceStorage, authorDescription: .alice, upgrader: GenericUpgrader(.testsV2))

    // now there shouldn't be an error
    try bob.merge(source: upgradedAlice)
  }
}

private struct UpgradeToV1: ApplicationDataUpgrader {
  var expectedApplicationIdentifier: ApplicationIdentifier = .tests

  func upgradeApplicationData(in database: KeyValueDatabase) throws {
    fatalError()
  }
}

private struct UpgradeToV2: ApplicationDataUpgrader {
  let expectedApplicationIdentifier: ApplicationIdentifier = .testsV2

  let didUpgrade: () -> Void

  func upgradeApplicationData(in database: KeyValueDatabase) throws {
    didUpgrade()
  }
}

private struct DifferentApplicationUpgrader: ApplicationDataUpgrader {
  let expectedApplicationIdentifier: ApplicationIdentifier = .differentApplication

  func upgradeApplicationData(in database: KeyValueDatabase) throws {
    fatalError()
  }
}

private enum TestKey {
  static let shared = "shared"
  static let alice = "alice"
  static let bob = "bob"
}

private extension String {
  static let alice = "Alice"
  static let bob = "Bob"
  static let charlie = "Charlie"
}
