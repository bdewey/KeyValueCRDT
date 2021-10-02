import Foundation
import KeyValueCRDT
import XCTest

final class UIKeyValueDocumentTests: XCTestCase {
  func testBasics() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("testBasics.kvcrdt")
    defer {
      try? FileManager.default.removeItem(at: url)
    }
    let document = try UIKeyValueDocument(fileURL: url, authorDescription: "testBasics")
    let openedExpectation = expectation(description: "opened")
    document.open { success in
      XCTAssertTrue(success)
      openedExpectation.fulfill()
    }
    waitForExpectations(timeout: 3)
    XCTAssertFalse(document.hasUnsavedChanges)
    try document.keyValueCRDT?.writeText("Hello, world", to: "test")
    XCTAssertTrue(document.hasUnsavedChanges)
    let closedExpectation = expectation(description: "closed")
    document.close { success in
      XCTAssertTrue(success)
      closedExpectation.fulfill()
    }
    waitForExpectations(timeout: 3)

    let roundTrip = try UIKeyValueDocument(fileURL: url, authorDescription: "testBasics")
    let rtOpen = expectation(description: "Round trip open")
    roundTrip.open { success in
      XCTAssertTrue(success)
      rtOpen.fulfill()
    }
    waitForExpectations(timeout: 3)
    let result = try roundTrip.keyValueCRDT!.read(key: "test")
    XCTAssertEqual(try result.text, "Hello, world")
    XCTAssertFalse(roundTrip.hasUnsavedChanges)
    let rtClose = expectation(description: "round trip close")
    roundTrip.close { success in
      XCTAssertTrue(success)
      rtClose.fulfill()
    }
    waitForExpectations(timeout: 3)
  }

  @available(iOS 15.0, *)
  func testUpgrader() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("testUpgrader.kvcrdt")
    defer {
      try? FileManager.default.removeItem(at: url)
    }

    let initialDocument = try await UIKeyValueDocument(fileURL: url, authorDescription: "test", upgrader: GenericUpgrader(.tests))
    await initialDocument.open()
    await initialDocument.save(to: url, for: .forCreating)
    await initialDocument.close()

    var didUpgrade = false
    let secondDocument = try await UIKeyValueDocument(fileURL: url, authorDescription: "testv2", upgrader: GenericUpgrader(.testsV2, upgradeBlock: { didUpgrade = true }))
    let secondOpenSuccess = await secondDocument.open()
    XCTAssertTrue(secondOpenSuccess)
    try await secondDocument.keyValueCRDT?.writeText("Hello, world", to: "greeting")
    await secondDocument.close()
    XCTAssertTrue(didUpgrade)

    let downgradeDocument = try await UIKeyValueDocument(fileURL: url, authorDescription: "test", upgrader: GenericUpgrader(.tests))
    let downgradeSuccess = await downgradeDocument.open()
    XCTAssertFalse(downgradeSuccess)
  }
}
