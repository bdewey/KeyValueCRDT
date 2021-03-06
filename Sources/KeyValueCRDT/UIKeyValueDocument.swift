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
    /// Called before using ``KeyValueCRDT/KeyValueDatabase/merge(source:)`` to merge **conflicting** copies of the CRDT.
    ///
    /// This is a useful hook for making backup copies of the CRDT in case something goes wrong!
    func keyValueDocument(_ document: UIKeyValueDocument, willMergeCRDT sourceCRDT: KeyValueDatabase, into destinationCRDT: KeyValueDatabase)
  }

  private struct UpgraderWrapper: ApplicationDataUpgrader {
    let upgrader: ApplicationDataUpgrader
    let document: UIKeyValueDocument

    init?(_ upgrader: ApplicationDataUpgrader?, document: UIKeyValueDocument) {
      guard let upgrader = upgrader else {
        return nil
      }
      self.upgrader = upgrader
      self.document = document
    }

    var expectedApplicationIdentifier: ApplicationIdentifier { upgrader.expectedApplicationIdentifier }

    func upgradeApplicationData(in database: KeyValueDatabase) throws {
      try upgrader.upgradeApplicationData(in: database)
      document.updateChangeCount(.done)
      Logger.keyValueDocument.info("Upgraded data in database to version \(expectedApplicationIdentifier)")
    }
  }

  /// A UIDocument subclass that provides access to a key-value CRDT database.
  ///
  /// Because it is a `UIDocument` subclass, it interoperates with the iOS mechanisms for coordinating access to files via `NSFileCoordinator` and `NSFilePresenter`.
  /// This lets you use a `UIKeyValueDocument` for documents that will be stored in iCloud Documents, among other places.
  ///
  /// In iOS, successfully working with services like iCloud involves careful coordination of I/O with other services, and natively sqlite does not know how to do this.
  /// Therefore, `UIKeyValueDocument` reads the entire database into memory, works on the in-memory copy, and writes the entire database to disk when it needs to
  /// coordinate with other proceses. Therefore, you should exclusively use `UIKeyValueDocument` for "document-sized" purposes, where reading/writing the entire
  /// document is feasible. If you do not want to read the entire contents of a key/value CRDT into memory at once, you should work directly with ``KeyValueDatabase``.
  /// ``KeyValueDatabase`` loads data on-demand but does not interoperate with the document replication mechanisms in iOS.
  public final class UIKeyValueDocument: UIDocument {
    /// Designated initializer.
    ///
    /// - parameter fileURL: The URL for the key-value CRDT database.
    /// - parameter author: An ``Author`` struct that identifies all changes made by this instance.
    public init(fileURL: URL, authorDescription: String, upgrader: ApplicationDataUpgrader? = nil) throws {
      self.authorDescription = authorDescription
      self.upgrader = upgrader
      super.init(fileURL: fileURL)
    }

    public weak var delegate: UIKeyValueDocumentDelegate?

    /// A human-readable hint identifying the author of any changes made from this instance.
    public let authorDescription: String

    public let upgrader: ApplicationDataUpgrader?

    /// The key-value CRDT stored in the document.
    ///
    /// This value is `nil` upon creating a document and will be non-nil after opening it.
    public private(set) var keyValueCRDT: KeyValueDatabase?

    /// Pipeline for monitoring for unsaved changes to the in-memory database.
    private var hasUnsavedChangesPipeline: AnyCancellable?

    override public func open(completionHandler: ((Bool) -> Void)? = nil) {
      Logger.keyValueDocument.info("Opening \(fileURL.path)")
      super.open { success in
        Logger.keyValueDocument.info("Opened '\(self.fileURL.path)' -- success = \(success) state = \(self.documentState)")
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(self.handleDocumentStateChanged),
          name: UIDocument.stateChangedNotification,
          object: self
        )
        if self.keyValueCRDT != nil {
          self.startMonitoringChanges()
        }
        self.handleDocumentStateChanged()
        completionHandler?(success)
      }
    }

    override public func close(completionHandler: ((Bool) -> Void)? = nil) {
      // Remove-on-deinit doesn't apply to UIDocument, it seems to me. These have an explicit open/close lifecycle.
      Logger.keyValueDocument.info("Closing \(fileURL.path)")
      stopMonitoringChanges()
      NotificationCenter.default.removeObserver(self) // swiftlint:disable:this notification_center_detachment
      super.close(completionHandler: completionHandler)
    }

    override public func save(to url: URL, for saveOperation: UIDocument.SaveOperation, completionHandler: ((Bool) -> Void)? = nil) {
      Logger.keyValueDocument.info("Saving \(url.path)")
      super.save(to: url, for: saveOperation) { success in
        Logger.keyValueDocument.info("Save finished. Success = \(success)")
        completionHandler?(success)
      }
    }

    override public func read(from url: URL) throws {
      Logger.keyValueDocument.info("Reading from \(url.path)")
      stopMonitoringChanges()
      do {
        let onDiskDataQueue = try memoryDatabaseQueue(fileURL: url)
        let wrappedUpgrader = UpgraderWrapper(upgrader, document: self)
        let onDiskData = try KeyValueDatabase(databaseWriter: onDiskDataQueue, authorDescription: authorDescription, upgrader: wrappedUpgrader)
        if let keyValueCRDT = keyValueCRDT {
          if try keyValueCRDT.dominates(other: onDiskData) {
            Logger.keyValueDocument.info("Ignoring read from \(url.path) because it contains no new information")
          } else {
            // Neither dominate. Merge disk contents into memory.
            Logger.keyValueDocument.info("Merging contents of \(url.path) with in-memory data")
            let changedEntries = try keyValueCRDT.merge(source: onDiskData)
            Logger.keyValueDocument.info("Updated keys from merge: \(changedEntries.count)")
          }
        } else {
          Logger.keyValueDocument.info("Loading initial copy of database into memory")
          keyValueCRDT = onDiskData
        }
        startMonitoringChanges()
      } catch {
        Logger.keyValueDocument.error("Error opening \(url.path): \(error)")
        throw error
      }
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
      try keyValueCRDT?.save(to: url)
      Logger.keyValueDocument.debug("document save finished")
    }
  }

  // MARK: - Private

  private extension UIKeyValueDocument {
    @objc func handleDocumentStateChanged() {
      guard documentState.contains(.inConflict), let keyValueCRDT = keyValueCRDT else {
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
          let conflictCRDT = try KeyValueDatabase(databaseWriter: conflictQueue, authorDescription: authorDescription)
          delegate?.keyValueDocument(self, willMergeCRDT: conflictCRDT, into: keyValueCRDT)
          let updates = try keyValueCRDT.merge(source: conflictCRDT)
          Logger.keyValueDocument.info("UIDocument: Merged conflict version: \(conflictVersion). Updates = \(updates)")
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
      guard let keyValueCRDT = keyValueCRDT else {
        assertionFailure()
        return
      }
      hasUnsavedChangesPipeline = keyValueCRDT.didChangePublisher().sink(receiveCompletion: { completion in
        switch completion {
        case .failure(let error):
          Logger.keyValueDocument.error("Unexpected error monitoring database: \(error)")
          assertionFailure()
        case .finished:
          Logger.keyValueDocument.info("Monitoring pipeline shutting down")
        }
      }, receiveValue: { [weak self] _ in
        self?.updateChangeCount(.done)
      })
    }

    func stopMonitoringChanges() {
      hasUnsavedChangesPipeline?.cancel()
      hasUnsavedChangesPipeline = nil
    }
  }

#endif
