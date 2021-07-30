#if os(iOS)

import Combine
import GRDB
import Logging
import UIKit

private extension Logger {
  static let keyValueDocument: Logger = {
    var logger = Logger(label: "org.brians-brain.KeyValueCRDT.UIKeyValueDocument")
    logger.logLevel = .debug
    return logger
  }()
}

public protocol UIKeyValueDocumentDelegate: AnyObject {
  /// Called before using ``KeyValueCRDT/KeyValueCRDT/merge(source:)`` to merge **conflicting** copies of the CRDT.
  ///
  /// This is a useful hook for making backup copies of the CRDT in case something goes wrong!
  func keyValueDocument(_ document: UIKeyValueDocument, willMergeCRDT sourceCRDT: KeyValueCRDT, into destinationCRDT: KeyValueCRDT)
}

/// A UIDocument subclass that provides access to a key-value CRDT database.
///
/// Because it is a `UIDocument` subclass, it interoperates with the iOS mechanisms for coordinating access to files via `NSFileCoordinator` and `NSFilePresenter`.
/// This lets you use a `UIKeyValueDocument` for documents that will be stored in iCloud Documents, among other places.
///
/// In iOS, successfully working with services like iCloud involves careful coordination of I/O with other services, and natively sqlite does not know how to do this.
/// Therefore, `UIKeyValueDocument` reads the entire database into memory, works on the in-memory copy, and writes the entire database to disk when it needs to
/// coordinate with other proceses. Therefore, you should exclusively use `UIKeyValueDocument` for "document-sized" purposes, where reading/writing the entire
/// document is feasible. If you do not want to read the entire contents of a key/value CRDT into memory at once, you should work directly with ``KeyValueCRDT``.
/// ``KeyValueCRDT`` loads data on-demand but does not interoperate with the document replication mechanisms in iOS.
public final class UIKeyValueDocument: UIDocument {
  /// Designated initializer.
  ///
  /// - parameter fileURL: The URL for the key-value CRDT database.
  /// - parameter author: An ``Author`` struct that identifies all changes made by this instance.
  public init(fileURL: URL, author: Author) throws {
    self.author = author
    self.keyValueCRDT = try KeyValueCRDT(fileURL: nil, author: author)
    super.init(fileURL: fileURL)
    startMonitoringChanges()
  }

  public weak var delegate: UIKeyValueDocumentDelegate?

  /// The ``Author`` identifying changes made by this instance.
  public let author: Author

  /// The key-value CRDT stored in the document.
  public let keyValueCRDT: KeyValueCRDT

  /// Pipeline for monitoring for unsaved changes to the in-memory database.
  private var hasUnsavedChangesPipeline: AnyCancellable?

  public override func open(completionHandler: ((Bool) -> Void)? = nil) {
    super.open { success in
      Logger.keyValueDocument.info("Opened '\(self.fileURL.path)' -- success = \(success) state = \(self.documentState)")
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(self.handleDocumentStateChanged),
        name: UIDocument.stateChangedNotification,
        object: self
      )
      self.handleDocumentStateChanged()
      completionHandler?(success)
    }
  }

  public override func close(completionHandler: ((Bool) -> Void)? = nil) {
    // Remove-on-deinit doesn't apply to UIDocument, it seems to me. These have an explicit open/close lifecycle.
    Logger.keyValueDocument.info("Closing \(fileURL.path)")
    stopMonitoringChanges()
    NotificationCenter.default.removeObserver(self) // swiftlint:disable:this notification_center_detachment
    super.close(completionHandler: completionHandler)
  }

  public override func read(from url: URL) throws {
    Logger.keyValueDocument.info("Reading from \(url.path)")
    stopMonitoringChanges()
    defer {
      startMonitoringChanges()
    }
    let onDiskDataQueue = try memoryDatabaseQueue(fileURL: url)
    let onDiskData = try KeyValueCRDT(databaseWriter: onDiskDataQueue, author: author)
    if try keyValueCRDT.dominates(other: onDiskData) {
      Logger.keyValueDocument.info("Ignoring read from \(url.path) because it contains no new information")
      return
    }
    if try onDiskData.dominates(other: keyValueCRDT) {
      Logger.keyValueDocument.info("Data at \(url.path) dominates the in-memory info; replacing all in-memory data.")
      try onDiskData.backup(to: keyValueCRDT)
      return
    }
    // Neither dominate. Merge disk contents into memory.
    Logger.keyValueDocument.info("Merging contents of \(url.path) with in-memory data")
    delegate?.keyValueDocument(self, willMergeCRDT: onDiskData, into: keyValueCRDT)
    try keyValueCRDT.merge(source: onDiskData)
  }

  override public func writeContents(
    _ contents: Any,
    to url: URL,
    for saveOperation: UIDocument.SaveOperation,
    originalContentsURL: URL?
  ) throws {
    guard hasUnsavedChanges else {
      return
    }
    Logger.keyValueDocument.info("document state \(documentState): Writing content to '\(url.path)'")
    try keyValueCRDT.save(to: url)
  }
}

