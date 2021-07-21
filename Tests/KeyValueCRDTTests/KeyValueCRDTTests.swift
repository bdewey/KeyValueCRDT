import Foundation
import KeyValueCRDT
import XCTest

final class KeyValueCRDTTests: XCTestCase {
  func testSimpleStorage() throws {
    let crdt = try KeyValueCRDT(fileURL: nil, author: Author(id: UUID(), name: "test"))
    try crdt.writeText("Hello, world!", to: "key")
    let result = try crdt.read(key: "key")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.value, .text("Hello, world!"))
  }

  func testMultipleWritesFromOneAuthorMakeOneVersion() throws {
    let crdt = try KeyValueCRDT(fileURL: nil, author: Author(id: UUID(), name: "test"))
    try crdt.writeText("Hello, world!", to: "key")
    try crdt.writeText("Goodbye, world!", to: "key")
    let result = try crdt.read(key: "key")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.value, .text("Goodbye, world!"))
  }

  func testDelete() throws {
    let crdt = try KeyValueCRDT(fileURL: nil, author: Author(id: UUID(), name: "test"))
    try crdt.writeText("Hello, world!", to: "key")
    try crdt.delete(key: "key")
    let result = try crdt.read(key: "key")
    XCTAssertEqual(result.count, 0)
  }

  func testMerge() throws {
    let alice = try KeyValueCRDT(fileURL: nil, author: .alice)
    let bob = try KeyValueCRDT(fileURL: nil, author: .bob)

    try alice.writeText("alice", to: TestKey.alice)
    try alice.writeText("alice shared", to: TestKey.shared)

    try bob.writeText("bob", to: TestKey.bob)
    try bob.writeText("bob shared", to: TestKey.shared)

    try alice.merge(source: bob)
    XCTAssertEqual(try alice.read(key: TestKey.alice).text, "alice")
    XCTAssertEqual(try alice.read(key: TestKey.bob).text, "bob")
    XCTAssertEqual(try alice.read(key: TestKey.shared).count, 2)
  }

  func testMergeDoesNotAllowTimeTravel() throws {
    let original = try KeyValueCRDT(fileURL: nil, author: .alice)
    try original.writeText("Version 1", to: "test")
    let modified = try KeyValueCRDT(databaseWriter: try original.makeMemoryDatabaseQueue(), author: .alice)
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
    let original = try KeyValueCRDT(fileURL: nil, author: .alice)
    try original.writeText("Version 1", to: "test")
    let modified = try KeyValueCRDT(databaseWriter: try original.makeMemoryDatabaseQueue(), author: .alice)
    try modified.writeText("Version 2", to: "test")

    // Changing `modified` doesn't change `original`
    XCTAssertEqual(try original.read(key: "test").text, "Version 1")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")

    try original.merge(source: modified)
    XCTAssertEqual(try original.read(key: "test").text, "Version 2")
    XCTAssertEqual(try modified.read(key: "test").text, "Version 2")
  }
}

private enum TestKey {
  static let shared = "shared"
  static let alice = "alice"
  static let bob = "bob"
}

private extension Author {
  static let alice = Author(id: UUID(), name: "Alice")
  static let bob = Author(id: UUID(), name: "Bob")
}