// MARK: - Private
private extension UIKeyValueDocument {
  @objc func handleDocumentStateChanged() {
    guard documentState.contains(.inConflict) else {
      return
    }
    Logger.keyValueDocument.info("Handling conflict")
    do {
      for conflictVersion in NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? [] {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kvcrdt")
        try conflictVersion.replaceItem(at: tempURL, options: [])
        defer {
          try? FileManager.default.removeItem(at: tempURL)
        }
        let conflictQueue = try memoryDatabaseQueue(fileURL: tempURL)
        let conflictCRDT = try KeyValueCRDT(databaseWriter: conflictQueue, author: author)
        delegate?.keyValueDocument(self, willMergeCRDT: conflictCRDT, into: keyValueCRDT)
        try keyValueCRDT.merge(source: conflictCRDT)
        Logger.keyValueDocument.info("UIDocument: Merged conflict version: \(conflictVersion)")
        conflictVersion.isResolved = true
        try conflictVersion.remove()
      }
      Logger.keyValueDocument.info("UIDocument: Finished resolving conflicts")
      try NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
    } catch {
      Logger.keyValueDocument.error("UIDocument: Unexpected error resolving conflict: \(error)")
    }
  }

  /// Creates an in-memory database queue for the contents of the file at `fileURL`
  /// - note: If fileURL does not exist, this method returns an empty database queue.
  /// - parameter fileURL: The file URL to read.
  /// - returns: An in-memory database queue with the contents of fileURL.
  func memoryDatabaseQueue(fileURL: URL) throws -> DatabaseQueue {
    let coordinator = NSFileCoordinator(filePresenter: self)
    var coordinatorError: NSError?
    var result: Result<DatabaseQueue, Swift.Error>?
    coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { coordinatedURL in
      result = Result {
        let queue = try DatabaseQueue(path: ":memory:")
        do {
          let didGetAccess = coordinatedURL.startAccessingSecurityScopedResource()
          defer {
            if didGetAccess {
              coordinatedURL.stopAccessingSecurityScopedResource()
            }
          }
          let fileQueue = try DatabaseQueue(path: coordinatedURL.path)
          try fileQueue.backup(to: queue)
        } catch {
          Logger.keyValueDocument.info("Unable to load \(coordinatedURL.path): \(error)")
        }
        return queue
      }
    }

    if let coordinatorError = coordinatorError {
      throw coordinatorError
    }

    switch result {
    case .failure(let error):
      throw error
    case .success(let dbQueue):
      return dbQueue
    case .none:
      preconditionFailure()
    }
  }

  func startMonitoringChanges() {
    do {
      hasUnsavedChangesPipeline = try keyValueCRDT.didChangePublisher().sink(receiveCompletion: { completion in
        switch completion {
        case .failure(let error):
          Logger.keyValueDocument.error("Unexpected error monitoring database: \(error)")
        case .finished:
          Logger.keyValueDocument.info("Monitoring pipeline shutting down")
        }
      }, receiveValue: { [weak self] _ in
        self?.updateChangeCount(.done)
      })
    } catch {
      Logger.keyValueDocument.error("Unable to monitor changes for \(fileURL) -- document updates will not save. \(error)")
      assertionFailure()
    }
  }

  func stopMonitoringChanges() {
    hasUnsavedChangesPipeline?.cancel()
    hasUnsavedChangesPipeline = nil
  }
}

#endif
